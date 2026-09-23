using System.Text.RegularExpressions;

namespace UDrive.Api.Security;

public static partial class PhoneNumberNormalizer
{
    public static bool TryNormalizePakistan(string? input, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(input))
        {
            return false;
        }

        var value = NonDigits().Replace(input, string.Empty);
        if (value.StartsWith("0092", StringComparison.Ordinal))
        {
            value = value[2..];
        }

        if (value.StartsWith("03", StringComparison.Ordinal) && value.Length == 11)
        {
            value = "92" + value[1..];
        }
        else if (value.StartsWith('3') && value.Length == 10)
        {
            value = "92" + value;
        }

        if (!value.StartsWith("923", StringComparison.Ordinal) || value.Length != 12)
        {
            return false;
        }

        normalized = "+" + value;
        return true;
    }

    [GeneratedRegex("[^0-9]")]
    private static partial Regex NonDigits();
}
