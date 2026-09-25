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

        // "Unavailable" means production is running without WhatsApp switched
        // on. The alternative to refusing here is issuing the fixed development
        // code, which is the same code for every number on the platform.
        if (plan.Provider == "Unavailable")
        {
            logger.LogError(
                "Login refused for {PhoneNumber}: WhatsApp delivery is not configured and this is "
                + "a production deployment, so the fixed development code is not issued. Configure "
                + "WA Engine under Services in the admin portal.",
                phoneNumber);

            return ServiceResult<RequestOtpDto>.Fail(
                StatusCodes.Status503ServiceUnavailable,
                "otp_not_configured",
                "Sign-in is temporarily unavailable. Please try again shortly.");
        }

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

    // ----------------------------------------------------------- portal login
    //
    // The admin portal signs in with a username and password, not an OTP: the
    // WhatsApp settings that deliver OTPs are configured inside the portal, so
    // an OTP-only portal locks its own door when WA Engine misbehaves.

    private static readonly string[] PortalRoles =
    [
        "SuperAdmin", "Admin", "Manager", "Operations", "VerificationOfficer",
        "SupportAgent", "FinanceOfficer", "SafetyOfficer", "TourismManager"
    ];

    public async Task<ServiceResult<AuthTokensDto>> AdminLoginAsync(
        AdminLoginRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken cancellationToken)
    {
        // One message for every failure: a different answer for "no such user"
        // tells an attacker which usernames exist.
        const string wrong = "The username or password is incorrect.";

        var login = await store.GetPortalLoginAsync(request.Username.Trim(), cancellationToken);
        if (login is null || login.PasswordHash is null)
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status401Unauthorized, "invalid_credentials", wrong);
        }

        if (login.LockedUntil is { } lockedUntil && lockedUntil > DateTimeOffset.UtcNow)
        {
            var minutes = Math.Max(1, Math.Ceiling((lockedUntil - DateTimeOffset.UtcNow).TotalMinutes));
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status423Locked,
                "account_locked",
                $"Too many failed attempts. Try again in {minutes} minute(s).");
        }

        if (!PasswordHasher.Verify(request.Password, login.PasswordHash))
        {
            await store.RecordFailedPortalLoginAsync(login.UserId, cancellationToken);
            logger.LogWarning("Failed portal sign-in for {Username} from {Ip}.", request.Username, ipAddress);
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status401Unauthorized, "invalid_credentials", wrong);
        }

        var user = await store.GetUserByIdAsync(login.UserId, cancellationToken);
        if (user is null || user.AccountStatus is "Suspended" or "Rejected" or "Deleted")
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status401Unauthorized, "account_unavailable", "This account is not available.");
        }

        var roles = await store.GetRolesAsync(user.Id, cancellationToken);
        if (!roles.Any(role => PortalRoles.Contains(role, StringComparer.Ordinal)))
        {
            return ServiceResult<AuthTokensDto>.Fail(
                StatusCodes.Status403Forbidden,
                "not_a_portal_user",
                "This account does not have admin portal access.");
        }

        await store.ClearFailedPortalLoginAsync(login.UserId, cancellationToken);
        // The token version moved when the password was set, so reload the user
        // before minting a token with it.
        var fresh = await store.GetUserByIdAsync(login.UserId, cancellationToken) ?? user;
        return await IssueTokensAsync(
            fresh, roles, request.DeviceId, request.DeviceName, ipAddress, userAgent, cancellationToken);
    }

    /// <summary>A portal user changing their own password. Ends every other session.</summary>
    public async Task<ServiceResult<bool>> ChangePasswordAsync(
        Guid userId,
        ChangePasswordRequest request,
        CancellationToken cancellationToken)
    {
        var currentHash = await store.GetPasswordHashAsync(userId, cancellationToken);
        if (currentHash is null)
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest,
                "no_password_set",
                "This account has no portal password. Ask a SuperAdmin to set one.");
        }

        if (!PasswordHasher.Verify(request.CurrentPassword, currentHash))
        {
            await store.RecordFailedPortalLoginAsync(userId, cancellationToken);
            return ServiceResult<bool>.Fail(
                StatusCodes.Status401Unauthorized, "invalid_credentials", "The current password is incorrect.");
        }

        if (PasswordHasher.Validate(request.NewPassword, null) is { } problem)
        {
            return ServiceResult<bool>.Fail(StatusCodes.Status400BadRequest, "weak_password", problem);
        }

        await store.SetPortalCredentialsAsync(
            userId, null, PasswordHasher.Hash(request.NewPassword), cancellationToken);
        return ServiceResult<bool>.Ok(true, "Password changed. Sign in again with the new password.");
    }

    /// <summary>SuperAdmin giving (or resetting) a portal user's username and password.</summary>
    public async Task<ServiceResult<bool>> SetPortalCredentialsAsync(
        SetPortalCredentialsRequest request,
        CancellationToken cancellationToken)
    {
        if (PasswordHasher.ValidateUsername(request.Username) is { } usernameProblem)
        {
            return ServiceResult<bool>.Fail(StatusCodes.Status400BadRequest, "invalid_username", usernameProblem);
        }

        if (PasswordHasher.Validate(request.Password, request.Username) is { } passwordProblem)
        {
            return ServiceResult<bool>.Fail(StatusCodes.Status400BadRequest, "weak_password", passwordProblem);
        }

        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.PhoneNumber, out var phoneNumber))
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest, "invalid_phone_number",
                "Enter a valid Pakistani mobile number, for example 03001234567.");
        }

        var user = await store.GetUserByPhoneAsync(phoneNumber, cancellationToken);
        if (user is null)
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound, "user_not_found", "No account uses this mobile number.");
        }

        var roles = await store.GetRolesAsync(user.Id, cancellationToken);
        if (!roles.Any(role => PortalRoles.Contains(role, StringComparer.Ordinal)))
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest,
                "not_a_portal_user",
                "Give this account a portal role first, then set its password.");
        }

        var saved = await store.SetPortalCredentialsAsync(
            user.Id, request.Username.Trim(), PasswordHasher.Hash(request.Password), cancellationToken);
        return saved
            ? ServiceResult<bool>.Ok(true, $"{request.Username.Trim()} can now sign in with this password.")
            : ServiceResult<bool>.Fail(StatusCodes.Status404NotFound, "user_not_found", "The account could not be updated.");
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
