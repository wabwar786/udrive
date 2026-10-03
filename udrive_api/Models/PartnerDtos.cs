namespace UDrive.Api.Models;

// Territory partners — everything the three partner controllers send and receive.
//
// Names are prefixed `Partner*` / `Territory*` throughout, including where a
// shorter name was free. Two DTOs called `CityDto` in one assembly is a build
// error discovered on Railway rather than here, and this project has already
// paid for that once (`ExpectedDemandDto` in growth zip 6).

// ───────────────────────────────────────────────────────────── the territory

public sealed record TerritoryNodeDto(
    Guid Id,
    Guid? ParentId,
    string Kind,
    string Name,
    Guid? LaunchCityId,
    string? LaunchStatus,
    bool IsActive,
    int Depth,
    string Path,
    // The partner holding it, if any — this is what makes a territory "taken".
    Guid? PartnerId,
    string? PartnerName,
    string? PartnerStatus,
    string? TierKey,
    int DriverCount,
    int WaitingCount,
    int PendingApplications);

public sealed record TerritoryRequest(
    Guid? ParentId,
    string Kind,
    string Name,
    Guid? LaunchCityId,
    bool IsActive,
    string? Notes);

public sealed record LaunchCityAreaDto(
    Guid Id,
    Guid LaunchCityId,
    string? Label,
    double Latitude,
    double Longitude,
    decimal RadiusKm);

public sealed record LaunchCityAreaRequest(
    Guid LaunchCityId,
    string? Label,
    double Latitude,
    double Longitude,
    decimal RadiusKm);

/// <summary>What the app shows when it knows where the customer is.</summary>
/// <param name="CityId">
/// Null when no circle contains the point. The app then asks rather than
/// guessing — a wrong city is worse than an unanswered question, because the
/// customer is told the service is unavailable in a city they are not in.
/// </param>
public sealed record CityStatusDto(
    Guid? CityId,
    string? CityName,
    bool IsLive,
    string? LaunchStatus,
    bool OnWaitlist,
    int WaitingCount,
    int DriverCount,
    bool PartnerWanted,
    IReadOnlyList<CityStatusEntryDto> Cities);

public sealed record CityStatusEntryDto(
    Guid Id,
    string Name,
    bool IsLive,
    string LaunchStatus,
    int WaitingCount,
    bool PartnerWanted);

public sealed record WaitlistJoinRequest(Guid CityId, bool NotifyOnOpen);

public sealed record WaitlistEntryDto(
    Guid Id,
    Guid CityId,
    string CityName,
    Guid UserId,
    string? FullName,
    string? PhoneNumber,
    bool NotifyOnOpen,
    DateTimeOffset CreatedAt);

// ───────────────────────────────────────────────────────────────── the tiers

public sealed record PartnerTierDto(
    string TierKey,
    string DisplayName,
    string TerritoryKind,
    decimal SecurityDeposit,
    decimal CommissionSharePct,
    int TermMonths,
    string? Description,
    bool IsActive,
    IReadOnlyList<PartnerCommitmentDefaultDto> Commitments);

public sealed record PartnerCommitmentDefaultDto(
    Guid Id,
    string MetricKey,
    decimal TargetValue,
    string Label,
    bool IsActive);

public sealed record PartnerTierRequest(
    string DisplayName,
    decimal SecurityDeposit,
    decimal CommissionSharePct,
    int TermMonths,
    string? Description,
    bool IsActive,
    IReadOnlyList<PartnerCommitmentDefaultRequest>? Commitments);

public sealed record PartnerCommitmentDefaultRequest(
    string MetricKey,
    decimal TargetValue,
    string Label,
    bool IsActive);

// ────────────────────────────────────────────────────────── the application

public sealed record PartnerApplicationDto(
    Guid Id,
    Guid UserId,
    string? FullName,
    string? PhoneNumber,
    string TierKey,
    string TierName,
    Guid TerritoryId,
    string TerritoryName,
    string TerritoryKind,
    string? ApplicantNote,
    string? ContactPhone,
    string Status,
    string? DecisionReason,
    DateTimeOffset? DecidedAt,
    string? DecidedByName,
    DateTimeOffset CreatedAt,
    // The applicant's own history with UDrive, so a decision is not made on a
    // name alone.
    DateTimeOffset? CustomerSince,
    int CompletedRides,
    // Whether the territory is still free. An application can sit in the queue
    // while somebody else signs for the same place.
    bool TerritoryAvailable);

public sealed record PartnerApplicationRequest(
    string TierKey,
    Guid TerritoryId,
    string? Note,
    string? ContactPhone);

public sealed record PartnerDecisionRequest(bool Approve, string? Reason);

/// <summary>What the customer app shows on the "Become a partner" screen.</summary>
public sealed record PartnerOpeningsDto(
    IReadOnlyList<PartnerTierDto> Tiers,
    IReadOnlyList<TerritoryNodeDto> Territories,
    PartnerSelfDto? Mine);

/// <summary>The applicant's own position: applied, waiting, or a partner.</summary>
public sealed record PartnerSelfDto(
    Guid? ApplicationId,
    string? ApplicationStatus,
    string? ApplicationTerritory,
    string? DecisionReason,
    DateTimeOffset? AppliedAt,
    Guid? PartnerId,
    string? PartnerStatus,
    string? PartnerTierName,
    string? PartnerTerritory,
    bool ContractAwaitingSignature);

// ─────────────────────────────────────────────────────────────── the partner

public sealed record PartnerListItemDto(
    Guid Id,
    Guid UserId,
    string FullName,
    string? PhoneNumber,
    string TierKey,
    string TierName,
    Guid TerritoryId,
    string TerritoryName,
    string TerritoryKind,
    string Status,
    DateTimeOffset? StartedAt,
    DateTimeOffset? EndedAt,
    Guid? ContractId,
    string? ContractReference,
    string? ContractStatus,
    decimal CommissionSharePct,
    decimal SecurityDeposit,
    int CommitmentsMet,
    int CommitmentsMissed,
    decimal CurrentMonthShare);

public sealed record PartnerDetailDto(
    PartnerListItemDto Partner,
    PartnerContractDto? Contract,
    IReadOnlyList<PartnerCommitmentDto> Commitments,
    IReadOnlyList<PartnerPeriodDto> Periods,
    IReadOnlyList<PartnerStatementDto> Statements,
    PartnerEvidenceSummaryDto? Evidence);

public sealed record PartnerStatusRequest(string Status, string? Reason);

// ────────────────────────────────────────────────────────────── the contract

public sealed record PartnerContractDto(
    Guid Id,
    Guid PartnerId,
    string Reference,
    string Status,
    string RenderedText,
    string VideoScript,
    decimal SecurityDeposit,
    decimal CommissionSharePct,
    int TermMonths,
    DateTimeOffset? SentAt,
    DateTimeOffset? SignedAt,
    DateTimeOffset? StartsAt,
    DateTimeOffset? EndsAt,
    DateTimeOffset? TerminatedAt,
    string? TerminationReason);

public sealed record PartnerContractDraftRequest(
    Guid? TemplateId,
    decimal? SecurityDeposit,
    decimal? CommissionSharePct,
    int? TermMonths);

public sealed record PartnerContractEditRequest(
    string RenderedText,
    string VideoScript,
    decimal SecurityDeposit,
    decimal CommissionSharePct,
    int TermMonths,
    IReadOnlyList<PartnerCommitmentDefaultRequest>? Commitments);

public sealed record PartnerTerminateRequest(string Reason);

public sealed record PartnerContractTemplateDto(
    Guid Id,
    string TierKey,
    int Version,
    string Title,
    string BodyMd,
    string VideoScript,
    bool IsActive,
    DateTimeOffset CreatedAt);

public sealed record PartnerContractTemplateRequest(
    string Title,
    string BodyMd,
    string VideoScript,
    bool IsActive);

// ─────────────────────────────────────────────────────────── commitments

public sealed record PartnerCommitmentDto(
    Guid Id,
    string MetricKey,
    decimal TargetValue,
    string Label,
    bool IsActive,
    // This month so far, computed live. The stored period row is the record;
    // this is the running number the partner watches.
    decimal CurrentValue,
    string CurrentStatus,
    // True for metrics the database cannot answer by itself.
    bool IsManual,
    // Said plainly rather than shown as a confident zero: a Tehsil Head has no
    // drivers until somebody assigns drivers to that tehsil.
    string? Caveat);

public sealed record PartnerPeriodDto(
    Guid Id,
    Guid CommitmentId,
    string MetricKey,
    string Label,
    DateOnly PeriodStart,
    DateOnly PeriodEnd,
    decimal TargetValue,
    decimal ActualValue,
    string Status,
    string? Note,
    DateTimeOffset ComputedAt);

public sealed record PartnerPeriodRecordRequest(
    decimal? ActualValue,
    string Status,
    string? Note);

// ──────────────────────────────────────────────────────────── statements

public sealed record PartnerStatementDto(
    Guid Id,
    DateOnly PeriodStart,
    DateOnly PeriodEnd,
    int CompletedRides,
    decimal GrossFares,
    decimal CommissionBase,
    decimal SharePct,
    decimal ShareAmount,
    string Status,
    string? PaidReference,
    DateTimeOffset? PaidAt,
    string? Note,
    DateTimeOffset ComputedAt);

public sealed record PartnerStatementPaidRequest(string Reference, string? Note);

// ───────────────────────────────────────────────────────────── the evidence

/// <summary>
/// What an ordinary admin may see about the signature: that it exists, when,
/// and from where. Never the photograph or the video.
/// </summary>
public sealed record PartnerEvidenceSummaryDto(
    bool Exists,
    DateTimeOffset? SignedAtServer,
    string? PhoneNumber,
    string? IpAddress,
    string? DeviceInfo,
    DateOnly? PurgeAfter,
    DateTimeOffset? PurgedAt,
    bool CanView);

/// <summary>
/// The files themselves, for SuperAdmin only. Returned by a route that writes an
/// <c>audit_logs</c> row before it answers.
/// </summary>
public sealed record PartnerEvidenceDto(
    Guid ContractId,
    string Reference,
    string PartnerName,
    string SelfieUrl,
    string VideoUrl,
    string ScriptShown,
    DateTimeOffset SignedAtServer,
    string? PhoneNumber,
    string? IpAddress,
    string? DeviceInfo,
    DateOnly? PurgeAfter);

// ───────────────────────────────────────────────── the partner's own portal

public sealed record PartnerPortalDto(
    string FullName,
    string? PhoneNumber,
    string TierName,
    string TerritoryName,
    string TerritoryKind,
    string PartnerStatus,
    PartnerContractDto? Contract,
    IReadOnlyList<PartnerCommitmentDto> Commitments,
    IReadOnlyList<PartnerPeriodDto> RecentPeriods,
    IReadOnlyList<PartnerStatementDto> Statements,
    PartnerPortalTotalsDto Totals,
    // The one sentence that stops the "where is my money" message: payment
    // happens outside the app, and this screen is the agreed record of it.
    string PayoutNote);

public sealed record PartnerPortalTotalsDto(
    int DriversInTerritory,
    int NewDriversThisMonth,
    int ActiveDriversThisMonth,
    int CompletedRidesThisMonth,
    decimal CommissionBaseThisMonth,
    decimal ShareThisMonth,
    decimal ShareOwedUnpaid,
    decimal SharePaidToDate);

public sealed record PartnerSignRequest(string? DeviceInfo);
