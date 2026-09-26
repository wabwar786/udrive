namespace UDrive.Api.Services;

/// <summary>
/// Runs the self-test once a day, at the local time an Admin chose, if they
/// switched it on.
/// </summary>
/// <remarks>
/// <para>
/// Modelled on <see cref="ProductionMaintenanceService"/>: a
/// <see cref="BackgroundService"/> that wakes, checks, and sleeps again. It
/// wakes every five minutes rather than sleeping until the exact moment,
/// because the schedule can be changed from the admin portal at any time and a
/// long sleep would not notice for hours.
/// </para>
///
/// <para>
/// "Once a day" is decided from the run history, not from a timer: it looks for
/// a scheduled run since the last time the chosen hour came round. So a deploy,
/// a restart or a container being moved does not produce a second run, and does
/// not lose the day's run either.
/// </para>
/// </remarks>
public sealed class SelfTestScheduler(
    IServiceScopeFactory scopeFactory,
    ILogger<SelfTestScheduler> logger) : BackgroundService
{
    private static readonly TimeSpan Tick = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!SelfTestService.Enabled)
        {
            logger.LogInformation(
                "Self-test scheduler is not running: {Variable} is not true.",
                SelfTestService.EnabledVariable);
            return;
        }

        // The same two minutes ProductionMaintenanceService waits. Migrations
        // and the HTTP listener both need to be up before anything calls the API
        // on itself, and on a cold start they are not.
        await Task.Delay(TimeSpan.FromMinutes(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await TickAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "The self-test scheduler's check failed.");
            }

            try
            {
                await Task.Delay(Tick, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task TickAsync(CancellationToken stoppingToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var service = scope.ServiceProvider.GetRequiredService<SelfTestService>();

        var schedule = await service.GetScheduleAsync(stoppingToken);
        if (!schedule.Enabled)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;

        // The most recent time the chosen hour came round. NextRunAfter always
        // returns a moment in the future, so a day back from it is the last one
        // that has passed.
        var due = SelfTestService.NextRunAfter(now, schedule.Time).AddDays(-1);
        if (due > now)
        {
            return;
        }

        // A due time from before the schedule was switched on is not owed.
        //
        // Turning the daily run on at two in the afternoon would otherwise fire
        // it immediately: this morning's 03:00 has passed and no scheduled run
        // has happened since it, which looks exactly like a missed run. The
        // first run belongs at the next 03:00.
        if (schedule.EnabledAt is { } enabledAt && due < enabledAt)
        {
            return;
        }

        if (await service.HasScheduledRunSinceAsync(due, stoppingToken))
        {
            return;
        }

        logger.LogInformation("Starting the daily self-test run for {Due:u}.", due);
        var report = await service.RunAsync(null, "Scheduled", stoppingToken);

        if (report is null)
        {
            // A manual run was already in flight. Today's scheduled run is
            // skipped rather than queued: two runs back to back would fight over
            // the same accounts, and the manual one is the more useful of the
            // two anyway.
            logger.LogInformation("The daily self-test was skipped: a run was already in progress.");
            return;
        }

        if (report.Status == "Passed")
        {
            logger.LogInformation(
                "The daily self-test passed: {Passed} passed, {Skipped} skipped, in {Duration} ms.",
                report.PassedSteps, report.SkippedSteps, report.DurationMs);
        }
        else
        {
            // Warning, not Error: this is a report about the platform, and an
            // error-level line here would be indistinguishable from the API
            // itself falling over.
            logger.LogWarning(
                "The daily self-test FAILED: {Failed} of {Total} steps. First problem: {Problem}",
                report.FailedSteps, report.TotalSteps, report.FailureSummary);
        }
    }
}
