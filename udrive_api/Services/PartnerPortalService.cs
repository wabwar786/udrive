using System.Globalization;
using System.Text.Json;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The partner's own portal: their contract, their commitments, their monthly
/// statements — and the one place a contract can be signed.
/// </summary>
/// <remarks>
/// <b>Every method here takes the user id from the token and finds the partner
/// from it.</b> Not one of them accepts a partner id, a contract id or a
/// territory id from the caller. That is the whole security model of the partner
/// portal, and it is deliberately not a permission check that could be forgotten
/// on a new method: there is no identifier to tamper with, so a partner cannot
/// reach another partner's contract by editing a URL. Hiding the other partners
/// in the interface would have been the usual mistake.
///
/// <para>The figures come from <see cref="AdminPartnerService"/>'s loaders and
/// <see cref="PartnerMetricsService"/> — the same SQL the admin screens use. A
/// partner and an admin looking at the same month see the same number because
/// there is only one query, not because somebody kept two in step.</para>
/// </remarks>
public sealed class PartnerPortalService(
    string connectionString,
    LocalFileStorageService storage)
{
    private NpgsqlConnection Open() => new(connectionString);

    /// <summary>Resolves the signed-in user to their partner row, or nothing.</summary>
    private static async Task<(Guid PartnerId, Guid TerritoryId, string TerritoryKind, string Status)?>
        ResolveAsync(NpgsqlConnection connection, Guid userId, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT p.id, p.territory_id, t.kind, p.status
            FROM udrive.partners p
            JOIN udrive.territories t ON t.id = p.territory_id
            WHERE p.user_id = @user
              AND p.status IN ('Pending', 'Active', 'Suspended')
            ORDER BY p.created_at DESC
            LIMIT 1;
            """,
            connection);
        command.Parameters.AddWithValue("user", userId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? (reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2), reader.GetString(3))
            : null;
    }

    public async Task<ServiceResult<PartnerPortalDto>> DashboardAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var resolved = await ResolveAsync(connection, userId, cancellationToken);
        if (resolved is null)
        {
            // 403 rather than 404: the account exists and is signed in correctly,
            // it simply is not a partner. A 404 here sends the portal's error
            // handler down the "this record is missing" path, which is wrong and
            // unhelpful.
            return ServiceResult<PartnerPortalDto>.Fail(
                StatusCodes.Status403Forbidden, "not_a_partner",
                "This account is not a UDrive partner.");
        }

        var (partnerId, territoryId, territoryKind, _) = resolved.Value;

        var partners = await AdminPartnerService.LoadPartnersAsync(
            connection, partnerId, null, cancellationToken);
        if (partners.Count == 0)
        {
            return ServiceResult<PartnerPortalDto>.Fail(
                StatusCodes.Status403Forbidden, "not_a_partner",
                "This account is not a UDrive partner.");
        }

        var partner = partners[0];

        var contract = partner.ContractId is null
            ? null
            : await AdminPartnerService.LoadContractAsync(
                connection, partner.ContractId.Value, cancellationToken);

        if (contract is { Status: "Signed" })
        {
            await PartnerMetricsService.RecomputeAsync(connection, contract.Id, cancellationToken);
        }

        var commitments = contract is null
            ? Array.Empty<PartnerCommitmentDto>()
            : await AdminPartnerService.LoadCommitmentsAsync(
                connection, contract.Id, territoryId, territoryKind, cancellationToken);

        var periods = contract is null
            ? Array.Empty<PartnerPeriodDto>()
            : await AdminPartnerService.LoadPeriodsAsync(connection, contract.Id, 6, cancellationToken);

        var statements = contract is null
            ? Array.Empty<PartnerStatementDto>()
            : await AdminPartnerService.LoadStatementsAsync(connection, contract.Id, 12, cancellationToken);

        var snapshot = await PartnerMetricsService.SnapshotAsync(
            connection, territoryId, PartnerMetricsService.MonthStart(DateTimeOffset.UtcNow),
            cancellationToken);

        var shareThisMonth = statements
            .Where(s => s.PeriodStart == PartnerMetricsService.MonthStart(DateTimeOffset.UtcNow))
            .Select(s => s.ShareAmount)
            .FirstOrDefault();

        // Owed means closed and not yet paid. An Open month is not owed — it is
        // still running, and showing it as owed is how a partner comes to believe
        // they are short-paid every single month.
        var owed = statements.Where(s => s.Status == "Closed").Sum(s => s.ShareAmount);
        var paid = statements.Where(s => s.Status == "Paid").Sum(s => s.ShareAmount);

        return ServiceResult<PartnerPortalDto>.Ok(new PartnerPortalDto(
            partner.FullName,
            partner.PhoneNumber,
            partner.TierName,
            partner.TerritoryName,
            partner.TerritoryKind,
            partner.Status,
            contract,
            commitments,
            periods,
            statements,
            new PartnerPortalTotalsDto(
                snapshot.DriversTotal,
                snapshot.NewDrivers,
                snapshot.ActiveDrivers,
                snapshot.CompletedRides,
                snapshot.CommissionBase,
                shareThisMonth,
                owed,
                paid),
            AdminPartnerService.PayoutSentence));
    }

    /// <summary>
    /// Signs the contract: the live photograph, the video of the fixed words, and
    /// the facts only the server can vouch for.
    /// </summary>
    /// <remarks>
    /// One transaction, and it either produces a signed contract with its evidence
    /// or changes nothing. A signed contract with no evidence row is the state this
    /// whole feature exists to prevent.
    ///
    /// <para>What the server supplies, and the client is never asked for:</para>
    /// <list type="bullet">
    /// <item><b>The time.</b> From the database's own clock. A phone's clock is
    /// whatever its owner set it to — the same lesson the rental cancellation
    /// window taught.</item>
    /// <item><b>The phone number.</b> From the <c>users</c> row behind the token,
    /// which OTP has already proven.</item>
    /// <item><b>The IP.</b> From the request.</item>
    /// <item><b>The words shown.</b> Copied from the contract, not from the
    /// request, so the stored script is provably the one on screen rather than
    /// whatever the client claims it displayed.</item>
    /// </list>
    /// </remarks>
    public async Task<ServiceResult<object>> SignAsync(
        Guid userId,
        IFormFile? selfie,
        IFormFile? video,
        string? deviceInfo,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        if (selfie is null || video is null)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "both_required",
                "Both the photograph and the video are needed to sign.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var resolved = await ResolveAsync(connection, userId, cancellationToken);
        if (resolved is null)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status403Forbidden, "not_a_partner",
                "This account is not a UDrive partner.");
        }

        var partnerId = resolved.Value.PartnerId;

        // The contract waiting to be signed, and the words it carries. Loaded
        // before anything is written to disk, so a partner with nothing to sign
        // is told so rather than having a video stored for no reason.
        Guid contractId;
        string reference, script;
        int termMonths;

        await using (var load = new NpgsqlCommand(
            """
            SELECT c.id, c.reference, c.video_script, c.term_months
            FROM udrive.partner_contracts c
            WHERE c.partner_id = @partner AND c.status = 'Sent'
            LIMIT 1;
            """,
            connection))
        {
            load.Parameters.AddWithValue("partner", partnerId);
            await using var reader = await load.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status409Conflict, "nothing_to_sign",
                    "There is no contract waiting for your signature right now.");
            }

            contractId = reader.GetGuid(0);
            reference = reader.GetString(1);
            script = reader.GetString(2);
            termMonths = reader.GetInt32(3);
        }

        StoredFile selfieFile, videoFile;
        try
        {
            selfieFile = await storage.SaveSignatureEvidenceAsync(
                selfie, contractId, "selfie", cancellationToken);
            videoFile = await storage.SaveSignatureEvidenceAsync(
                video, contractId, "video", cancellationToken);
        }
        catch (InvalidDataException error)
        {
            // The storage service's messages are written for the person holding
            // the phone, so they are passed through rather than replaced.
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "file_rejected", error.Message);
        }
        catch (InvalidOperationException error)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status503ServiceUnavailable, "storage_unavailable", error.Message);
        }

        // The date the words were read, filled now rather than when the contract
        // was written — the placeholder was left in for exactly this moment.
        var signedScript = script.Replace(
            "{{sign_date}}",
            DateTime.UtcNow.ToString("d MMMM yyyy", CultureInfo.InvariantCulture));

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            // Guarded again inside the transaction, on status. Two taps on a slow
            // connection would otherwise produce two evidence rows and two
            // signatures for one contract — the unique index on contract_id makes
            // the second fail, and this makes it fail politely.
            await using (var sign = new NpgsqlCommand(
                """
                UPDATE udrive.partner_contracts
                   SET status = 'Signed',
                       signed_at = now(),
                       starts_at = now(),
                       ends_at = now() + (@term || ' months')::interval,
                       video_script = @script,
                       updated_at = now()
                 WHERE id = @id AND status = 'Sent';
                """,
                connection,
                transaction))
            {
                sign.Parameters.AddWithValue("id", contractId);
                sign.Parameters.AddWithValue("term", termMonths.ToString(CultureInfo.InvariantCulture));
                sign.Parameters.AddWithValue("script", signedScript);

                if (await sign.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    storage.DeleteSignatureEvidence(selfieFile.RelativeUrl);
                    storage.DeleteSignatureEvidence(videoFile.RelativeUrl);
                    return ServiceResult<object>.Fail(
                        StatusCodes.Status409Conflict, "already_signed",
                        "This contract has already been signed.");
                }
            }

            // `purge_after` is set here, from the contract's own end date plus a
            // year. Nothing deletes it automatically — a SuperAdmin presses the
            // button — but the date is written down rather than left to memory,
            // which is the difference between a retention policy and an intention.
            await using (var evidence = new NpgsqlCommand(
                """
                INSERT INTO udrive.partner_signature_evidence
                    (contract_id, selfie_url, video_url, phone_number,
                     signed_at_server, ip_address, device_info, script_shown,
                     purge_after)
                SELECT @contract, @selfie, @video, u.phone_number, now(), @ip,
                       nullif(btrim(@device), ''), @script,
                       (c.ends_at + interval '1 year')::date
                FROM udrive.partner_contracts c
                JOIN udrive.partners p ON p.id = c.partner_id
                JOIN udrive.users u ON u.id = p.user_id
                WHERE c.id = @contract;
                """,
                connection,
                transaction))
            {
                evidence.Parameters.AddWithValue("contract", contractId);
                evidence.Parameters.AddWithValue("selfie", selfieFile.RelativeUrl);
                evidence.Parameters.AddWithValue("video", videoFile.RelativeUrl);
                evidence.Parameters.AddWithValue("ip", (object?)ipAddress ?? DBNull.Value);
                evidence.Parameters.AddWithValue("device", (object?)deviceInfo ?? string.Empty);
                evidence.Parameters.AddWithValue("script", signedScript);
                await evidence.ExecuteNonQueryAsync(cancellationToken);
            }

            // The partner becomes Active here and nowhere else. This is the line
            // that hands over an exclusive territory, and it sits immediately
            // after the evidence insert on purpose.
            await using (var activate = new NpgsqlCommand(
                """
                UPDATE udrive.partners
                   SET status = 'Active', started_at = coalesce(started_at, now()),
                       updated_at = now()
                 WHERE id = @partner AND status = 'Pending';
                """,
                connection,
                transaction))
            {
                activate.Parameters.AddWithValue("partner", partnerId);
                await activate.ExecuteNonQueryAsync(cancellationToken);
            }

            await using (var audit = new NpgsqlCommand(
                """
                INSERT INTO udrive.audit_logs
                    (id, actor_user_id, action, entity_type, entity_id,
                     changes_json, created_at, updated_at)
                VALUES (gen_random_uuid(), @actor, 'PartnerContractSigned',
                        'PartnerContract', @entity, cast(@changes as jsonb),
                        now(), now());
                """,
                connection,
                transaction))
            {
                audit.Parameters.AddWithValue("actor", userId);
                audit.Parameters.AddWithValue("entity", contractId.ToString());
                audit.Parameters.AddWithValue(
                    "changes",
                    JsonSerializer.Serialize(new { reference, ipAddress, deviceInfo }));
                await audit.ExecuteNonQueryAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);

            // The files were written before the transaction, so a rollback has to
            // clean them up by hand. Left behind, they are a photograph and a
            // video of somebody on a server with no row pointing at them and no
            // purge date — the worst possible outcome for personal data.
            storage.DeleteSignatureEvidence(selfieFile.RelativeUrl);
            storage.DeleteSignatureEvidence(videoFile.RelativeUrl);
            throw;
        }

        // The open months are built straight away, so the portal has something to
        // show the moment the partner lands back on it.
        await PartnerMetricsService.RecomputeAsync(connection, contractId, cancellationToken);

        return ServiceResult<object>.Ok(
            new { contractId, reference, status = "Signed" },
            "Signed. Your territory is now yours.");
    }

    /// <summary>The contract text and the words to read, for the sign screen.</summary>
    public async Task<ServiceResult<PartnerContractDto>> ContractAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var resolved = await ResolveAsync(connection, userId, cancellationToken);
        if (resolved is null)
        {
            return ServiceResult<PartnerContractDto>.Fail(
                StatusCodes.Status403Forbidden, "not_a_partner",
                "This account is not a UDrive partner.");
        }

        await using var command = new NpgsqlCommand(
            """
            SELECT id FROM udrive.partner_contracts
            WHERE partner_id = @partner AND status <> 'Terminated'
            ORDER BY created_at DESC LIMIT 1;
            """,
            connection);
        command.Parameters.AddWithValue("partner", resolved.Value.PartnerId);

        if (await command.ExecuteScalarAsync(cancellationToken) is not Guid contractId)
        {
            return ServiceResult<PartnerContractDto>.Fail(
                StatusCodes.Status404NotFound, "no_contract",
                "Your contract is being prepared. We will tell you when it is ready.");
        }

        var contract = await AdminPartnerService.LoadContractAsync(
            connection, contractId, cancellationToken);

        // A Draft is not shown. It is being written, and the figures in it are
        // still being argued about internally.
        return contract is null || contract.Status == "Draft"
            ? ServiceResult<PartnerContractDto>.Fail(
                StatusCodes.Status404NotFound, "no_contract",
                "Your contract is being prepared. We will tell you when it is ready.")
            : ServiceResult<PartnerContractDto>.Ok(contract);
    }
}
