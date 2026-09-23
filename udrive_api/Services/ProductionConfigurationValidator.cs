namespace UDrive.Api.Services;

public static class ProductionConfigurationValidator
{
    private static readonly string[] DevelopmentSecretFragments =
    [
        "Development-Signing-Key",
        "Development-Otp-Hash-Secret",
        "Development-Identity-Hash-Secret",
        "Change-Me"
    ];

    /// <param name="effectiveOtpProvider">
    /// What login codes actually go out on right now. Since the admin portal
    /// owns this setting, the OTP_PROVIDER environment variable is only a
    /// fallback — blocking startup on it kept a correctly configured platform
    /// from booting.
    /// </param>
    public static void Validate(
        IHostEnvironment environment,
        AuthOptions options,
        string effectiveOtpProvider,
        ILogger logger)
    {
        if (!environment.IsProduction())
        {
            return;
        }

        var enforce = string.Equals(
            Environment.GetEnvironmentVariable("ENFORCE_PRODUCTION_SECURITY"),
            "true",
            StringComparison.OrdinalIgnoreCase);

        var problems = new List<string>();
        if (DevelopmentSecretFragments.Any(options.SigningKey.Contains))
            problems.Add("JWT_SIGNING_KEY uses a development default.");
        if (DevelopmentSecretFragments.Any(options.OtpHashSecret.Contains))
            problems.Add("OTP_HASH_SECRET uses a development default.");
        if (DevelopmentSecretFragments.Any(options.IdentityHashSecret.Contains))
            problems.Add("IDENTITY_HASH_SECRET uses a development default.");
        if (options.ExposeDevelopmentOtp)
            problems.Add("EXPOSE_DEVELOPMENT_OTP must be false in production.");
        if (string.Equals(effectiveOtpProvider, "Development", StringComparison.OrdinalIgnoreCase))
        {
            // Not blocking: a platform mid-setup, or one recovering from a WA
            // Engine outage, must still be able to start so an admin can sign
            // in and fix it. It is loud instead.
            logger.LogWarning(
                "Login codes are going out as the fixed development code. Set the WA Engine API key in " +
                "Admin portal -> Services -> WhatsApp OTP and send a test message to switch WhatsApp on.");
        }

        var origins = Environment.GetEnvironmentVariable("ALLOWED_ORIGINS");
        if (string.IsNullOrWhiteSpace(origins))
            problems.Add("ALLOWED_ORIGINS is not configured.");

        if (problems.Count == 0)
        {
            logger.LogInformation("Production configuration validation passed.");
            return;
        }

        var message = "Unsafe production configuration: " + string.Join(" ", problems);
        if (!enforce)
        {
            logger.LogCritical("{Message} Set ENFORCE_PRODUCTION_SECURITY=true after configuring production secrets to make these checks blocking.", message);
            return;
        }

        throw new InvalidOperationException(message);
    }
}
