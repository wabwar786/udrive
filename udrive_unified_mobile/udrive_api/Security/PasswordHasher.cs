using System.Security.Cryptography;

namespace UDrive.Api.Security;

/// <summary>
/// Portal passwords: PBKDF2-HMAC-SHA256, per-password random salt.
///
/// Format: <c>pbkdf2$&lt;iterations&gt;$&lt;salt-base64&gt;$&lt;hash-base64&gt;</c>. The
/// iteration count travels with the hash, so raising it later does not
/// invalidate passwords already stored — old hashes keep verifying with their
/// own count and are upgraded the next time the password is set.
/// </summary>
public static class PasswordHasher
{
    public const int MinimumLength = 10;
    private const int Iterations = 210_000;
    private const int SaltBytes = 16;
    private const int HashBytes = 32;

    public static string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltBytes);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, HashBytes);
        return $"pbkdf2${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    public static bool Verify(string password, string? stored)
    {
        if (string.IsNullOrWhiteSpace(stored)) return false;

        var parts = stored.Split('$');
        if (parts.Length != 4 || parts[0] != "pbkdf2") return false;
        if (!int.TryParse(parts[1], out var iterations) || iterations is < 1000 or > 2_000_000) return false;

        byte[] salt, expected;
        try
        {
            salt = Convert.FromBase64String(parts[2]);
            expected = Convert.FromBase64String(parts[3]);
        }
        catch (FormatException)
        {
            return false;
        }

        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, expected.Length);
        return CryptographicOperations.FixedTimeEquals(actual, expected);
    }

    /// <summary>Rejects the passwords that get portals broken into.</summary>
    public static string? Validate(string? password, string? username)
    {
        if (string.IsNullOrWhiteSpace(password) || password.Length < MinimumLength)
            return $"The password must be at least {MinimumLength} characters.";
        if (password.Length > 128)
            return "The password must be 128 characters or fewer.";
        if (!password.Any(char.IsLetter) || !password.Any(char.IsDigit))
            return "The password must contain both letters and numbers.";
        if (!string.IsNullOrWhiteSpace(username) &&
            password.Contains(username, StringComparison.OrdinalIgnoreCase))
            return "The password must not contain the username.";

        string[] banned = ["password", "12345678", "qwerty", "udrive", "admin123", "letmein"];
        if (banned.Any(b => password.Contains(b, StringComparison.OrdinalIgnoreCase)))
            return "That password is too easy to guess. Choose something else.";

        return null;
    }

    /// <summary>Usernames are stored as typed and matched without case.</summary>
    public static string? ValidateUsername(string? username)
    {
        if (string.IsNullOrWhiteSpace(username) || username.Trim().Length < 3)
            return "The username must be at least 3 characters.";
        var value = username.Trim();
        if (value.Length > 64)
            return "The username must be 64 characters or fewer.";
        if (!value.All(c => char.IsLetterOrDigit(c) || c is '.' or '_' or '-'))
            return "The username may contain letters, numbers, dot, underscore and hyphen only.";
        return null;
    }
}
