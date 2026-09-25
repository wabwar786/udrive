using System.Security.Claims;
using UDrive.Api.Common;

namespace UDrive.Api.Security;

public static class ClaimsPrincipalExtensions
{
    public static Guid GetRequiredUserId(this ClaimsPrincipal principal)
    {
        var value = principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? principal.FindFirstValue("sub");

        return Guid.TryParse(value, out var userId)
            ? userId
            : throw new ApiAuthenticationException("The access token does not contain a valid user ID.");
    }

    /// <summary>The signed-in user, or null rather than an exception.</summary>
    /// <remarks>
    /// For places that only want to record who did something. A fuel price is
    /// still a fuel price if the audit column ends up empty; refusing to save
    /// it over a malformed token would be the wrong trade.
    /// </remarks>
    public static Guid? GetUserIdOrNull(this ClaimsPrincipal principal)
    {
        var value = principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? principal.FindFirstValue("sub");

        return Guid.TryParse(value, out var userId) ? userId : null;
    }
}
