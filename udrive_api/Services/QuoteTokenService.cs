using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

/// <summary>
/// The band the server quoted, in a form it can verify later without trusting
/// the client and without pricing the trip a second time.
/// </summary>
/// <remarks>
/// The alternative would be to recompute the fare when the ride request
/// arrives — but the distance came from a Directions call the client paid for,
/// so recomputing means either calling Directions again on the server or
/// trusting the distance the client now says it had. Signing the answer avoids
/// both: the server already did the arithmetic, and this is the server
/// recognising its own work.
///
/// Format is <c>v1.{payload}.{signature}</c>, payload base64url JSON, signature
/// HMAC-SHA256 hex over the payload segment. Deliberately the same primitive as
/// the OTP hashes next door, with its own secret so rotating one does not
/// invalidate the other.
/// </remarks>
public sealed class QuoteTokenService(AuthOptions authOptions)
{
    private const string Version = "v1";

    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>
    /// Everything the booking endpoint has to be able to check.
    /// </summary>
    /// <remarks>
    /// Coordinates are stored to four decimal places, about eleven metres.
    /// Keeping more would be pretending the phone's fix is better than it is;
    /// keeping fewer would let a quote for one street price a trip from
    /// another.
    /// </remarks>
    public sealed record Payload(
        Guid QuoteId,
        /// <summary>Who the quote was issued to.</summary>
        /// <remarks>
        /// Without this a quote is a bearer token: one customer's cheap band,
        /// handed to another, priced their trip. It is signed, so it cannot be
        /// edited, and the booking endpoint compares it to the caller.
        /// </remarks>
        Guid CustomerUserId,
        string ServiceType,
        string VehicleCategory,
        string BookingType,
        int Seats,
        double PickupLatitude,
        double PickupLongitude,
        double DestinationLatitude,
        double DestinationLongitude,
        double DistanceKm,
        decimal Minimum,
        decimal Recommended,
        decimal Maximum,
        decimal Surge,
        long IssuedAt,
        long ExpiresAt);

    public string Issue(Payload payload)
    {
        var rounded = payload with
        {
            PickupLatitude = Math.Round(payload.PickupLatitude, 4),
            PickupLongitude = Math.Round(payload.PickupLongitude, 4),
            DestinationLatitude = Math.Round(payload.DestinationLatitude, 4),
            DestinationLongitude = Math.Round(payload.DestinationLongitude, 4),
            DistanceKm = Math.Round(payload.DistanceKm, 3),
        };

        var segment = WebEncoders.Base64UrlEncode(
            Encoding.UTF8.GetBytes(JsonSerializer.Serialize(rounded, Json)));

        return $"{Version}.{segment}.{Sign(segment)}";
    }

    /// <summary>
    /// The payload if the token is ours and still valid, otherwise null.
    /// </summary>
    /// <remarks>
    /// Returns null for every kind of failure — wrong shape, wrong signature,
    /// expired, unparseable. The caller turns that into one refusal with one
    /// message, because telling a client which part of its forged token was
    /// wrong is how forging gets easier.
    /// </remarks>
    public Payload? Verify(string? token)
    {
        if (string.IsNullOrWhiteSpace(token)) return null;

        var parts = token.Split('.');
        if (parts.Length != 3 || parts[0] != Version) return null;

        if (!SecurityHashing.FixedTimeEqualsHex(Sign(parts[1]), parts[2]))
        {
            return null;
        }

        Payload? payload;
        try
        {
            var json = Encoding.UTF8.GetString(WebEncoders.Base64UrlDecode(parts[1]));
            payload = JsonSerializer.Deserialize<Payload>(json, Json);
        }
        catch (Exception exception) when (
            exception is JsonException or FormatException or DecoderFallbackException)
        {
            return null;
        }

        if (payload is null) return null;

        return DateTimeOffset.UtcNow.ToUnixTimeSeconds() > payload.ExpiresAt
            ? null
            : payload;
    }

    private string Sign(string segment) =>
        SecurityHashing.HashWithSecret(segment, authOptions.QuoteSigningSecret);

    /// <summary>Metres between two coordinates, on a sphere.</summary>
    /// <remarks>
    /// Used twice: to check a claimed road distance is not shorter than the
    /// straight line, and to check the trip being booked is the trip that was
    /// quoted. Both want a cheap answer, not a geodesic one.
    /// </remarks>
    public static double DistanceMetres(
        double fromLatitude, double fromLongitude,
        double toLatitude, double toLongitude)
    {
        const double earthRadiusMetres = 6371000.0;

        var dLat = (toLatitude - fromLatitude) * Math.PI / 180.0;
        var dLon = (toLongitude - fromLongitude) * Math.PI / 180.0;
        var lat1 = fromLatitude * Math.PI / 180.0;
        var lat2 = toLatitude * Math.PI / 180.0;

        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
                + Math.Sin(dLon / 2) * Math.Sin(dLon / 2) * Math.Cos(lat1) * Math.Cos(lat2);

        return earthRadiusMetres * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
