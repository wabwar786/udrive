namespace UDrive.Api.Models;

// ───────────────────────────────────────────────────────────────── presence

/// <summary>What the driver app sends when it goes online or beats.</summary>
/// <remarks>
/// Position is optional on purpose. A driver who has not yet granted location
/// permission can still go online and still receive requests — refusing that
/// would make the toggle fail for a reason the driver cannot see. The position
/// is what a zone-scoped reward is checked against, so a reward simply does not
/// qualify without it.
/// </remarks>
public sealed record DriverPresenceRequest(
    double? Latitude,
    double? Longitude,

    /// <summary>The platform reported this fix as mocked.</summary>
    /// <remarks>
    /// Recorded against the session and raised as a review flag. It never
    /// blocks the driver by itself: Android has reported false positives on
    /// rooted-but-honest phones, and a driver who cannot go online has no way
    /// to argue the point.
    /// </remarks>
    bool MockLocation = false);

/// <summary>Whether the driver is online, and for how long today.</summary>
public sealed record DriverPresenceDto(
    bool IsOnline,
    Guid? SessionId,
    DateTimeOffset? OnlineSince,

    /// <summary>Seconds credited in the current session.</summary>
    int SessionSeconds,

    /// <summary>Seconds credited today, across every session.</summary>
    int TodaySeconds,

    /// <summary>How often the app should beat, in seconds.</summary>
    int HeartbeatSeconds,

    string? CityName,
    Guid? CityId);

// ──────────────────────────────────────────────────────────── driver facing

public sealed record GrowthRewardProgressDto(
    Guid Id,
    Guid CampaignId,
    Guid? MilestoneId,
    string Title,
    string? Description,
    decimal RewardAmount,
    decimal ProgressValue,
    decimal TargetValue,
    string Status,
    DateTimeOffset? QualifiedAt,
    DateTimeOffset? CreditedAt,
    DateTimeOffset? ExpiresAt);

public sealed record WelcomeBonusDto(
    Guid CampaignId,
    string Title,
    decimal TotalAmount,
    decimal UnlockedAmount,
    decimal RemainingAmount,
    DateTimeOffset? EndsAt,
    GrowthRewardProgressDto? NextMilestone,
    IReadOnlyList<GrowthRewardProgressDto> Milestones);

public sealed record MissionDto(
    Guid CampaignId,
    string CampaignType,
    string Title,
    string? Description,
    decimal RewardAmount,
    decimal ProgressValue,
    decimal TargetValue,
    string Status,
    DateTimeOffset? WindowStartsAt,
    DateTimeOffset? WindowEndsAt,
    string? ZoneName);

public sealed record FoundingDriverDto(
    bool IsFoundingDriver,
    int? SequenceNo,
    string? CityName,
    DateTimeOffset? GrantedAt,
    IReadOnlyList<MissionDto> Benefits);

public sealed record LaunchStatusDto(
    Guid? CityId,
    string? CityName,
    string LaunchStatus,
    bool CustomerCampaignActive,
    int VerifiedDrivers,
    int RegisteredCustomers,
    int RequestsThisWeek,
    int CompletedRidesThisWeek);

public sealed record ExpectedDemandDto(
    Guid ZoneId,
    string ZoneName,
    string Level,
    string? Reason,
    string StartTime,
    string EndTime,
    double? Latitude,
    double? Longitude,
    double? RadiusKm,

    /// <summary>
    /// True when the level came from live traffic rather than from an admin's
    /// expectation. The app must label the two differently — a driver who
    /// drives across town for "high demand" that was a guess will not do it
    /// twice.
    /// </summary>
    bool IsLive);

public sealed record DriverUpdateDto(
    Guid Id,
    string Category,
    string Title,
    string Body,
    string? ActionPath,
    DateTimeOffset PublishAt);

public sealed record ReferralSummaryDto(
    string ReferralCode,
    int TotalInvited,
    int Verified,
    int Active,
    decimal EarnedAmount,
    decimal PendingAmount,
    IReadOnlyList<ReferralEntryDto> Entries);

public sealed record ReferralEntryDto(
    Guid Id,
    string DriverName,
    string Status,
    DateTimeOffset? VerifiedAt,
    DateTimeOffset? FirstRideAt,
    decimal RewardEarned,
    decimal RewardPending);

/// <summary>Everything the driver home screen needs, in one call.</summary>
/// <remarks>
/// One call rather than eight. The home screen is what a driver opens twenty
/// times a day on a mobile connection, and eight requests there is eight
/// chances to show a half-drawn screen.
/// </remarks>
public sealed record DriverHomeDto(
    DriverPresenceDto Presence,
    decimal TodayEarnings,
    int TodayCompletedRides,
    decimal Rating,
    decimal? AcceptanceRate,
    decimal WalletBalance,
    decimal BonusBalance,
    MissionDto? ActiveMission,
    WelcomeBonusDto? WelcomeBonus,
    LaunchStatusDto? Launch,
    FoundingDriverDto? Founding,
    IReadOnlyList<ExpectedDemandDto> Demand,
    IReadOnlyList<DriverUpdateDto> Updates);

// ───────────────────────────────────────────────────────────── admin facing

public sealed record LaunchCityDto(
    Guid Id,
    string Name,
    bool IsActive,
    string LaunchStatus,
    bool CustomerCampaignActive,
    bool FoundingEnabled,
    int? FoundingLimit,
    DateTimeOffset? FoundingWindowEndsAt,
    string? SupportPhone,
    string? CommunityUrl,
    DateTimeOffset? ActivatedAt,
    int DriverCount,
    int FoundingCount);

public sealed record LaunchCityRequest(
    string Name,
    bool IsActive,
    string LaunchStatus,
    bool CustomerCampaignActive,
    bool FoundingEnabled,
    int? FoundingLimit,
    DateTimeOffset? FoundingWindowEndsAt,
    string? SupportPhone,
    string? CommunityUrl,
    string? Notes);

public sealed record GrowthCampaignDto(
    Guid Id,
    string CampaignType,
    string Code,
    string Title,
    string? Description,
    Guid? CityId,
    string? CityName,
    Guid? ZoneId,
    string? ZoneName,
    decimal RewardAmount,
    DateTimeOffset? StartsAt,
    DateTimeOffset? EndsAt,
    string? DailyStartTime,
    string? DailyEndTime,
    IReadOnlyList<int> DaysOfWeek,
    string DriverSegment,
    int? MinOnlineSeconds,
    int? MinCompletedRides,
    int? MinAcceptedRides,
    int? MaxCancellations,
    decimal? MinRating,
    decimal? MinAcceptanceRate,
    int? InactiveDays,
    int MaxAwardsPerDriver,
    decimal? TotalBudget,
    decimal SpentAmount,
    bool IsActive,
    IReadOnlyList<GrowthMilestoneDto> Milestones);

public sealed record GrowthMilestoneDto(
    Guid Id,
    int SortOrder,
    string Title,
    string? Description,
    decimal RewardAmount,
    string ConditionType,
    decimal ConditionValue);

public sealed record GrowthCampaignRequest(
    string CampaignType,
    string Code,
    string Title,
    string? Description,
    Guid? CityId,
    Guid? ZoneId,
    decimal RewardAmount,
    DateTimeOffset? StartsAt,
    DateTimeOffset? EndsAt,
    string? DailyStartTime,
    string? DailyEndTime,
    IReadOnlyList<int>? DaysOfWeek,
    string DriverSegment,
    int? MinOnlineSeconds,
    int? MinCompletedRides,
    int? MinAcceptedRides,
    int? MaxCancellations,
    decimal? MinRating,
    decimal? MinAcceptanceRate,
    int? InactiveDays,
    int MaxAwardsPerDriver,
    decimal? TotalBudget,
    bool IsActive,
    IReadOnlyList<GrowthMilestoneRequest>? Milestones);

public sealed record GrowthMilestoneRequest(
    int SortOrder,
    string Title,
    string? Description,
    decimal RewardAmount,
    string ConditionType,
    decimal ConditionValue);

public sealed record ExpectedDemandRequest(
    Guid? CityId,
    Guid ZoneId,
    string Level,
    string? Reason,
    IReadOnlyList<int>? DaysOfWeek,
    string StartTime,
    string EndTime,
    DateOnly? ValidFrom,
    DateOnly? ValidTo,
    Guid? CampaignId,
    bool IsActive);

public sealed record DriverUpdateRequest(
    Guid? CityId,
    string Category,
    string Title,
    string Body,
    string? ActionPath,
    DateTimeOffset? PublishAt,
    DateTimeOffset? ExpiresAt,
    bool IsPublished);

public sealed record FraudFlagDto(
    Guid Id,
    Guid DriverProfileId,
    string DriverName,
    string FlagType,
    string? Detail,
    string Severity,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ReviewedAt,
    string? ReviewNotes);

public sealed record FraudReviewRequest(string Status, string? Notes);

/// <summary>What a campaign has actually paid, per driver.</summary>
public sealed record CampaignAwardDto(
    Guid Id,
    Guid DriverProfileId,
    string DriverName,
    string? MilestoneTitle,
    string PeriodKey,
    decimal ProgressValue,
    decimal TargetValue,
    string Status,
    decimal RewardAmount,
    DateTimeOffset? QualifiedAt,
    DateTimeOffset? CreditedAt);
