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
    string? ZoneName,

    /// <summary>The time of day a peak-hour reward runs, as "HH:mm".</summary>
    string? DailyStartTime = null,
    string? DailyEndTime = null,

    /// <summary>
    /// The conditions as the admin wrote them, so a detail screen can list what
    /// qualifying actually requires.
    /// </summary>
    /// <remarks>
    /// Sent even though only one of them drives the progress bar. A driver who
    /// finishes two hours online and is then not paid because they cancelled
    /// twice needs to have been able to read that rule beforehand — otherwise
    /// the reward looks arbitrary, which is worse than no reward.
    /// </remarks>
    int? MinOnlineSeconds = null,
    int? MinCompletedRides = null,
    int? MinAcceptedRides = null,
    int? MaxCancellations = null,
    decimal? MinRating = null,
    decimal? MinAcceptanceRate = null,

    /// <summary>Why this reward is not being paid, when it is on hold.</summary>
    string? HoldReason = null);

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

    /// <summary>
    /// The platform's cut, so a request card can show what the driver actually
    /// keeps.
    /// </summary>
    /// <remarks>
    /// Sent with the home payload rather than fetched separately because the
    /// request card needs it the moment a request arrives, and an app that has
    /// to ask the server before it can show a net figure will show the gross
    /// one — which is the number that makes a driver feel cheated at settlement.
    /// </remarks>
    decimal CommissionPercentage,

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

/// <param name="Id">
/// The milestone being edited, as it came back in <see cref="GrowthMilestoneDto"/>.
/// Null means a new milestone.
/// <para>
/// This is here because position used to be identity. The upsert keyed on
/// <c>(campaign_id, sort_order)</c>, so reordering the list in the panel did
/// not move the rows — it overwrote their contents. Since a progress row that
/// has already paid out is never reopened, a reorder left one milestone
/// permanently unpayable and paid another a second time under a new id.
/// Sending the id back makes "the milestone the admin is looking at"
/// unambiguous, and leaves sort_order an ordinary editable field.
/// </para>
/// </param>
public sealed record GrowthMilestoneRequest(
    int SortOrder,
    string Title,
    string? Description,
    decimal RewardAmount,
    string ConditionType,
    decimal ConditionValue,
    Guid? Id = null);

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

// ──────────────────────────────────────────────────── earnings and ways to earn

/// <summary>What a Driver earned, and where it came from.</summary>
/// <remarks>
/// Three periods in one response rather than three requests. A Driver opening
/// this screen wants to compare today against the week — switching the tab
/// should not wait on the network, and on a mountain road it would.
/// </remarks>
public sealed record DriverEarningsDto(
    EarningsPeriodDto Today,
    EarningsPeriodDto Week,
    EarningsPeriodDto Month,

    /// <summary>The commission rate the platform is currently taking.</summary>
    decimal CommissionPercentage,

    /// <summary>Prepaid commission balance — what rides are paid for from.</summary>
    decimal CommissionBalance,

    /// <summary>Payout wallet: earned, cleared and waiting to be sent.</summary>
    decimal AvailableBalance,
    decimal PendingBalance,

    /// <summary>Every live way this Driver can earn, from real campaigns.</summary>
    IReadOnlyList<WayToEarnDto> WaysToEarn);

/// <summary>One period's figures, all of them measured, none estimated.</summary>
/// <param name="RideNet">Fares after commission.</param>
/// <param name="RideGross">Fares before commission.</param>
/// <param name="CommissionPaid">What the platform took.</param>
/// <param name="BonusEarned">Rewards credited — missions, peak hours, bonuses.</param>
/// <param name="Trips">Completed trips.</param>
/// <param name="OnlineSeconds">Credited online time.</param>
/// <param name="PerHour">
/// Ride plus bonus divided by hours online, or null under fifteen minutes
/// online — a figure from four minutes of work says nothing and reads as a
/// promise.
/// </param>
public sealed record EarningsPeriodDto(
    string Label,
    DateTimeOffset From,
    DateTimeOffset To,
    decimal RideNet,
    decimal RideGross,
    decimal CommissionPaid,
    decimal BonusEarned,
    int Trips,
    int OnlineSeconds,
    decimal? PerHour)
{
    public decimal Total => RideNet + BonusEarned;
}

/// <summary>One live earning route, described in what it actually pays.</summary>
/// <remarks>
/// Built from the campaigns an admin has configured and funded, never from
/// copy. A row that says "earn up to PKR 3,000" with nothing behind it is the
/// thing the specification forbids: no guaranteed income unless an Admin has
/// explicitly configured and funded that guarantee.
/// </remarks>
public sealed record WayToEarnDto(
    string Kind,
    string Title,
    string Detail,

    /// <summary>What it pays, or null when it varies by fare.</summary>
    decimal? Amount,

    /// <summary>Where the Driver goes to act on it, if anywhere.</summary>
    string? ActionPath);

/// <summary>What happened when a Driver entered somebody's referral code.</summary>
public sealed record ReferralApplyResultDto(string ReferrerName, string Code);

public sealed record ApplyReferralCodeRequest(string? Code);

/// <summary>This week's target, and what last week came to.</summary>
/// <param name="TargetRides">
/// Null when the city has no live weekly campaign. The screen says so rather
/// than drawing an empty bar — a target of zero reads as a bug.
/// </param>
/// <param name="LastWeekBestDay">
/// The day that earned most. The one line of a weekly summary a Driver acts on:
/// it tells them which day to clear their diary for next week.
/// </param>
public sealed record DriverWeeklyDto(
    string WeekLabel,
    int? TargetRides,
    int RidesThisWeek,
    decimal RewardAmount,
    bool RewardEarned,
    DateTimeOffset? WeekEndsAt,

    decimal LastWeekEarnings,
    int LastWeekRides,
    int LastWeekOnlineSeconds,
    decimal LastWeekReward,
    bool LastWeekRewardEarned,
    string? LastWeekBestDay,
    decimal LastWeekBestDayEarnings,
    int LastWeekBestDayRides);

/// <summary>A driver update as the admin portal lists it.</summary>
public sealed record AdminDriverUpdateDto(
    Guid Id,
    Guid? CityId,
    string CityName,
    string Category,
    string Title,
    string Body,
    string? ActionPath,
    DateTimeOffset PublishAt,
    DateTimeOffset? ExpiresAt,
    bool IsPublished,
    string CreatedBy);
