using System.Security.Claims;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
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
// Singleton: the documents are embedded in the assembly and never change at
// runtime, so they are parsed and rendered once per process.
builder.Services.AddSingleton<LegalDocumentService>();
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

// ------------------------------------------------------------------ pricing
//
// The fare engine and the four inputs it reads. Settings and demand are
// singletons because both hold a short-lived cache that is only worth having
// if it outlives a request; everything else is scoped like its neighbours.
builder.Services.AddSingleton(new PricingSettingsService(connectionString));
builder.Services.AddSingleton(new DemandService(connectionString));
builder.Services.AddSingleton(new QuoteTokenService(authOptions));
builder.Services.AddScoped<FuelPriceService>(_ => new FuelPriceService(connectionString));
builder.Services.AddScoped<PricingZoneService>(_ => new PricingZoneService(connectionString));
builder.Services.AddScoped<RateInsightsService>(_ => new RateInsightsService(connectionString));
builder.Services.AddScoped<FareEngine>(serviceProvider =>
    new FareEngine(
        connectionString,
        serviceProvider.GetRequiredService<MarketplacePricingService>(),
        serviceProvider.GetRequiredService<SeatFaresService>(),
        serviceProvider.GetRequiredService<PricingZoneService>(),
        serviceProvider.GetRequiredService<DemandService>(),
        serviceProvider.GetRequiredService<FuelPriceService>(),
        serviceProvider.GetRequiredService<PricingSettingsService>(),
        serviceProvider.GetRequiredService<QuoteTokenService>()));
builder.Services.AddScoped<TripChatService>(_ => new TripChatService(connectionString));
builder.Services.AddScoped<ServiceAvailabilityService>(_ =>
    new ServiceAvailabilityService(connectionString));
builder.Services.AddScoped<DriverWalletService>(serviceProvider =>
    new DriverWalletService(
        connectionString,
        serviceProvider.GetRequiredService<LocalFileStorageService>()));
builder.Services.AddScoped<JwtTokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton(sp => new AccountDeletionService(
    connectionString,
    sp.GetRequiredService<LocalFileStorageService>()));
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
builder.Services.AddScoped<BookingService>(serviceProvider =>
    new BookingService(
        connectionString,
        authOptions,
        new ServiceAvailabilityService(connectionString),
        serviceProvider.GetRequiredService<QuoteTokenService>(),
        serviceProvider.GetRequiredService<PricingSettingsService>()));
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
    // Each named policy is PER CALLER, not one bucket for the whole platform.
    //
    // These three were written with options.AddFixedWindowLimiter(name, …),
    // which registers a single FixedWindowRateLimiter partitioned on the policy
    // name — a constant. Every caller therefore shared one allowance, and the
    // numbers below only make sense per caller:
    //
    //   * "location" — 40/min. A driver pings every 2 seconds, so 30/min each.
    //     TWO online drivers filled the bucket; from the third onward every
    //     location write returned 429 and live tracking stopped working for
    //     the entire platform.
    //   * "otp" — 8/min across sign-in, admin login and account deletion. Nine
    //     sign-in attempts anywhere in one minute and the tenth person — quite
    //     possibly the Play reviewer — was told to wait.
    //   * "public-tracking" — 60/min for every shared trip link at once.
    //
    // It never showed up in testing, where you are the only caller. The global
    // limiter above was already partitioned correctly; these now match it.
    //
    // The key is the client IP, which is only meaningful because
    // UseForwardedHeaders runs first — see where the app is built below.
    // UseRateLimiter sits ahead of UseAuthentication, so HttpContext.User is
    // not populated here and the caller's identity is not available to key on.
    static RateLimitPartition<string> PerCaller(HttpContext context, int permitLimit) =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = permitLimit,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            });

    options.AddPolicy("location", context => PerCaller(context, 40));
    options.AddPolicy("public-tracking", context => PerCaller(context, 60));
    options.AddPolicy("otp", context => PerCaller(context, 8));

    // Every call under /api/v1/places spends the admin-configured Google key
    // (Routes computeRoutes and Place Details are among the pricier SKUs) and
    // the controller is anonymous by design, because the app needs address
    // search before anybody has signed in. Without its own allowance a script
    // can run up the billing account or exhaust the global limiter for
    // everyone else. Map tiles get a larger one because a single pan of the
    // map legitimately fetches a screenful at a time.
    options.AddPolicy("places", context => PerCaller(context, 60));
    options.AddPolicy("map-tiles", context => PerCaller(context, 240));
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
        // An empty ALLOWED_ORIGINS used to mean AllowAnyOrigin() — a missing
        // variable opened the API to every website on the internet, with only
        // a log line to say so. It now means what it says: no browser origin
        // is allowed. The mobile app is unaffected either way, because CORS is
        // a browser rule and a Dart HTTP client does not send an Origin.
        //
        // Development keeps the convenience, so nobody has to set the variable
        // to run the portal locally, and a production deployment that forgets
        // it loses the admin portal rather than its access control — a failure
        // somebody notices in a minute and fixes in a minute.
        if (allowedOrigins.Length == 0)
        {
            if (builder.Environment.IsDevelopment())
            {
                policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
            }

            return;
        }

        policy.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod();
    });
});

var app = builder.Build();

var startupLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("ProductionConfiguration");

// What login codes actually go out on. Read from the database (the admin
// portal owns it); if the database is not reachable yet, fall back to the
// environment value rather than refusing to start.
var effectiveOtpProvider = authOptions.OtpProvider;
try
{
    effectiveOtpProvider = await app.Services
        .GetRequiredService<OtpDeliveryService>()
        .EffectiveProviderAsync(CancellationToken.None);
}
catch (Exception exception)
{
    startupLogger.LogWarning(exception, "Could not read the OTP provider from the database at startup.");
}

ProductionConfigurationValidator.Validate(
    app.Environment,
    authOptions,
    effectiveOtpProvider,
    startupLogger);

// Railway terminates TLS at its edge and proxies to this container, so
// without this every request appears to come from the proxy's address.
// HttpContext.Connection.RemoteIpAddress was therefore the SAME value for
// every client on the internet, which meant:
//   * the global 300/min limiter was one bucket for the entire platform,
//     and the per-caller policies below keyed on that same constant;
//   * auth_otp_challenges.requested_ip, the failed-portal-sign-in warning and
//     the refresh-token IP records all stored the proxy, so per-IP abuse could
//     not be investigated at all.
// None of it reproduces locally, where every client has its own address.
//
// ForwardLimit = 1 takes only the right-most X-Forwarded-For entry — the one
// Railway's own proxy appended. Entries further left are supplied by the
// caller and can say anything, so they are ignored. KnownProxies and
// KnownNetworks are cleared because the proxy's address is not fixed and is
// not reachable from inside the container; the ForwardLimit is what keeps this
// honest.
var forwardedHeaders = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
    ForwardLimit = 1
};

// These must be Clear()ed, not written as `KnownNetworks = { }` in the object
// initializer. That form compiles — it parses as an empty initializer and emits
// nothing — so the defaults survive: KnownNetworks holds 127.0.0.1/8 and
// KnownProxies holds ::1. The middleware then sees a non-empty allowlist,
// checks Railway's proxy (a private container address) against loopback, fails
// the check, and gives up WITHOUT applying X-Forwarded-For at all. Everything
// this block exists to fix stays broken, silently, and only in production.
forwardedHeaders.KnownNetworks.Clear();
forwardedHeaders.KnownProxies.Clear();

app.UseForwardedHeaders(forwardedHeaders);

app.UseExceptionHandler();
app.UseMiddleware<RequestContextMiddleware>();
app.UseMiddleware<SecurityHeadersMiddleware>();
app.UseCors("UDriveClients");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

// Swagger UI has no authorization gate, so publishing it hands an anonymous
// visitor the complete API surface: every route, every parameter, every DTO.
// Both .env.example files set ENABLE_SWAGGER=true, so a copied example would
// have turned it on in production with nothing to stop it. It is now available
// only outside production, whatever that variable says.
if (app.Environment.IsDevelopment() ||
    (!app.Environment.IsProduction() &&
     string.Equals(Environment.GetEnvironmentVariable("ENABLE_SWAGGER"), "true", StringComparison.OrdinalIgnoreCase)))
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
