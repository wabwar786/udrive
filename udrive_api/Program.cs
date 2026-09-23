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
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls($"http://0.0.0.0:{Environment.GetEnvironmentVariable("PORT") ?? "8080"}");

var connectionString = ConnectionStringFactory.Resolve(builder.Configuration);

// Named client for the Places proxy. Nominatim requires a descriptive
// User-Agent, which a server can send but a browser cannot — one of the reasons
// address search is proxied here instead of called from the app.
builder.Services.AddHttpClient("places", client =>
{
    client.Timeout = TimeSpan.FromSeconds(12);
    client.DefaultRequestHeaders.Add("User-Agent", "UDrive-API/1.0 (+https://udrive.pk)");
    client.DefaultRequestHeaders.Add("Accept-Language", "en");
});
var authOptions = AuthOptions.FromEnvironment();

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton(authOptions);
builder.Services.AddSingleton(new AuthSqlStore(connectionString));
builder.Services.AddSingleton<LocalFileStorageService>();
builder.Services.AddSingleton(sp => new ProductionMaintenanceService(
    connectionString,
    sp.GetRequiredService<ILogger<ProductionMaintenanceService>>()));
builder.Services.AddHostedService(sp => sp.GetRequiredService<ProductionMaintenanceService>());

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
builder.Services.AddScoped<MarketplacePricingService>(_ => new MarketplacePricingService(connectionString));
builder.Services.AddScoped<PricingRulesService>(_ => new PricingRulesService(connectionString));
builder.Services.AddScoped<TourRatesService>(_ => new TourRatesService(connectionString));
builder.Services.AddScoped<SeatFaresService>(_ => new SeatFaresService(connectionString));
builder.Services.AddScoped<TripChatService>(_ => new TripChatService(connectionString));
builder.Services.AddScoped<ServiceAvailabilityService>(_ =>
    new ServiceAvailabilityService(connectionString));
builder.Services.AddScoped<DriverWalletService>(serviceProvider =>
    new DriverWalletService(
        connectionString,
        serviceProvider.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<JwtTokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton(new AccountDeletionService(connectionString));
builder.Services.AddHttpClient(OtpDeliveryService.HttpClientName, client =>
{
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddSingleton(sp => new OtpDeliveryService(
    connectionString,
    authOptions,
    sp.GetRequiredService<IHttpClientFactory>(),
    sp.GetRequiredService<ILogger<OtpDeliveryService>>()));
builder.Services.AddScoped<DriverVerificationService>(serviceProvider =>
    new DriverVerificationService(
        connectionString,
        serviceProvider.GetRequiredService<AuthOptions>(),
        serviceProvider.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<AdminVerificationService>(serviceProvider =>
    new AdminVerificationService(
        connectionString,
        serviceProvider.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<BookingService>(_ =>
    new BookingService(
        connectionString,
        authOptions,
        new ServiceAvailabilityService(connectionString)));
builder.Services.AddScoped<PackageMarketplaceService>(_ =>
    new PackageMarketplaceService(connectionString, authOptions));
builder.Services.AddScoped<TourInterestService>(_ =>
    new TourInterestService(connectionString));
builder.Services.AddScoped<AdminOperationsService>(sp =>
    new AdminOperationsService(connectionString, sp.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<AdminUserManagementService>(_ =>
    new AdminUserManagementService(connectionString));
builder.Services.AddScoped<TripOperationsService>(_ => new TripOperationsService(connectionString, authOptions));
builder.Services.AddScoped<TrackingService>(_ => new TrackingService(connectionString));
builder.Services.AddScoped<FinanceService>(_ => new FinanceService(connectionString));
builder.Services.AddScoped<PaymentService>(_ => new PaymentService(connectionString));
builder.Services.AddScoped<FeedbackService>(sp => new FeedbackService(connectionString, sp.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<CommunicationService>(_ => new CommunicationService(connectionString));
builder.Services.AddHttpClient<WhatsAppService>(client =>
{
    var baseUrl = Environment.GetEnvironmentVariable("WA_ENGINE_BASE_URL")
        ?? builder.Configuration["WA_ENGINE_BASE_URL"]
        ?? "https://wa-engine-deploy-production.up.railway.app/";
    client.BaseAddress = new Uri(baseUrl.EndsWith('/') ? baseUrl : $"{baseUrl}/");
    client.Timeout = TimeSpan.FromSeconds(20);
});
builder.Services.AddScoped<SafetyService>(_ => new SafetyService(connectionString));
builder.Services.AddScoped<Phase18TourService>(_ => new Phase18TourService(connectionString));
builder.Services.AddScoped<Phase19AdminService>(_ => new Phase19AdminService(connectionString));
builder.Services.AddScoped<HotelService>(_ => new HotelService(connectionString));
builder.Services.AddScoped<AdminDataService>(sp =>
    new AdminDataService(connectionString, sp.GetRequiredService<ILogger<AdminDataService>>()));
builder.Services.AddScoped<VerificationFileLookupService>(serviceProvider =>
    new VerificationFileLookupService(
        connectionString,
        serviceProvider.GetRequiredService<LocalFileStorageService>()));

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
                    user.AccountStatus is "Suspended" or "Rejected" or "Deleted")
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
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 300,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.OnRejected = async (context, cancellationToken) =>
    {
        context.HttpContext.Response.ContentType = "application/problem+json";
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            status = StatusCodes.Status429TooManyRequests,
            title = "Too many requests.",
            detail = "Please wait a moment and try again.",
            traceId = context.HttpContext.TraceIdentifier
        }, cancellationToken);
    };
    options.AddFixedWindowLimiter("location", limiter =>
    {
        limiter.PermitLimit = 40;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
        limiter.AutoReplenishment = true;
    });
    options.AddFixedWindowLimiter("public-tracking", limiter =>
    {
        limiter.PermitLimit = 60;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
        limiter.AutoReplenishment = true;
    });
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
builder.Services.AddSwaggerGen(options =>
{
    options.CustomSchemaIds(type => (type.FullName ?? type.Name).Replace("+", ".", StringComparison.Ordinal));
    options.SupportNonNullableReferenceTypes();
});
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

ProductionConfigurationValidator.Validate(
    app.Environment,
    authOptions,
    app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("ProductionConfiguration"));

app.UseExceptionHandler();
app.UseMiddleware<RequestContextMiddleware>();
app.UseMiddleware<SecurityHeadersMiddleware>();
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

// First portal password, set from Railway variables.
//
// The portal needs a password before anyone can sign in to set one — this is
// the way in. ADMIN_BOOTSTRAP_PHONE names an existing portal user;
// ADMIN_BOOTSTRAP_USERNAME and ADMIN_BOOTSTRAP_PASSWORD are what they will
// type. It only writes when the account has no password yet, unless
// ADMIN_BOOTSTRAP_FORCE=true, so leaving the variables in place does not keep
// resetting a password the admin later changed.
{
    var bootstrapPhone = Environment.GetEnvironmentVariable("ADMIN_BOOTSTRAP_PHONE");
    var bootstrapUsername = Environment.GetEnvironmentVariable("ADMIN_BOOTSTRAP_USERNAME");
    var bootstrapPassword = Environment.GetEnvironmentVariable("ADMIN_BOOTSTRAP_PASSWORD");
    if (!string.IsNullOrWhiteSpace(bootstrapPhone) &&
        !string.IsNullOrWhiteSpace(bootstrapUsername) &&
        !string.IsNullOrWhiteSpace(bootstrapPassword))
    {
        await using var scope = app.Services.CreateAsyncScope();
        var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("AdminBootstrap");
        var store = scope.ServiceProvider.GetRequiredService<AuthSqlStore>();
        var authService = scope.ServiceProvider.GetRequiredService<AuthService>();
        try
        {
            if (!PhoneNumberNormalizer.TryNormalizePakistan(bootstrapPhone, out var normalisedPhone))
            {
                logger.LogError("ADMIN_BOOTSTRAP_PHONE is not a valid Pakistani mobile number.");
            }
            else
            {
                var existing = await store.GetUserByPhoneAsync(normalisedPhone, CancellationToken.None);
                var force = string.Equals(
                    Environment.GetEnvironmentVariable("ADMIN_BOOTSTRAP_FORCE"),
                    "true",
                    StringComparison.OrdinalIgnoreCase);
                var alreadySet = existing is not null &&
                    await store.GetPasswordHashAsync(existing.Id, CancellationToken.None) is not null;

                if (existing is null)
                {
                    logger.LogError(
                        "ADMIN_BOOTSTRAP_PHONE {Phone} has no account yet. Sign in once with OTP, give it a portal role, then redeploy.",
                        normalisedPhone);
                }
                else if (alreadySet && !force)
                {
                    logger.LogInformation("Portal password already set for {Phone}; bootstrap skipped.", normalisedPhone);
                }
                else
                {
                    var result = await authService.SetPortalCredentialsAsync(
                        new SetPortalCredentialsRequest(normalisedPhone, bootstrapUsername!, bootstrapPassword!),
                        CancellationToken.None);
                    if (result.Success)
                    {
                        logger.LogWarning(
                            "Portal credentials bootstrapped for {Username}. Remove ADMIN_BOOTSTRAP_PASSWORD from the environment now.",
                            bootstrapUsername);
                    }
                    else
                    {
                        logger.LogError("Portal bootstrap failed: {Message}", result.Message);
                    }
                }
            }
        }
        catch (Exception exception)
        {
            // A broken bootstrap must never stop the API from serving rides.
            logger.LogError(exception, "Portal credential bootstrap failed.");
        }
    }
}

app.MapControllers();
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
});
app.MapHealthChecks("/health/ready");

app.Run();

public partial class Program;
