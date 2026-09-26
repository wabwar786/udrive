using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace UDrive.Api.Services;

/// <summary>
/// Signs in as a Customer, a Driver and a Hotel Owner in turn and drives one
/// complete journey through the live API, asserting at every step.
/// </summary>
/// <remarks>
/// <para><b>What this proves, and what it does not.</b></para>
///
/// <para>
/// It calls the API over HTTP, on the loopback address, exactly as the app
/// does. So it exercises routing, model binding, authorisation, the services,
/// the SQL and the response shapes — and it catches the failures that make the
/// app useless while every screen still renders: a broken query, a migration
/// that did not run, an endpoint that 500s, a permission that stopped working,
/// a status machine that no longer advances, a number that comes back wrong.
/// </para>
///
/// <para>
/// It says nothing at all about the Flutter screens. A green run with a
/// customer app that crashes on launch is perfectly possible: nothing here
/// builds, renders or taps anything. Layout, navigation, state, offline
/// behaviour and the widgets themselves are outside it.
/// </para>
///
/// <para><b>Why it calls itself over HTTP instead of calling the services.</b></para>
///
/// <para>
/// Calling <c>BookingService</c> directly would be simpler and would skip the
/// token minting below entirely. It would also skip the three layers where
/// things actually break in production — routing, authentication and JSON —
/// and the question this answers is "will the app work", not "does this method
/// work".
/// </para>
///
/// <para><b>Why the accounts are suspended between runs.</b></para>
///
/// <para>
/// Four accounts that can sign in are four ways into a live system. The JWT
/// handler in <c>Program.cs</c> rejects any token whose user is
/// <c>Suspended</c>, and rejects any token whose <c>token_version</c> no longer
/// matches. So the accounts sit suspended, are activated for the seconds a run
/// takes, and are suspended again afterwards with their token version bumped —
/// which kills the tokens this run minted at the same moment. Outside a run
/// they cannot be signed into at all, by anyone, with anything.
/// </para>
/// </remarks>
public sealed class SelfTestService(
    string connectionString,
    AuthSqlStore authStore,
    JwtTokenService tokenService,
    IHttpClientFactory httpClientFactory,
    ILogger<SelfTestService> logger)
{
    public const string HttpClientName = "selftest";

    /// <summary>One run at a time, process-wide.</summary>
    /// <remarks>
    /// Two runs at once would fight over the same three accounts and the same
    /// "one live ride at a time" rule, and both would fail for a reason that
    /// has nothing to do with the platform being broken.
    /// </remarks>
    private static readonly SemaphoreSlim Gate = new(1, 1);

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>Pakistan Standard Time, which has no daylight saving.</summary>
    private static readonly TimeSpan PakistanOffset = TimeSpan.FromHours(5);

    public const string EnabledVariable = "SELFTEST_ENABLED";

    public static bool Enabled => string.Equals(
        Environment.GetEnvironmentVariable(EnabledVariable),
        "true",
        StringComparison.OrdinalIgnoreCase);

    /// <summary>Where to send the loopback requests.</summary>
    /// <remarks>
    /// The API binds <c>0.0.0.0:$PORT</c>, so 127.0.0.1 on the same port
    /// reaches this very process without leaving the container. Overridable for
    /// the rare deployment where it does not.
    /// </remarks>
    public static string BaseUrl
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable("SELFTEST_BASE_URL")?.TrimEnd('/');
            if (!string.IsNullOrWhiteSpace(configured))
            {
                return configured;
            }

            var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
            return "http://127.0.0.1:" + port;
        }
    }

    // ------------------------------------------------------------------ run

    public async Task<SelfTestRunReport?> RunAsync(
        Guid? startedByUserId,
        string triggerSource,
        CancellationToken cancellationToken)
    {
        if (!await Gate.WaitAsync(TimeSpan.Zero, cancellationToken))
        {
            return null;
        }

        var runId = Guid.NewGuid();
        var startedAt = DateTimeOffset.UtcNow;
        var clock = Stopwatch.StartNew();
        var scenario = new SelfTestScenario(httpClientFactory.CreateClient(HttpClientName), BaseUrl);
        // Assigned in the finally below, which always runs. Given a starting
        // value anyway: a run that somehow reaches the report without cleanup
        // having been recorded should say so rather than claim it was clean.
        var cleanup = new SelfTestCleanupResult(
            false, [], [], "Cleanup did not run.");

        try
        {
            await RecordStartAsync(runId, triggerSource, startedByUserId, startedAt, cancellationToken);

            // Clear first, then run.
            //
            // A run that crashed halfway leaves a booking behind, and the very
            // first thing the next run does is ask for a ride — which the API
            // refuses with "you already have a ride under way". Clearing up
            // front means yesterday's failure cannot masquerade as today's.
            await ClearArtefactsAsync(CancellationToken.None);

            await EnsureAccountsAsync(cancellationToken);
            await SetAccountsSuspendedAsync(false, cancellationToken);

            await scenario.ExecuteAsync(
                await MintTokenAsync(SelfTestAccounts.CustomerEmail, cancellationToken),
                await MintTokenAsync(SelfTestAccounts.DriverEmail, cancellationToken),
                await MintTokenAsync(SelfTestAccounts.HotelOwnerEmail, cancellationToken),
                await MintTokenAsync(SelfTestAccounts.AdminEmail, cancellationToken),
                cancellationToken);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Self-test run {RunId} stopped on an unhandled error.", runId);
            scenario.RecordFailure("Run aborted", exception.Message);
        }
        finally
        {
            // Both of these run whatever happened above. An account left
            // active, or a booking left in the live database, is worse than a
            // failed test.
            cleanup = await CleanupAsync(CancellationToken.None);
            try
            {
                await SetAccountsSuspendedAsync(true, CancellationToken.None);
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Self-test accounts could not be suspended again after run {RunId}.", runId);
            }

            Gate.Release();
        }

        clock.Stop();
        var steps = scenario.Steps;
        var failed = steps.Count(step => step.Outcome == "Failed");
        var report = new SelfTestRunReport(
            runId,
            triggerSource,
            failed == 0 && cleanup.Clean ? "Passed" : "Failed",
            steps.Count,
            steps.Count(step => step.Outcome == "Passed"),
            failed,
            steps.Count(step => step.Outcome == "Skipped"),
            (int)clock.ElapsedMilliseconds,
            FirstProblem(steps, cleanup),
            steps,
            cleanup,
            startedAt,
            DateTimeOffset.UtcNow);

        await RecordFinishAsync(report, CancellationToken.None);
        return report;
    }

    private static string? FirstProblem(
        IReadOnlyList<SelfTestStepResult> steps,
        SelfTestCleanupResult cleanup)
    {
        var failure = steps.FirstOrDefault(step => step.Outcome == "Failed");
        if (failure is not null)
        {
            var detail = failure.Detail ?? "failed";
            return $"Step {failure.Number} ({failure.Name}): {detail}";
        }

        // Cleanup counts as a failure of the run even when every step passed.
        // Rows left in a live database are the one thing nobody should have to
        // discover later.
        if (!cleanup.Clean)
        {
            if (cleanup.Error is not null)
            {
                return cleanup.Error;
            }

            var left = string.Join(", ", cleanup.LeftBehind);
            return $"Cleanup left {cleanup.LeftBehind.Count} record(s) behind in the live database: {left}";
        }

        return null;
    }

    // -------------------------------------------------------------- history

    public async Task<IReadOnlyList<SelfTestRunSummary>> GetRunsAsync(
        int limit,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, trigger_source, status, total_steps, passed_steps,
                   failed_steps, skipped_steps, duration_ms, failure_summary,
                   started_at, finished_at
            FROM udrive.self_test_runs
            ORDER BY started_at DESC
            LIMIT @limit;
            """;

        var list = new List<SelfTestRunSummary>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("limit", Math.Clamp(limit, 1, 100));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new SelfTestRunSummary(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetInt32(3),
                reader.GetInt32(4),
                reader.GetInt32(5),
                reader.GetInt32(6),
                reader.GetInt32(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.GetFieldValue<DateTimeOffset>(9),
                reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10)));
        }

        return list;
    }

    public async Task<SelfTestRunReport?> GetRunAsync(Guid id, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, trigger_source, status, total_steps, passed_steps,
                   failed_steps, skipped_steps, duration_ms, failure_summary,
                   steps, cleanup, started_at, finished_at
            FROM udrive.self_test_runs
            WHERE id = @id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        var steps = JsonSerializer.Deserialize<List<SelfTestStepResult>>(reader.GetString(9), Json) ?? [];
        var cleanup = JsonSerializer.Deserialize<SelfTestCleanupResult>(reader.GetString(10), Json)
            ?? new SelfTestCleanupResult(true, [], [], null);

        return new SelfTestRunReport(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetInt32(3),
            reader.GetInt32(4),
            reader.GetInt32(5),
            reader.GetInt32(6),
            reader.GetInt32(7),
            reader.IsDBNull(8) ? null : reader.GetString(8),
            steps,
            cleanup,
            reader.GetFieldValue<DateTimeOffset>(11),
            reader.IsDBNull(12) ? null : reader.GetFieldValue<DateTimeOffset>(12));
    }

    private async Task RecordStartAsync(
        Guid runId,
        string triggerSource,
        Guid? startedByUserId,
        DateTimeOffset startedAt,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.self_test_runs
                (id, trigger_source, started_by_user_id, status, started_at)
            VALUES (@id, @source, @actor, 'Running', @startedAt);
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", runId);
        command.Parameters.AddWithValue("source", triggerSource);
        command.Parameters.Add(new NpgsqlParameter("actor", NpgsqlDbType.Uuid)
        {
            Value = (object?)startedByUserId ?? DBNull.Value
        });
        command.Parameters.AddWithValue("startedAt", startedAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task RecordFinishAsync(SelfTestRunReport report, CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.self_test_runs
            SET status=@status, total_steps=@total, passed_steps=@passed,
                failed_steps=@failed, skipped_steps=@skipped,
                duration_ms=@duration, failure_summary=@summary,
                steps=@steps::jsonb, cleanup=@cleanup::jsonb,
                finished_at=@finishedAt
            WHERE id=@id;
            """;

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(sql, connection);
            command.Parameters.AddWithValue("id", report.Id);
            command.Parameters.AddWithValue("status", report.Status);
            command.Parameters.AddWithValue("total", report.TotalSteps);
            command.Parameters.AddWithValue("passed", report.PassedSteps);
            command.Parameters.AddWithValue("failed", report.FailedSteps);
            command.Parameters.AddWithValue("skipped", report.SkippedSteps);
            command.Parameters.AddWithValue("duration", report.DurationMs);
            command.Parameters.Add(new NpgsqlParameter("summary", NpgsqlDbType.Text)
            {
                Value = (object?)report.FailureSummary ?? DBNull.Value
            });
            command.Parameters.AddWithValue("steps", JsonSerializer.Serialize(report.Steps, Json));
            command.Parameters.AddWithValue("cleanup", JsonSerializer.Serialize(report.Cleanup, Json));
            command.Parameters.AddWithValue("finishedAt", report.FinishedAt ?? DateTimeOffset.UtcNow);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (Exception exception)
        {
            // The report is still returned to the caller. Losing the history
            // row is a nuisance; swallowing the run's result would be worse.
            logger.LogError(exception, "Self-test run {RunId} finished but could not be recorded.", report.Id);
        }
    }

    // ------------------------------------------------------------- schedule

    public async Task<SelfTestScheduleDto> GetScheduleAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                COALESCE((SELECT value_json #>> '{}' FROM udrive.system_settings
                           WHERE key='selftest.schedule.enabled'), 'false'),
                COALESCE((SELECT value_json #>> '{}' FROM udrive.system_settings
                           WHERE key='selftest.schedule.time'), '03:00'),
                (SELECT started_at FROM udrive.self_test_runs ORDER BY started_at DESC LIMIT 1),
                (SELECT status FROM udrive.self_test_runs ORDER BY started_at DESC LIMIT 1);
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);

        var enabled = string.Equals(reader.GetString(0), "true", StringComparison.OrdinalIgnoreCase);
        var time = NormaliseTime(reader.GetString(1));
        var lastRunAt = reader.IsDBNull(2) ? (DateTimeOffset?)null : reader.GetFieldValue<DateTimeOffset>(2);
        var lastStatus = reader.IsDBNull(3) ? null : reader.GetString(3);

        return new SelfTestScheduleDto(
            enabled,
            time,
            lastRunAt,
            lastStatus,
            enabled ? NextRunAfter(DateTimeOffset.UtcNow, time) : null);
    }

    /// <summary>Whether a scheduled run has already happened since a moment.</summary>
    /// <remarks>
    /// How the scheduler decides it has done today's run. Reading the history is
    /// the only way that survives a restart: an in-memory "last run" field is
    /// lost on every deploy, which on a busy day means several runs, and on a
    /// quiet one means none.
    ///
    /// Manual runs are excluded deliberately. An Admin pressing Run at noon
    /// should not cancel the unattended 3am run that is the point of the
    /// schedule.
    /// </remarks>
    public async Task<bool> HasScheduledRunSinceAsync(
        DateTimeOffset since,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1 FROM udrive.self_test_runs
                 WHERE trigger_source = 'Scheduled'
                   AND started_at >= @since);
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("since", since);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    public async Task<SelfTestScheduleDto> SaveScheduleAsync(
        SaveSelfTestScheduleRequest request,
        Guid adminUserId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.system_settings (key, value_json, updated_by_user_id, created_at, updated_at)
            VALUES ('selftest.schedule.enabled', @enabled::jsonb, @admin, now(), now()),
                   ('selftest.schedule.time', @time::jsonb, @admin, now(), now())
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("enabled", request.Enabled ? "true" : "false");
        command.Parameters.AddWithValue("time", JsonSerializer.Serialize(NormaliseTime(request.Time)));
        command.Parameters.AddWithValue("admin", adminUserId);
        await command.ExecuteNonQueryAsync(cancellationToken);

        return await GetScheduleAsync(cancellationToken);
    }

    /// <summary>Forces any input into a valid <c>HH:mm</c>, defaulting to 03:00.</summary>
    /// <remarks>
    /// A malformed time must not stop the scheduler: the point of the daily run
    /// is that it happens without anybody watching, and a saved value of
    /// "3am please" silently disabling it is exactly the failure this harness
    /// exists to catch elsewhere.
    /// </remarks>
    public static string NormaliseTime(string? value)
    {
        if (TimeOnly.TryParseExact(value?.Trim(), "HH:mm", CultureInfo.InvariantCulture, out var parsed) ||
            TimeOnly.TryParse(value?.Trim(), CultureInfo.InvariantCulture, out parsed))
        {
            return parsed.ToString("HH\\:mm", CultureInfo.InvariantCulture);
        }

        return "03:00";
    }

    /// <summary>The next moment the configured local time comes round.</summary>
    public static DateTimeOffset NextRunAfter(DateTimeOffset utcNow, string localTime)
    {
        var time = TimeOnly.ParseExact(NormaliseTime(localTime), "HH:mm", CultureInfo.InvariantCulture);
        var local = utcNow.ToOffset(PakistanOffset);
        var candidate = new DateTimeOffset(
            local.Year, local.Month, local.Day,
            time.Hour, time.Minute, 0, PakistanOffset);

        return candidate <= local ? candidate.AddDays(1) : candidate;
    }

    // ------------------------------------------------------------- accounts

    /// <summary>
    /// Creates the four harness accounts if they are missing, and puts their
    /// driver profile, vehicle and wallet into the state the run needs.
    /// </summary>
    /// <remarks>
    /// Idempotent, and deliberately not a migration. See 056_self_test.sql.
    ///
    /// Every account is left <c>Suspended</c>; <see cref="SetAccountsSuspendedAsync"/>
    /// is what lifts that for the length of a run.
    /// </remarks>
    private async Task EnsureAccountsAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            -- The three signed-in roles plus the Admin the run needs for the
            -- two approval steps. Admin, not SuperAdmin: the harness approves a
            -- hotel and a tour package, and nothing else.
            INSERT INTO udrive.users
                (id, phone_number, email, full_name, role, status,
                 preferred_language, phone_verified, created_at, updated_at)
            VALUES
                (gen_random_uuid(), @customerPhone, @customerEmail, @customerName,
                 'Customer', 'Suspended', 'en', true, now(), now()),
                (gen_random_uuid(), @driverPhone, @driverEmail, @driverName,
                 'Driver', 'Suspended', 'en', true, now(), now()),
                (gen_random_uuid(), @hotelPhone, @hotelEmail, @hotelName,
                 'Customer', 'Suspended', 'en', true, now(), now()),
                (gen_random_uuid(), @adminPhone, @adminEmail, @adminName,
                 'Admin', 'Suspended', 'en', true, now(), now())
            ON CONFLICT (phone_number) DO UPDATE
            SET email = EXCLUDED.email,
                full_name = EXCLUDED.full_name,
                updated_at = now();

            INSERT INTO udrive.user_roles (user_id, role, created_at)
            SELECT u.id, 'Customer', now() FROM udrive.users u
             WHERE u.email IN (@customerEmail, @hotelEmail)
            ON CONFLICT (user_id, role) DO NOTHING;

            INSERT INTO udrive.user_roles (user_id, role, created_at)
            SELECT u.id, 'Driver', now() FROM udrive.users u WHERE u.email = @driverEmail
            ON CONFLICT (user_id, role) DO NOTHING;

            INSERT INTO udrive.user_roles (user_id, role, created_at)
            SELECT u.id, 'Admin', now() FROM udrive.users u WHERE u.email = @adminEmail
            ON CONFLICT (user_id, role) DO NOTHING;

            INSERT INTO udrive.customer_profiles (id, user_id, created_at, updated_at)
            SELECT gen_random_uuid(), u.id, now(), now() FROM udrive.users u
             WHERE u.email IN (@customerEmail, @hotelEmail)
            ON CONFLICT (user_id) DO NOTHING;

            -- Approved and online, because a Driver who is neither sees no ride
            -- requests at all and the run would fail on its own setup.
            INSERT INTO udrive.driver_profiles
                (id, user_id, verification_status, languages, service_areas,
                 is_online, created_at, updated_at)
            SELECT gen_random_uuid(), u.id, 'Approved', '{en}', '{Muzaffarabad}',
                   true, now(), now()
            FROM udrive.users u WHERE u.email = @driverEmail
            ON CONFLICT (user_id) DO UPDATE
            SET verification_status = 'Approved', is_online = true, updated_at = now();

            -- Capacity 4 and a readiness score of 85: the tour package rules
            -- refuse anything under 60, and the package books 4 seats.
            INSERT INTO udrive.vehicles
                (id, driver_profile_id, category, make, model, year,
                 registration_number, colour, passenger_capacity, luggage_capacity,
                 has_air_conditioning, has_heating, is_four_by_four,
                 mountain_readiness_score, status, booking_mode,
                 available_for_tour, created_at, updated_at)
            SELECT gen_random_uuid(), dp.id, 'Car', 'Self-test', 'Harness', 2024,
                   @registration, 'White', 4, 2, true, true, true,
                   85, 'Verified', 'Both', true, now(), now()
            FROM udrive.driver_profiles dp
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE u.email = @driverEmail
            ON CONFLICT (registration_number) DO UPDATE
            SET status = 'Verified',
                mountain_readiness_score = 85,
                available_for_tour = true,
                booking_mode = 'Both',
                updated_at = now();

            -- Prepaid commission, topped back up every run.
            --
            -- GetEligibleRideRequestsAsync stops showing requests to a Driver
            -- whose commission balance has run out, and the run spends some of
            -- it every time it starts a trip. Without this the harness would
            -- work for a few weeks and then start reporting a platform failure
            -- that was really its own empty wallet.
            INSERT INTO udrive.driver_wallets
                (id, driver_profile_id, commission_balance, created_at, updated_at)
            SELECT gen_random_uuid(), dp.id, 20000, now(), now()
            FROM udrive.driver_profiles dp
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE u.email = @driverEmail
            ON CONFLICT (driver_profile_id) DO UPDATE
            SET commission_balance = 20000,
                version = udrive.driver_wallets.version + 1,
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("customerPhone", SelfTestAccounts.CustomerPhone);
        command.Parameters.AddWithValue("customerEmail", SelfTestAccounts.CustomerEmail);
        command.Parameters.AddWithValue("customerName", SelfTestAccounts.CustomerName);
        command.Parameters.AddWithValue("driverPhone", SelfTestAccounts.DriverPhone);
        command.Parameters.AddWithValue("driverEmail", SelfTestAccounts.DriverEmail);
        command.Parameters.AddWithValue("driverName", SelfTestAccounts.DriverName);
        command.Parameters.AddWithValue("hotelPhone", SelfTestAccounts.HotelOwnerPhone);
        command.Parameters.AddWithValue("hotelEmail", SelfTestAccounts.HotelOwnerEmail);
        command.Parameters.AddWithValue("hotelName", SelfTestAccounts.HotelOwnerName);
        command.Parameters.AddWithValue("adminPhone", SelfTestAccounts.AdminPhone);
        command.Parameters.AddWithValue("adminEmail", SelfTestAccounts.AdminEmail);
        command.Parameters.AddWithValue("adminName", SelfTestAccounts.AdminName);
        command.Parameters.AddWithValue("registration", SelfTestAccounts.VehicleRegistration);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>Opens the four accounts for a run, or shuts them again after one.</summary>
    /// <remarks>
    /// Suspending also bumps <c>token_version</c>, which the JWT handler
    /// compares on every request — so the tokens this run minted stop working
    /// the instant the run ends, rather than lingering until they expire.
    /// </remarks>
    private async Task SetAccountsSuspendedAsync(bool suspended, CancellationToken cancellationToken)
    {
        var sql = suspended
            ? """
              UPDATE udrive.users
              SET status = 'Suspended',
                  token_version = token_version + 1,
                  updated_at = now()
              WHERE email LIKE @pattern;
              """
            : """
              UPDATE udrive.users
              SET status = 'Approved', updated_at = now()
              WHERE email LIKE @pattern;
              """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("pattern", SelfTestAccounts.EmailPattern);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>Issues an access token for one harness account.</summary>
    /// <remarks>
    /// Three things stop this becoming a way to mint a token for anybody:
    /// the controller is SuperAdmin-only, <c>SELFTEST_ENABLED</c> has to be
    /// true, and the check below refuses any address that is not one of the
    /// harness accounts. The token itself never leaves the server — it is used
    /// for the loopback calls and is not in the report.
    /// </remarks>
    private async Task<string> MintTokenAsync(string email, CancellationToken cancellationToken)
    {
        if (!SelfTestAccounts.AllEmails.Contains(email, StringComparer.Ordinal))
        {
            throw new InvalidOperationException(
                $"Refusing to mint a self-test token for {email}: not a self-test account.");
        }

        Guid userId;
        await using (var connection = new NpgsqlConnection(connectionString))
        {
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(
                "SELECT id FROM udrive.users WHERE email = @email;", connection);
            command.Parameters.AddWithValue("email", email);
            if (await command.ExecuteScalarAsync(cancellationToken) is not Guid found)
            {
                throw new InvalidOperationException($"Self-test account {email} is missing.");
            }

            userId = found;
        }

        // Through AuthSqlStore rather than hand-built claims, so the token this
        // run uses is put together by exactly the same code that builds a real
        // one — including driver_profile_id, which the Driver endpoints read.
        var user = await authStore.GetUserByIdAsync(userId, cancellationToken)
            ?? throw new InvalidOperationException($"Self-test account {email} could not be loaded.");
        var roles = await authStore.GetRolesAsync(userId, cancellationToken);
        return tokenService.CreateAccessToken(user, roles).Token;
    }

    // -------------------------------------------------------------- cleanup

    private async Task<SelfTestCleanupResult> CleanupAsync(CancellationToken cancellationToken)
    {
        try
        {
            var removed = await ClearArtefactsAsync(cancellationToken);
            var left = await RemainingArtefactsAsync(cancellationToken);
            return new SelfTestCleanupResult(left.Count == 0, removed, left, null);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Self-test cleanup failed.");
            IReadOnlyList<string> left;
            try
            {
                left = await RemainingArtefactsAsync(CancellationToken.None);
            }
            catch
            {
                left = ["unknown — the database could not be read"];
            }

            return new SelfTestCleanupResult(false, [], left, exception.Message);
        }
    }

    /// <summary>Deletes everything a run creates, in foreign-key order.</summary>
    /// <remarks>
    /// The order is not a guess. Children that cascade are left to their
    /// parents; the three that do not — wallet entries, earnings and payments —
    /// are deleted first by hand, because Postgres would otherwise refuse the
    /// booking and roll the whole thing back.
    ///
    /// The four accounts themselves are kept. Migration 055 established that
    /// hard-deleting a user is not viable here: twenty tables reference
    /// driver_profiles and more than thirty reference users. They stay,
    /// suspended.
    /// </remarks>
    private async Task<IReadOnlyList<string>> ClearArtefactsAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            WITH selftest AS (
                SELECT id, email FROM udrive.users WHERE email LIKE @pattern
            ), driver AS (
                SELECT dp.id FROM udrive.driver_profiles dp
                JOIN selftest s ON s.id = dp.user_id
            ), rides AS (
                SELECT b.id FROM udrive.bookings b
                JOIN selftest s ON s.id = b.customer_user_id
            )
            SELECT
                (SELECT count(*) FROM rides),
                (SELECT count(*) FROM udrive.ride_requests rr
                  JOIN selftest s ON s.id = rr.customer_user_id),
                (SELECT count(*) FROM udrive.hotels h
                  JOIN selftest s ON s.id = h.owner_user_id),
                (SELECT count(*) FROM udrive.hotel_bookings hb
                  JOIN selftest s ON s.id = hb.customer_user_id),
                (SELECT count(*) FROM udrive.tour_packages tp
                  JOIN driver d ON d.id = tp.driver_profile_id);
            """;

        var counts = new long[5];
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var count = new NpgsqlCommand(sql, connection))
        {
            count.Parameters.AddWithValue("pattern", SelfTestAccounts.EmailPattern);
            await using var reader = await count.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                for (var index = 0; index < counts.Length; index++)
                {
                    counts[index] = reader.GetInt64(index);
                }
            }
        }

        const string deleteSql = """
            CREATE TEMP TABLE selftest_users(id uuid PRIMARY KEY) ON COMMIT DROP;
            INSERT INTO selftest_users(id)
            SELECT id FROM udrive.users WHERE email LIKE @pattern;

            CREATE TEMP TABLE selftest_drivers(id uuid PRIMARY KEY) ON COMMIT DROP;
            INSERT INTO selftest_drivers(id)
            SELECT dp.id FROM udrive.driver_profiles dp
            JOIN selftest_users s ON s.id = dp.user_id;

            CREATE TEMP TABLE selftest_bookings(id uuid PRIMARY KEY) ON COMMIT DROP;
            INSERT INTO selftest_bookings(id)
            SELECT b.id FROM udrive.bookings b
            JOIN selftest_users s ON s.id = b.customer_user_id;

            -- Hotel side. hotel_rooms and hotel_room_inventory cascade from
            -- hotels; hotel_bookings does not, so it goes first.
            DELETE FROM udrive.hotel_bookings hb
             USING selftest_users s WHERE s.id = hb.customer_user_id;
            DELETE FROM udrive.hotels h
             USING selftest_users s WHERE s.id = h.owner_user_id;

            -- Tour packages cascade to their images, itinerary, rules, offers,
            -- holds, waitlist and departures.
            DELETE FROM udrive.tour_packages tp
             USING selftest_drivers d WHERE d.id = tp.driver_profile_id;

            -- The three that will not cascade from bookings.
            --
            -- Wallet entries go by wallet rather than by booking, so the whole
            -- ledger is cleared and not just the lines a booking produced. The
            -- welcome credit has no booking_id, and leaving it while the balance
            -- below is reset would make the wallet disagree with its own
            -- history.
            --
            -- Entries before earnings: driver_wallet_entries.earning_id points
            -- at driver_earnings.
            DELETE FROM udrive.driver_wallet_entries e
             USING udrive.driver_wallets w, selftest_drivers d
             WHERE e.wallet_id = w.id AND w.driver_profile_id = d.id;
            DELETE FROM udrive.driver_earnings de
             USING selftest_bookings b WHERE b.id = de.booking_id;
            DELETE FROM udrive.payments p
             USING selftest_bookings b WHERE b.id = p.booking_id;

            -- Bookings cascade to trip_operations, trip_assignments,
            -- trip_status_history, trip_ratings, trip_messages and the rest.
            DELETE FROM udrive.bookings b2
             USING selftest_bookings b WHERE b.id = b2.id;

            -- Ride requests cascade to driver_offers and the decision rows.
            -- selected_offer_id is nulled first: it points at a driver_offers
            -- row that the cascade is about to remove.
            UPDATE udrive.ride_requests rr
               SET selected_offer_id = NULL
              FROM selftest_users s
             WHERE s.id = rr.customer_user_id;
            DELETE FROM udrive.ride_requests rr
             USING selftest_users s WHERE s.id = rr.customer_user_id;

            -- The presence ping, so no stale location survives the run.
            DELETE FROM udrive.driver_presence_locations dpl
             USING selftest_drivers d WHERE d.id = dpl.driver_profile_id;

            -- The wallet and its ledger are emptied together, so the balance
            -- and the entries still agree with each other.
            UPDATE udrive.driver_wallets w
               SET commission_balance = 20000,
                   pending_balance = 0,
                   available_balance = 0,
                   paid_balance = 0,
                   version = w.version + 1,
                   updated_at = now()
              FROM selftest_drivers d
             WHERE d.id = w.driver_profile_id;

            DELETE FROM udrive.notifications n
             USING selftest_users s WHERE s.id = n.user_id;
            """;

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        try
        {
            await using var delete = new NpgsqlCommand(deleteSql, connection, transaction);
            delete.CommandTimeout = 60;
            delete.Parameters.AddWithValue("pattern", SelfTestAccounts.EmailPattern);
            await delete.ExecuteNonQueryAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        var removed = new List<string>();
        void Note(long value, string singular, string plural)
        {
            if (value > 0)
            {
                removed.Add($"{value} {(value == 1 ? singular : plural)}");
            }
        }

        Note(counts[0], "ride booking", "ride bookings");
        Note(counts[1], "ride request", "ride requests");
        Note(counts[2], "hotel", "hotels");
        Note(counts[3], "hotel booking", "hotel bookings");
        Note(counts[4], "tour package", "tour packages");
        return removed;
    }

    /// <summary>What is still in the live database under a harness account.</summary>
    private async Task<IReadOnlyList<string>> RemainingArtefactsAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            WITH selftest AS (
                SELECT id FROM udrive.users WHERE email LIKE @pattern
            ), driver AS (
                SELECT dp.id FROM udrive.driver_profiles dp
                JOIN selftest s ON s.id = dp.user_id
            )
            SELECT
                (SELECT count(*) FROM udrive.bookings b JOIN selftest s ON s.id = b.customer_user_id),
                (SELECT count(*) FROM udrive.ride_requests rr JOIN selftest s ON s.id = rr.customer_user_id),
                (SELECT count(*) FROM udrive.hotels h JOIN selftest s ON s.id = h.owner_user_id),
                (SELECT count(*) FROM udrive.hotel_bookings hb JOIN selftest s ON s.id = hb.customer_user_id),
                (SELECT count(*) FROM udrive.tour_packages tp JOIN driver d ON d.id = tp.driver_profile_id);
            """;

        var labels = new[]
        {
            "ride booking(s)", "ride request(s)", "hotel(s)",
            "hotel booking(s)", "tour package(s)"
        };

        var left = new List<string>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("pattern", SelfTestAccounts.EmailPattern);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (await reader.ReadAsync(cancellationToken))
        {
            for (var index = 0; index < labels.Length; index++)
            {
                var value = reader.GetInt64(index);
                if (value > 0)
                {
                    left.Add($"{value} {labels[index]}");
                }
            }
        }

        return left;
    }
}
