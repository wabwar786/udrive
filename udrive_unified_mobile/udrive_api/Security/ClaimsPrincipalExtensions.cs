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
}
