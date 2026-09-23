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
    bool ExposeDevelopmentOtp)
{
    public static AuthOptions FromEnvironment()
    {
        var signingKey = Environment.GetEnvironmentVariable("JWT_SIGNING_KEY")
            ?? "UDrive-Phase8-Development-Signing-Key-Change-Me-2026!";
        var otpSecret = Environment.GetEnvironmentVariable("OTP_HASH_SECRET")
            ?? "UDrive-Phase8-Development-Otp-Hash-Secret-2026!";
        var identitySecret = Environment.GetEnvironmentVariable("IDENTITY_HASH_SECRET")
            ?? "UDrive-Phase8-Development-Identity-Hash-Secret-2026!";

        if (signingKey.Length < 32)
        {
            throw new InvalidOperationException("JWT_SIGNING_KEY must contain at least 32 characters.");
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
                StringComparison.OrdinalIgnoreCase));
    }

    private static int ParsePositiveInt(string key, int fallback)
    {
        return int.TryParse(Environment.GetEnvironmentVariable(key), out var value) && value > 0
            ? value
            : fallback;
    }
}
