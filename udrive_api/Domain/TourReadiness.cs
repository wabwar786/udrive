namespace UDrive.Api.Domain;

/// <summary>
/// What makes a vehicle fit to carry a tour, and how close one is.
/// </summary>
/// <remarks>
/// The scoring used to live as a private method inside DriverVerificationService,
/// where the only thing that could reach it was the save path. So the number was
/// written to the database and never explained to anyone: a Driver was refused a
/// tour package with "this vehicle does not meet the minimum tourism readiness
/// score" and had no way to learn the score, the bar, or which item would close
/// the gap. They would tick boxes at random or give up.
///
/// Here it is one list, read by the save path, by the screen that shows a
/// Driver their vehicle, and by the check that lets a package be published — so
/// the three can never disagree about what a vehicle is worth.
/// </remarks>
public static class TourReadiness
{
    /// <summary>The score every vehicle starts with.</summary>
    /// <remarks>
    /// Twenty for being a registered, verified vehicle at all. It matters that
    /// this is not zero: the items below are about mountain roads, and a
    /// perfectly sound car with none of them is not worth nothing.
    /// </remarks>
    public const int BaseScore = 20;

    /// <summary>The bar used when the database has no setting for it.</summary>
    public const int DefaultMinimum = 60;

    /// <summary>One thing a vehicle can have, and what it is worth.</summary>
    /// <param name="Key">Stable; the app matches on this, not on the label.</param>
    /// <param name="Label">What the Driver sees.</param>
    /// <param name="Points">Added to the score when present.</param>
    public sealed record Item(string Key, string Label, int Points);

    /// <summary>
    /// Everything that counts, heaviest first — so a Driver reading the list
    /// top to bottom is reading it in the order that helps them most.
    /// </summary>
    /// <remarks>
    /// The weights say what these roads ask for. Four-wheel drive is worth more
    /// than everything except the safety kit combined, because on the Neelum
    /// and Leepa roads it is the difference between a trip and a recovery. A
    /// spare tyre and a first-aid kit are next and equal: both are the
    /// difference between an inconvenience and an emergency when help is two
    /// hours away. Air conditioning and a child seat are comfort, and score
    /// like it.
    /// </remarks>
    public static readonly IReadOnlyList<Item> Items =
    [
        new("fourByFour", "Four-wheel drive", 25),
        new("firstAidKit", "First-aid kit", 12),
        new("spareTyre", "Spare tyre", 12),
        new("fireExtinguisher", "Fire extinguisher", 10),
        new("snowChains", "Snow chains", 10),
        new("heating", "Heating", 5),
        new("airConditioning", "Air conditioning", 3),
        new("childSeat", "Child seat", 3),
    ];

    /// <summary>What a vehicle has, in the order <see cref="Items"/> lists it.</summary>
    public sealed record Equipment(
        bool FourByFour,
        bool FirstAidKit,
        bool SpareTyre,
        bool FireExtinguisher,
        bool SnowChains,
        bool Heating,
        bool AirConditioning,
        bool ChildSeat)
    {
        public bool Has(string key) => key switch
        {
            "fourByFour" => FourByFour,
            "firstAidKit" => FirstAidKit,
            "spareTyre" => SpareTyre,
            "fireExtinguisher" => FireExtinguisher,
            "snowChains" => SnowChains,
            "heating" => Heating,
            "airConditioning" => AirConditioning,
            "childSeat" => ChildSeat,
            _ => false,
        };
    }

    /// <summary>The score, 0–100.</summary>
    public static int Score(Equipment equipment) =>
        Math.Min(
            100,
            BaseScore + Items.Where(item => equipment.Has(item.Key)).Sum(item => item.Points));

    /// <summary>
    /// The cheapest set of missing items that would reach <paramref name="minimum"/>,
    /// or everything missing when even all of it would not.
    /// </summary>
    /// <remarks>
    /// Cheapest, not heaviest. A Driver eleven points short should be told to
    /// buy a first-aid kit, not to buy a four-wheel-drive vehicle — and a list
    /// sorted by points would tell them the second. So the missing items are
    /// walked from the smallest upwards and taken until the gap closes, which
    /// gives the shortest honest answer to "what do I need".
    /// </remarks>
    public static IReadOnlyList<Item> MissingToReach(Equipment equipment, int minimum)
    {
        var score = Score(equipment);
        if (score >= minimum) return [];

        var missing = Items.Where(item => !equipment.Has(item.Key))
            .OrderBy(item => item.Points)
            .ToList();

        var needed = new List<Item>();
        foreach (var item in missing)
        {
            needed.Add(item);
            score += item.Points;
            if (score >= minimum) break;
        }

        // Still short with everything ticked: say so by returning all of it,
        // rather than a list that would not be enough even if followed.
        return needed;
    }
}
