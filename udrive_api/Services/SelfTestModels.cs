namespace UDrive.Api.Services;

/// <summary>One thing the self-test tried, and what happened.</summary>
/// <param name="Outcome">
/// <c>Passed</c>, <c>Failed</c> or <c>Skipped</c>. A skipped step is never
/// counted as a pass: either an earlier step failed and this one could not be
/// attempted, or the endpoint it needs does not exist in this build.
/// </param>
/// <param name="Detail">
/// Why it failed or was skipped, in words an Admin can act on. Null when it
/// passed and there is nothing to say.
/// </param>
public sealed record SelfTestStepResult(
    int Number,
    string Name,
    string Role,
    string Method,
    string Path,
    int? HttpStatus,
    int DurationMs,
    string Outcome,
    string? Detail);

/// <summary>What the run created, and what it managed to remove again.</summary>
/// <remarks>
/// <see cref="LeftBehind"/> is the field that matters. The self-test writes to
/// the live database, so anything it cannot delete is a real row somebody has
/// to know about — it will show up in bookings lists, revenue figures and
/// hotel searches until it is removed by hand.
/// </remarks>
public sealed record SelfTestCleanupResult(
    bool Clean,
    IReadOnlyList<string> Removed,
    IReadOnlyList<string> LeftBehind,
    string? Error);

public sealed record SelfTestRunReport(
    Guid Id,
    string TriggerSource,
    string Status,
    int TotalSteps,
    int PassedSteps,
    int FailedSteps,
    int SkippedSteps,
    int DurationMs,
    string? FailureSummary,
    IReadOnlyList<SelfTestStepResult> Steps,
    SelfTestCleanupResult Cleanup,
    DateTimeOffset StartedAt,
    DateTimeOffset? FinishedAt);

public sealed record SelfTestRunSummary(
    Guid Id,
    string TriggerSource,
    string Status,
    int TotalSteps,
    int PassedSteps,
    int FailedSteps,
    int SkippedSteps,
    int DurationMs,
    string? FailureSummary,
    DateTimeOffset StartedAt,
    DateTimeOffset? FinishedAt);

/// <summary>The daily run, as the admin portal sees it.</summary>
/// <param name="Time">
/// Local Pakistan time (UTC+5) as <c>HH:mm</c>. Pakistan does not observe
/// daylight saving, so a fixed offset is correct here and will stay correct.
/// </param>
/// <param name="EnabledAt">
/// When the daily run was last switched on.
/// </param>
/// <remarks>
/// Needed so that turning the schedule on at two in the afternoon does not
/// immediately fire the run: this morning's 03:00 has passed and no scheduled
/// run has happened since, which without this reads as "today's run is owed".
/// The first run belongs at the next 03:00, not now.
/// </remarks>
public sealed record SelfTestScheduleDto(
    bool Enabled,
    string Time,
    DateTimeOffset? LastRunAt,
    string? LastRunStatus,
    DateTimeOffset? NextRunAt,
    DateTimeOffset? EnabledAt);

public sealed record SaveSelfTestScheduleRequest(bool Enabled, string Time);
