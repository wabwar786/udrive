namespace UDrive.Api.Services;

/// <summary>
/// Towns and valleys across Azad Kashmir, matched alongside Google's results.
/// </summary>
/// <remarks>
/// Google's coverage of Pakistan is good for cities and thin for mountain
/// villages. A customer in Kel or Sharda searching for home should not be told
/// their village does not exist — and those are exactly the journeys UDrive
/// exists for, so the places the app most needs are the ones a general geocoder
/// is least likely to hold.
///
/// These are merged with Google's results, never replacing them: Google still
/// wins for cities, street addresses and businesses. This guarantees a floor of
/// local coverage.
///
/// The list is deliberately short and limited to places whose position is well
/// established. An approximate pin on a well-known valley is useful; an invented
/// one for a hamlet is worse than no result, because it sends a driver
/// somewhere wrong. Extend it as real journeys reveal what is missing.
/// </remarks>
public static class KashmirGazetteer
{
    public sealed record Place(
        string Name,
        string District,
        double Latitude,
        double Longitude,
        string[] Aliases);

    public static readonly IReadOnlyList<Place> Places = new List<Place>
    {
        // Muzaffarabad division
        new("Muzaffarabad", "Muzaffarabad", 34.3700, 73.4711,
            ["muzafarabad", "mzffarabad"]),
        new("Domel", "Muzaffarabad", 34.3556, 73.4744, []),
        new("Garhi Dupatta", "Muzaffarabad", 34.2231, 73.6011, ["ghari dupatta"]),
        new("Chikar", "Muzaffarabad", 34.1289, 73.6892, ["chikkar"]),
        new("Pir Chinasi", "Muzaffarabad", 34.3667, 73.5833, ["peer chinasi"]),
        new("Hattian Bala", "Hattian Bala", 34.1631, 73.7519, ["hattian"]),
        new("Chakothi", "Hattian Bala", 34.0356, 73.9028, ["chakoti"]),
        new("Leepa Valley", "Hattian Bala", 34.1856, 73.9944, ["leepa"]),

        // Neelum valley
        new("Athmuqam", "Neelum", 34.5822, 73.8992, ["atmuqam", "athmaqam"]),
        new("Kundal Shahi", "Neelum", 34.5342, 73.8189, ["kundalshahi"]),
        new("Keran", "Neelum", 34.6247, 73.9139, []),
        new("Sharda", "Neelum", 34.7906, 74.1806, ["shardi"]),
        new("Kel", "Neelum", 34.8244, 74.3517, ["kail"]),
        new("Arang Kel", "Neelum", 34.7900, 74.3400, ["arangkel", "arang kail"]),
        new("Neelum Valley", "Neelum", 34.5900, 73.9100, ["neelam valley"]),

        // Bagh and Poonch
        new("Bagh", "Bagh", 33.9797, 73.7728, []),
        new("Dhirkot", "Bagh", 33.9206, 73.6500, ["dheerkot"]),
        new("Rawalakot", "Poonch", 33.8578, 73.7604, ["rawlakot"]),
        new("Toli Peer", "Poonch", 33.8167, 73.8833, ["tolipir", "toli pir"]),
        new("Banjosa Lake", "Poonch", 33.7833, 73.8000, ["banjosa"]),

        // Southern districts
        new("Kotli", "Kotli", 33.5183, 73.9020, []),
        new("Mirpur", "Mirpur", 33.1478, 73.7519, ["mirpur ajk"]),
        new("Dadyal", "Mirpur", 33.1050, 73.6600, ["dadial"]),
        new("Bhimber", "Bhimber", 32.9750, 74.0800, []),
        new("Pallandri", "Sudhanoti", 33.7100, 73.6800, ["palandri"]),
    };

    /// <summary>Places whose name or an alias contains <paramref name="query"/>.</summary>
    /// <remarks>
    /// Matches on "contains" rather than "starts with": people search "kel"
    /// expecting Arang Kel, and "neelum" expecting the valley. An exact name
    /// match is ordered first.
    /// </remarks>
    public static IEnumerable<Place> Search(string query, int limit)
    {
        var needle = query.Trim().ToLowerInvariant();
        if (needle.Length < 2) return Array.Empty<Place>();

        return Places
            .Where(place =>
                place.Name.ToLowerInvariant().Contains(needle) ||
                place.Aliases.Any(alias => alias.Contains(needle)))
            .OrderBy(place =>
                place.Name.ToLowerInvariant() == needle ? 0
                : place.Name.ToLowerInvariant().StartsWith(needle) ? 1
                : 2)
            .ThenBy(place => place.Name.Length)
            .Take(limit);
    }
}
