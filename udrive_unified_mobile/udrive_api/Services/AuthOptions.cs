namespace UDrive.Api.Services;

public sealed record AuthOptions(
    string Issuer,
    string Audience,
    string SigningKey,
    int AccessTokenMinutes,
    int RefreshTokenDays,
    string OtpHashSecret,
    string IdentityHashSecret,
    string OtpProvider,
    string DevelopmentOtpCode,
    bool ExposeDevelopmentOtp,
    string QuoteSigningSecret)
{
    public static AuthOptions FromEnvironment()
    {
        var signingKey = Environment.GetEnvironmentVariable("JWT_SIGNING_KEY")
            ?? "UDrive-Phase8-Development-Signing-Key-Change-Me-2026!";
        var otpSecret = Environment.GetEnvironmentVariable("OTP_HASH_SECRET")
            ?? "UDrive-Phase8-Development-Otp-Hash-Secret-2026!";
        var identitySecret = Environment.GetEnvironmentVariable("IDENTITY_HASH_SECRET")
            ?? "UDrive-Phase8-Development-Identity-Hash-Secret-2026!";

        // Signs fare quotes. Its own secret rather than reusing the JWT key,
        // so rotating sign-in tokens does not invalidate every open quote and
        // a leak of one is not a leak of the other.
        //
        // A rotation of this key makes quotes issued before it unusable. That
        // is a few minutes of customers being asked to reload a fare, which is
        // the correct trade for being able to rotate it at all.
        var quoteSecret = Environment.GetEnvironmentVariable("QUOTE_SIGNING_SECRET")
            ?? "UDrive-Phase20-Development-Quote-Signing-Secret-2026!";

        if (signingKey.Length < 32)
        {
            throw new InvalidOperationException("JWT_SIGNING_KEY must contain at least 32 characters.");
        }

        if (quoteSecret.Length < 32)
        {
            throw new InvalidOperationException("QUOTE_SIGNING_SECRET must contain at least 32 characters.");
        }

        return new AuthOptions(
            Environment.GetEnvironmentVariable("JWT_ISSUER") ?? "udrive-api",
            Environment.GetEnvironmentVariable("JWT_AUDIENCE") ?? "udrive-clients",
            signingKey,
            ParsePositiveInt("JWT_ACCESS_TOKEN_MINUTES", 15),
            ParsePositiveInt("JWT_REFRESH_TOKEN_DAYS", 30),
            otpSecret,
            identitySecret,
            Environment.GetEnvironmentVariable("OTP_PROVIDER") ?? "Development",
            Environment.GetEnvironmentVariable("DEVELOPMENT_OTP_CODE") ?? "1234",
            string.Equals(
                Environment.GetEnvironmentVariable("EXPOSE_DEVELOPMENT_OTP"),
                "true",
                StringComparison.OrdinalIgnoreCase),
            quoteSecret);
    }

    private static int ParsePositiveInt(string key, int fallback)
    {
        return int.TryParse(Environment.GetEnvironmentVariable(key), out var value) && value > 0
            ? value
            : fallback;
    }
}
