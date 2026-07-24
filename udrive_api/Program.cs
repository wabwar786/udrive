using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using UDrive.Api.Infrastructure.Persistence;
using UDrive.Api.Middleware;
using UDrive.Api.Services;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls($"http://0.0.0.0:{Environment.GetEnvironmentVariable("PORT") ?? "8080"}");

var connectionString = ConnectionStringFactory.Resolve(builder.Configuration);

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddHttpContextAccessor();

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
