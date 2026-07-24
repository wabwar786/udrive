using System.Security.Claims;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using UDrive.Api.Infrastructure.Persistence;
using UDrive.Api.Middleware;
using UDrive.Api.Services;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls($"http://0.0.0.0:{Environment.GetEnvironmentVariable("PORT") ?? "8080"}");

var connectionString = ConnectionStringFactory.Resolve(builder.Configuration);
var authOptions = AuthOptions.FromEnvironment();

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton(authOptions);
builder.Services.AddSingleton(new AuthSqlStore(connectionString));
builder.Services.AddSingleton<LocalFileStorageService>();

builder.Services.AddDbContextPool<UDriveDbContext>(options =>
{
    options.UseNpgsql(
        connectionString,
        npgsql => npgsql
            .UseNetTopologySuite()
            .EnableRetryOnFailure(5, TimeSpan.FromSeconds(10), null))
        .UseSnakeCaseNamingConvention();
});

builder.Services.AddScoped<SqlMigrationRunner>();
builder.Services.AddScoped<CatalogService>();
builder.Services.AddScoped<JwtTokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<DriverVerificationService>(serviceProvider =>
    new DriverVerificationService(
        connectionString,
        serviceProvider.GetRequiredService<AuthOptions>(),
        serviceProvider.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<AdminVerificationService>(_ =>
    new AdminVerificationService(connectionString));

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = authOptions.Issuer,
            ValidateAudience = true,
            ValidAudience = authOptions.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(authOptions.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role
        };
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                var userIdValue = context.Principal?.FindFirstValue(ClaimTypes.NameIdentifier)
                    ?? context.Principal?.FindFirstValue("sub");
                var versionValue = context.Principal?.FindFirstValue("token_version");
                if (!Guid.TryParse(userIdValue, out var userId) ||
                    !int.TryParse(versionValue, out var tokenVersion))
                {
                    context.Fail("The access token does not contain valid security claims.");
                    return;
                }

                var store = context.HttpContext.RequestServices.GetRequiredService<AuthSqlStore>();
                var user = await store.GetUserByIdAsync(userId, context.HttpContext.RequestAborted);
                if (user is null ||
                    user.TokenVersion != tokenVersion ||
                    user.AccountStatus is "Suspended" or "Rejected")
                {
                    context.Fail("The account session is no longer valid.");
                }
            }
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddFixedWindowLimiter("otp", limiter =>
    {
        limiter.PermitLimit = 8;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
        limiter.AutoReplenishment = true;
    });
});

builder.Services
    .AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
        options.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
    });

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHealthChecks().AddDbContextCheck<UDriveDbContext>("postgresql");

var allowedOrigins = (Environment.GetEnvironmentVariable("ALLOWED_ORIGINS") ?? string.Empty)
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

builder.Services.AddCors(options =>
{
    options.AddPolicy("UDriveClients", policy =>
    {
        if (allowedOrigins.Length == 0)
        {
            policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
            return;
        }

        policy.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod();
    });
});

var app = builder.Build();

app.UseExceptionHandler();
app.UseMiddleware<RequestContextMiddleware>();
app.UseCors("UDriveClients");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment() ||
    string.Equals(Environment.GetEnvironmentVariable("ENABLE_SWAGGER"), "true", StringComparison.OrdinalIgnoreCase))
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

var autoMigrate = !string.Equals(
    Environment.GetEnvironmentVariable("AUTO_APPLY_MIGRATIONS"),
    "false",
    StringComparison.OrdinalIgnoreCase);

if (autoMigrate)
{
    await using var scope = app.Services.CreateAsyncScope();
    var runner = scope.ServiceProvider.GetRequiredService<SqlMigrationRunner>();
    await runner.ApplyPendingAsync();
}

app.MapControllers();
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
});
app.MapHealthChecks("/health/ready");

app.Run();

public partial class Program;
