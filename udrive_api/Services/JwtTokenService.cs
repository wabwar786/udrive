using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class JwtTokenService(AuthOptions options)
{
    public (string Token, DateTimeOffset ExpiresAt) CreateAccessToken(
        AuthUserRecord user,
        IReadOnlyCollection<string> roles)
    {
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(options.AccessTokenMinutes);
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(ClaimTypes.MobilePhone, user.PhoneNumber),
            new(ClaimTypes.Name, user.FullName),
            new("preferred_language", user.PreferredLanguage),
            new("account_status", user.AccountStatus),
            new("token_version", user.TokenVersion.ToString())
        };

        if (user.DriverProfileId is not null)
        {
            claims.Add(new Claim("driver_profile_id", user.DriverProfileId.Value.ToString()));
            claims.Add(new Claim("driver_status", user.DriverVerificationStatus ?? "Draft"));
        }

        claims.AddRange(roles.Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(role => new Claim(ClaimTypes.Role, role)));

        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey));
        var token = new JwtSecurityToken(
            issuer: options.Issuer,
            audience: options.Audience,
            claims: claims,
            notBefore: DateTime.UtcNow,
            expires: expiresAt.UtcDateTime,
            signingCredentials: new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256));

        return (new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }

    public CurrentUserDto ToCurrentUser(
        AuthUserRecord user,
        IReadOnlyCollection<string> roles)
    {
        var roleList = roles.Distinct(StringComparer.OrdinalIgnoreCase).Order().ToArray();
        return new CurrentUserDto(
            user.Id,
            user.PhoneNumber,
            user.FullName,
            user.Email,
            user.PreferredLanguage,
            user.AccountStatus,
            roleList,
            user.DriverProfileId,
            user.DriverVerificationStatus,
            string.Equals(user.DriverVerificationStatus, "Approved", StringComparison.OrdinalIgnoreCase));
    }
}
