using System.Security.Cryptography;
using System.Text;
using Npgsql;
using UDrive.Api.Common;

namespace UDrive.Api.Services;

public sealed record TestRunDto(
    Guid Id,
    string Suite,
    string? Title,
    string Status,
    string? Source,
    string? CommitSha,
    int StepsTotal,
    int StepsPassed,
    int StepsFailed,
    DateTimeOffset StartedAt,
    DateTimeOffset? FinishedAt);

public sealed record TestStepDto(
    Guid Id,
    int Seq,
    string Name,
    string Status,
    string? Detail,
    string Device,
    string? ScreenshotUrl,
    DateTimeOffset CreatedAt);

public sealed record TestRunDetailDto(TestRunDto Run, IReadOnlyList<TestStepDto> Steps);

public sealed record TestImprovementDto(
    Guid Id,
    Guid? RunId,
    Guid? StepId,
    string? Suite,
    string? StepName,
    string? ScreenshotUrl,
    string Note,
    string Status,
    string? CreatedBy,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DoneAt);

public sealed record TestingOverviewDto(
    bool KeyConfigured,
    IReadOnlyList<TestRunDto> Runs,
    int ImprovementsOpen,
    int ImprovementsDone);

public sealed record TestKeyDto(string Key);

public sealed record StartTestRunRequest(string Suite, string? Title, string? Source, string? CommitSha);

public sealed record FinishTestRunRequest(string? Status);

public sealed record TestImprovementRequest(Guid? StepId, Guid? RunId, string Note);

public sealed record TestImprovementStatusRequest(string Status);

/// <summary>
/// Live testing: the automated app tests on staging report every step (with a
/// screenshot) here; Admin → Live testing shows them as they arrive, and the
/// Admin writes improvements against the screen they are looking at.
/// </summary>
/// <remarks>
/// The tests sign in with the Google Play reviewer account (otp.test.phone) and
/// report with that token. A key (header <c>X-Test-Key</c>, only its SHA-256
/// stored) also works, for a runner that cannot sign in.
/// </remarks>
public sealed class TestingService(string connectionString, LocalFileStorageService storage)
{
    public const string KeySetting = "testing.reporter_key";
    private static readonly string[] Devices = ["customer", "driver", "owner", "admin"];
    private static readonly string[] StepStatuses = ["Running", "Passed", "Failed", "Skipped", "Info"];

    // ---- Reporter (the tests) -------------------------------------------------

    public async Task<bool> KeyMatchesAsync(string? key, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(key)) return false;
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            "SELECT value_json #>> '{}' FROM udrive.system_settings WHERE key = @key;", connection);
        command.Parameters.AddWithValue("key", KeySetting);
        var stored = (await command.ExecuteScalarAsync(ct))?.ToString();
        if (string.IsNullOrEmpty(stored)) return false;
        var given = Encoding.ASCII.GetBytes(Hash(key.Trim()));
        var expected = Encoding.ASCII.GetBytes(stored);
        return given.Length == expected.Length && CryptographicOperations.FixedTimeEquals(given, expected);
    }

    /// <summary>
    /// Is this the Google Play reviewer account (otp.test.phone)? The tests sign
    /// in with it, so they need no key of their own and no GitHub secret.
    /// </summary>
    public async Task<bool> IsTestAccountAsync(Guid? userId, CancellationToken ct)
    {
        if (userId is null) return false;
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            SELECT EXISTS (
                SELECT 1 FROM udrive.users u, udrive.system_settings s
                WHERE u.id = @user AND s.key = 'otp.test.phone'
                  AND length(regexp_replace(s.value_json #>> '{}', '\D', '', 'g')) >= 10
                  AND right(regexp_replace(u.phone_number, '\D', '', 'g'), 10)
                    = right(regexp_replace(s.value_json #>> '{}', '\D', '', 'g'), 10));
            """, connection);
        command.Parameters.AddWithValue("user", userId.Value);
        return await command.ExecuteScalarAsync(ct) is true;
    }

    public async Task<ServiceResult<TestRunDto>> StartRunAsync(StartTestRunRequest request, CancellationToken ct)
    {
        var suite = Clip(request.Suite, 80);
        if (string.IsNullOrWhiteSpace(suite))
            return ServiceResult<TestRunDto>.Fail(400, "suite_required", "Suite ka naam zaroori hai.");

        await using var connection = await OpenAsync(ct);

        // A run whose machine died never says it finished.
        await using (var stale = new NpgsqlCommand(
            """
            UPDATE udrive.test_runs SET status = 'Stopped', finished_at = now()
            WHERE status = 'Running' AND started_at < now() - interval '2 hours';
            """, connection))
        {
            await stale.ExecuteNonQueryAsync(ct);
        }

        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.test_runs (suite, title, source, commit_sha)
            VALUES (@suite, @title, @source, @sha)
            RETURNING id;
            """, connection);
        command.Parameters.AddWithValue("suite", suite);
        command.Parameters.AddWithValue("title", (object?)Clip(request.Title, 160) ?? DBNull.Value);
        command.Parameters.AddWithValue("source", (object?)Clip(request.Source, 120) ?? DBNull.Value);
        command.Parameters.AddWithValue("sha", (object?)Clip(request.CommitSha, 64) ?? DBNull.Value);
        var id = (Guid)(await command.ExecuteScalarAsync(ct))!;
        var run = await ReadRunAsync(connection, id, ct);
        return ServiceResult<TestRunDto>.Created(run!);
    }

    public async Task<ServiceResult<TestStepDto>> AddStepAsync(
        Guid runId, string name, string? status, string? detail, string? device, IFormFile? file, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(name))
            return ServiceResult<TestStepDto>.Fail(400, "name_required", "Step ka naam zaroori hai.");
        var cleanStatus = StepStatuses.FirstOrDefault(s => s.Equals(status?.Trim(), StringComparison.OrdinalIgnoreCase)) ?? "Info";
        var cleanDevice = Devices.FirstOrDefault(d => d.Equals(device?.Trim(), StringComparison.OrdinalIgnoreCase)) ?? "customer";

        await using var connection = await OpenAsync(ct);
        var run = await ReadRunAsync(connection, runId, ct);
        if (run is null) return ServiceResult<TestStepDto>.Fail(404, "run_not_found", "Test run nahi mila.");
        if (run.Status != "Running") return ServiceResult<TestStepDto>.Fail(409, "run_finished", "Yeh run khatam ho chuka hai.");

        string? url = null;
        if (file is { Length: > 0 })
        {
            try
            {
                url = (await storage.SaveAsync(file, "test-shots", runId, ct)).RelativeUrl;
            }
            catch (InvalidDataException)
            {
                // A bad screenshot does not lose the step.
            }
        }

        await using var tx = await connection.BeginTransactionAsync(ct);
        await using (var lockRun = new NpgsqlCommand("SELECT 1 FROM udrive.test_runs WHERE id = @id FOR UPDATE;", connection, tx))
        {
            lockRun.Parameters.AddWithValue("id", runId);
            await lockRun.ExecuteNonQueryAsync(ct);
        }

        await using var insert = new NpgsqlCommand(
            """
            INSERT INTO udrive.test_steps (run_id, seq, name, status, detail, device, screenshot_url)
            VALUES (@run, (SELECT COALESCE(MAX(seq), 0) + 1 FROM udrive.test_steps WHERE run_id = @run),
                    @name, @status, @detail, @device, @url)
            RETURNING id;
            """, connection, tx);
        insert.Parameters.AddWithValue("run", runId);
        insert.Parameters.AddWithValue("name", Clip(name, 200)!);
        insert.Parameters.AddWithValue("status", cleanStatus);
        insert.Parameters.AddWithValue("detail", (object?)Clip(detail, 2000) ?? DBNull.Value);
        insert.Parameters.AddWithValue("device", cleanDevice);
        insert.Parameters.AddWithValue("url", (object?)url ?? DBNull.Value);
        var stepId = (Guid)(await insert.ExecuteScalarAsync(ct))!;

        await using (var counts = new NpgsqlCommand(CountsSql, connection, tx))
        {
            counts.Parameters.AddWithValue("id", runId);
            await counts.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        var steps = await ReadStepsAsync(connection, runId, 0, stepId, ct);
        return ServiceResult<TestStepDto>.Created(steps[0]);
    }

    public async Task<ServiceResult<TestRunDto>> FinishRunAsync(Guid runId, FinishTestRunRequest request, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        await using (var counts = new NpgsqlCommand(CountsSql, connection))
        {
            counts.Parameters.AddWithValue("id", runId);
            await counts.ExecuteNonQueryAsync(ct);
        }

        var wanted = request.Status?.Trim();
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.test_runs
            SET status = CASE
                    WHEN @status IN ('Passed', 'Failed', 'Stopped') THEN @status
                    WHEN steps_failed > 0 THEN 'Failed'
                    ELSE 'Passed' END,
                finished_at = now()
            WHERE id = @id AND status = 'Running';
            """, connection);
        command.Parameters.AddWithValue("id", runId);
        command.Parameters.AddWithValue("status", wanted ?? string.Empty);
        await command.ExecuteNonQueryAsync(ct);

        var run = await ReadRunAsync(connection, runId, ct);
        return run is null
            ? ServiceResult<TestRunDto>.Fail(404, "run_not_found", "Test run nahi mila.")
            : ServiceResult<TestRunDto>.Ok(run);
    }

    // ---- Admin ------------------------------------------------------------------

    public async Task<ServiceResult<TestingOverviewDto>> OverviewAsync(int limit, CancellationToken ct)
    {
        limit = Math.Clamp(limit, 1, 100);
        await using var connection = await OpenAsync(ct);
        var runs = new List<TestRunDto>();
        await using (var command = new NpgsqlCommand($"{RunSelect} ORDER BY started_at DESC LIMIT @limit;", connection))
        {
            command.Parameters.AddWithValue("limit", limit);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) runs.Add(ReadRun(reader));
        }

        int open = 0, done = 0;
        await using (var command = new NpgsqlCommand(
            "SELECT status, count(*)::int FROM udrive.test_improvements GROUP BY status;", connection))
        {
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                var n = Convert.ToInt32(reader.GetValue(1));
                if (reader.GetString(0) == "Open") open = n; else done += n;
            }
        }

        bool configured;
        await using (var command = new NpgsqlCommand(
            "SELECT COALESCE(value_json #>> '{}', '') <> '' FROM udrive.system_settings WHERE key = @key;", connection))
        {
            command.Parameters.AddWithValue("key", KeySetting);
            configured = await command.ExecuteScalarAsync(ct) is true;
        }

        return ServiceResult<TestingOverviewDto>.Ok(new TestingOverviewDto(configured, runs, open, done));
    }

    /// <summary>The run and its steps after <paramref name="afterSeq"/> (0: all), for polling.</summary>
    public async Task<ServiceResult<TestRunDetailDto>> RunAsync(Guid runId, int afterSeq, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var run = await ReadRunAsync(connection, runId, ct);
        if (run is null) return ServiceResult<TestRunDetailDto>.Fail(404, "run_not_found", "Test run nahi mila.");
        var steps = await ReadStepsAsync(connection, runId, Math.Max(0, afterSeq), null, ct);
        return ServiceResult<TestRunDetailDto>.Ok(new TestRunDetailDto(run, steps));
    }

    public async Task<ServiceResult<IReadOnlyList<TestImprovementDto>>> ImprovementsAsync(string? status, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            SELECT i.id, i.run_id, i.step_id, i.suite, i.step_name, i.screenshot_url, i.note, i.status,
                   COALESCE(u.full_name, u.phone_number), i.created_at, i.done_at
            FROM udrive.test_improvements i
            LEFT JOIN udrive.users u ON u.id = i.created_by_user_id
            WHERE (@status = '' OR i.status = @status)
            ORDER BY (i.status = 'Open') DESC, i.created_at DESC
            LIMIT 300;
            """, connection);
        command.Parameters.AddWithValue("status", status is "Open" or "Done" ? status : string.Empty);
        var items = new List<TestImprovementDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            items.Add(new TestImprovementDto(
                reader.GetGuid(0),
                reader.IsDBNull(1) ? null : reader.GetGuid(1),
                reader.IsDBNull(2) ? null : reader.GetGuid(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetString(6),
                reader.GetString(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.GetFieldValue<DateTimeOffset>(9),
                reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10)));
        }

        return ServiceResult<IReadOnlyList<TestImprovementDto>>.Ok(items);
    }

    public async Task<ServiceResult<TestImprovementDto>> AddImprovementAsync(
        Guid adminId, TestImprovementRequest request, CancellationToken ct)
    {
        var note = Clip(request.Note, 2000);
        if (string.IsNullOrWhiteSpace(note))
            return ServiceResult<TestImprovementDto>.Fail(400, "note_required", "Improvement likhein.");

        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.test_improvements (run_id, step_id, suite, step_name, screenshot_url, note, created_by_user_id)
            SELECT COALESCE(s.run_id, r.id), s.id, r.suite, s.name, s.screenshot_url, @note, @admin
            FROM (SELECT 1) one
            LEFT JOIN udrive.test_steps s ON s.id = @step
            LEFT JOIN udrive.test_runs r ON r.id = COALESCE(s.run_id, @run)
            RETURNING id;
            """, connection);
        command.Parameters.AddWithValue("note", note);
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.Add(new NpgsqlParameter("step", NpgsqlTypes.NpgsqlDbType.Uuid) { Value = (object?)request.StepId ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("run", NpgsqlTypes.NpgsqlDbType.Uuid) { Value = (object?)request.RunId ?? DBNull.Value });
        var id = (Guid)(await command.ExecuteScalarAsync(ct))!;
        var list = await ImprovementsAsync(null, ct);
        return ServiceResult<TestImprovementDto>.Created(list.Data!.First(i => i.Id == id), "Improvement save ho gayi.");
    }

    public async Task<ServiceResult<bool>> SetImprovementStatusAsync(Guid id, string status, CancellationToken ct)
    {
        if (status is not ("Open" or "Done"))
            return ServiceResult<bool>.Fail(400, "invalid_status", "Status Open ya Done.");
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.test_improvements
            SET status = @status, done_at = CASE WHEN @status = 'Done' THEN now() ELSE NULL END
            WHERE id = @id;
            """, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("status", status);
        return await command.ExecuteNonQueryAsync(ct) == 1
            ? ServiceResult<bool>.Ok(true)
            : ServiceResult<bool>.Fail(404, "not_found", "Improvement nahi mili.");
    }

    public async Task<ServiceResult<bool>> DeleteImprovementAsync(Guid id, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand("DELETE FROM udrive.test_improvements WHERE id = @id;", connection);
        command.Parameters.AddWithValue("id", id);
        return await command.ExecuteNonQueryAsync(ct) == 1
            ? ServiceResult<bool>.Ok(true)
            : ServiceResult<bool>.Fail(404, "not_found", "Improvement nahi mili.");
    }

    /// <summary>A new reporter key. The old one stops working at once.</summary>
    public async Task<ServiceResult<TestKeyDto>> GenerateKeyAsync(CancellationToken ct)
    {
        var key = "udt_" + Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
            VALUES (@key, to_jsonb(@hash::text), 'SHA-256 of the key the automated tests send (X-Test-Key).', false, now(), now())
            ON CONFLICT (key) DO UPDATE SET value_json = EXCLUDED.value_json, updated_at = now();
            """, connection);
        command.Parameters.AddWithValue("key", KeySetting);
        command.Parameters.AddWithValue("hash", Hash(key));
        await command.ExecuteNonQueryAsync(ct);
        return ServiceResult<TestKeyDto>.Ok(new TestKeyDto(key),
            "Yeh key sirf abhi dikhegi. GitHub → Settings → Secrets mein TEST_REPORT_KEY naam se rakhein.");
    }

    // ---- Helpers ----------------------------------------------------------------

    private const string RunSelect =
        """
        SELECT id, suite, title, status, source, commit_sha, steps_total, steps_passed, steps_failed, started_at, finished_at
        FROM udrive.test_runs
        """;

    private const string CountsSql =
        """
        UPDATE udrive.test_runs r SET
            steps_total = c.total, steps_passed = c.passed, steps_failed = c.failed
        FROM (
            SELECT count(*) FILTER (WHERE status <> 'Info')::int AS total,
                   count(*) FILTER (WHERE status = 'Passed')::int AS passed,
                   count(*) FILTER (WHERE status = 'Failed')::int AS failed
            FROM udrive.test_steps WHERE run_id = @id
        ) c
        WHERE r.id = @id;
        """;

    private static async Task<TestRunDto?> ReadRunAsync(NpgsqlConnection connection, Guid id, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand($"{RunSelect} WHERE id = @id;", connection);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct) ? ReadRun(reader) : null;
    }

    private static TestRunDto ReadRun(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.IsDBNull(2) ? null : reader.GetString(2),
        reader.GetString(3),
        reader.IsDBNull(4) ? null : reader.GetString(4),
        reader.IsDBNull(5) ? null : reader.GetString(5),
        Convert.ToInt32(reader.GetValue(6)),
        Convert.ToInt32(reader.GetValue(7)),
        Convert.ToInt32(reader.GetValue(8)),
        reader.GetFieldValue<DateTimeOffset>(9),
        reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10));

    private static async Task<List<TestStepDto>> ReadStepsAsync(
        NpgsqlConnection connection, Guid runId, int afterSeq, Guid? onlyId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT id, seq, name, status, detail, device, screenshot_url, created_at
            FROM udrive.test_steps
            WHERE run_id = @run AND seq > @after AND (@only::uuid IS NULL OR id = @only::uuid)
            ORDER BY seq
            LIMIT 500;
            """, connection);
        command.Parameters.AddWithValue("run", runId);
        command.Parameters.AddWithValue("after", afterSeq);
        command.Parameters.Add(new NpgsqlParameter("only", NpgsqlTypes.NpgsqlDbType.Uuid) { Value = (object?)onlyId ?? DBNull.Value });
        var steps = new List<TestStepDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            steps.Add(new TestStepDto(
                reader.GetGuid(0),
                Convert.ToInt32(reader.GetValue(1)),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetFieldValue<DateTimeOffset>(7)));
        }

        return steps;
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }

    private static string Hash(string key) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();

    private static string? Clip(string? value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var trimmed = value.Trim();
        return trimmed.Length <= max ? trimmed : trimmed[..max];
    }
}
