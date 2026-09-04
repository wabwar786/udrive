namespace UDrive.Api.Common;

/// <summary>
/// The caller's token is missing or does not identify a user.
/// </summary>
/// <remarks>
/// Its own type on purpose. This used to throw <see cref="UnauthorizedAccessException"/>,
/// which .NET also throws when the filesystem denies access to a path — and the
/// exception handler mapped that type to 401 "The current session is not
/// authorized for this action."
///
/// So when `Directory.CreateDirectory` on the uploads volume failed for want of
/// write permission, every Driver opening My documents was told their session
/// was invalid. They signed out, signed in, and were told the same thing, because
/// the problem was a directory on a disk.
///
/// Two different faults must not share one exception type when the response
/// depends on telling them apart.
/// </remarks>
public sealed class ApiAuthenticationException(string message) : Exception(message);
