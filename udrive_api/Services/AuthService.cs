using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

public sealed class AuthService(
    AuthOptions options,
    AuthSqlStore store,
    JwtTokenService jwtTokenService,
    OtpDeliveryService otpDelivery,
    ILogger<AuthService> logger)
{
    public async Task<ServiceResult<RequestOtpDto>> RequestOtpAsync(
        RequestOtpRequest request,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.PhoneNumber, out var phoneNumber))
        {
            return ServiceResult<RequestOtpDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_phone_number",
                "Enter a valid Pakistani mobile number, for example 03001234567.");
        }

        var purpose = string.IsNullOrWhiteSpace(request.Purpose)
            ? "login"
            : request.Purpose.Trim().ToLowerInvariant();
        var lastRequestedAt = await store.GetLastOtpRequestAsync(phoneNumber, purpose, cancellationToken);
        if (lastRequestedAt is not null)
        {
            var elapsed = DateTimeOffset.UtcNow - lastRequestedAt.Value;
            if (elapsed < TimeSpan.FromSeconds(45))
            {
                return ServiceResult<RequestOtpDto>.Fail(
                    StatusCodes.Status429TooManyRequests,
                    "otp_retry_later",
                    $"Please wait {Math.Ceiling((TimeSpan.FromSeconds(45) - elapsed).TotalSeconds)} seconds before requesting another code.");
            }
        }

        // Provider and code come from the admin OTP settings (Development, WhatsApp,
        // or the Play reviewer number). The challenge is stored only after the
        // code has actually been sent, so a failed send does not start the
        // 45-second wait.
        var plan = await otpDelivery.PlanAsync(phoneNumber, cancellationToken);
        if (plan.Send && !await otpDelivery.SendLoginCodeAsync(phoneNumber, plan.Code, cancellationToken))
        {
            return ServiceResult<RequestOtpDto>.Fail(
                StatusCodes.Status503ServiceUnavailable,
                "otp_delivery_failed",
                "We could not send the code on WhatsApp. Check the number has WhatsApp and try again in a minute.");
        }

        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(5);
        var hash = SecurityHashing.HashWithSecret($"{phoneNumber}:{purpose}:{plan.Code}", options.OtpHashSecret);
        var challengeId = await store.CreateOtpChallengeAsync(
            phoneNumber,
            purpose,
            hash,
            expiresAt,
            ipAddress,
            cancellationToken);

        logger.LogInformation(
            "OTP challenge {ChallengeId} created for {PhoneNumber} via {Provider}.",
            challengeId,
            phoneNumber,
            plan.Provider);

        return ServiceResult<RequestOtpDto>.Ok(new RequestOtpDto(
            challengeId,
            expiresAt,
            45,
            plan.Provider switch { "WhatsApp" => "whatsapp", "Test" => "test", _ => "development" },
            plan.DevelopmentCodeToExpose));
    }

    public async Task<ServiceResult<AuthTokensDto>> VerifyOtpAsync(
        VerifyOtpRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken cancellationToken)
    {
        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.PhoneNumber, out var phoneNumber))
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_phone_number",
                "The mobile number is invalid.");
        }

        var challenge = await store.GetLatestActiveOtpAsync(phoneNumber, "login", cancellationToken);
        if (challenge is null)
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status400BadRequest,
                "otp_not_requested",
                "Request a new verification code first.");
        }

        if (challenge.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status400BadRequest,
                "otp_expired",
                "The verification code has expired.");
        }

        if (challenge.Attempts >= challenge.MaxAttempts)
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status429TooManyRequests,
                "otp_attempts_exceeded",
                "Too many incorrect attempts. Request a new code.");
        }

        var actualHash = SecurityHashing.HashWithSecret(
            $"{phoneNumber}:login:{request.Code.Trim()}",
            options.OtpHashSecret);
        if (!SecurityHashing.FixedTimeEqualsHex(challenge.CodeHash, actualHash))
        {
            await store.IncrementOtpAttemptsAsync(challenge.Id, cancellationToken);
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_otp",
                "The verification code is incorrect.");
        }

        await store.ConsumeOtpAsync(challenge.Id, cancellationToken);
        var name = string.IsNullOrWhiteSpace(request.FullName)
            ? $"uDrive User {phoneNumber[^4..]}"
            : request.FullName.Trim();
        var language = string.Equals(request.Language, "ur", StringComparison.OrdinalIgnoreCase) ? "ur" : "en";
        var user = await store.UpsertVerifiedCustomerAsync(phoneNumber, name, language, cancellationToken);
        var roles = await store.GetRolesAsync(user.Id, cancellationToken);
        return await IssueTokensAsync(
            user,
            roles,
            request.DeviceId,
            request.DeviceName,
            ipAddress,
            userAgent,
            cancellationToken);
    }

    public async Task<ServiceResult<AuthTokensDto>> RefreshAsync(
        RefreshTokenRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken cancellationToken)
    {
        var tokenHash = SecurityHashing.HashToken(request.RefreshToken);
        var storedToken = await store.GetRefreshTokenAsync(tokenHash, cancellationToken);
        if (storedToken is null || storedToken.RevokedAt is not null || storedToken.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status401Unauthorized,
                "invalid_refresh_token",
                "The session has expired. Sign in again.");
        }

        var user = await store.GetUserByIdAsync(storedToken.UserId, cancellationToken);
        if (user is null || user.AccountStatus is "Suspended" or "Rejected" or "Deleted")
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status401Unauthorized,
                "account_unavailable",
                "This account is not available.");
        }

        var roles = await store.GetRolesAsync(user.Id, cancellationToken);
        var result = await IssueTokensAsync(
            user,
            roles,
            request.DeviceId,
            request.DeviceName,
            ipAddress,
            userAgent,
            cancellationToken);

        if (!result.Success || result.Data is null)
        {
            return result;
        }

        var replacementHash = SecurityHashing.HashToken(result.Data.RefreshToken);
        var replacement = await store.GetRefreshTokenAsync(replacementHash, cancellationToken);
        if (replacement is not null)
        {
            await store.RevokeAndReplaceRefreshTokenAsync(
                storedToken.Id,
                replacement.Id,
                cancellationToken);
        }
        return result;
    }

    public async Task<ServiceResult<CurrentUserDto>> GetCurrentUserAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        var user = await store.GetUserByIdAsync(userId, cancellationToken);
        if (user is null)
        {
            return ServiceResult<CurrentUserDto>.Fail(
                StatusCodes.Status404NotFound,
                "user_not_found",
                "The account could not be found.");
        }

        var roles = await store.GetRolesAsync(userId, cancellationToken);
        return ServiceResult<CurrentUserDto>.Ok(jwtTokenService.ToCurrentUser(user, roles));
    }

    public async Task<ServiceResult<bool>> LogoutAsync(
        Guid userId,
        LogoutRequest request,
        CancellationToken cancellationToken)
    {
        if (request.RevokeAllDevices)
        {
            await store.RevokeAllRefreshTokensAsync(userId, cancellationToken);
        }
        else if (!string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            await store.RevokeRefreshTokenAsync(
                SecurityHashing.HashToken(request.RefreshToken),
                cancellationToken);
        }

        return ServiceResult<bool>.Ok(true, "Signed out successfully.");
    }

    private async Task<ServiceResult<AuthTokensDto>> IssueTokensAsync(
        AuthUserRecord user,
        IReadOnlyCollection<string> roles,
        string? deviceId,
        string? deviceName,
        string? ipAddress,
        string? userAgent,
        CancellationToken cancellationToken)
    {
        var access = jwtTokenService.CreateAccessToken(user, roles);
        var refreshToken = SecurityHashing.CreateRefreshToken();
        var refreshExpiresAt = DateTimeOffset.UtcNow.AddDays(options.RefreshTokenDays);
        var refreshId = Guid.NewGuid();
        await store.InsertRefreshTokenAsync(
            refreshId,
            user.Id,
            SecurityHashing.HashToken(refreshToken),
            deviceId,
            deviceName,
            refreshExpiresAt,
            ipAddress,
            userAgent,
            cancellationToken);

        return ServiceResult<AuthTokensDto>.Ok(new AuthTokensDto(
            access.Token,
            access.ExpiresAt,
            refreshToken,
            refreshExpiresAt,
            jwtTokenService.ToCurrentUser(user, roles)));
    }
}
