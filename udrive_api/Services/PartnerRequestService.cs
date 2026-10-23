using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

/// <summary>
/// "Become a partner" from the website: the request, the conversation with
/// the UDrive team, and the admin side.
/// </summary>
/// <remarks>
/// A request is only a first contact. The agreement, fee and onboarding stay
/// physical, as before; nothing here takes money.
///
/// The applicant is a signed-in customer (WhatsApp OTP), so the phone number
/// is the verified one and one person has at most one open request. Team
/// replies can go out on WhatsApp through the outbox; internal notes are
/// never shown to the applicant.
/// </remarks>
public sealed partial class PartnerRequestService(string connectionString)
{
    public static readonly string[] Budgets = ["1M", "2M", "3M", "4M+"];
    public static readonly string[] Statuses = ["New", "Contacted", "Meeting", "Approved", "Declined", "Closed"];
    private static readonly string[] Open = ["New", "Contacted", "Meeting", "Approved"];

    [GeneratedRegex(@"^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$")]
    private static partial Regex EmailPattern();

    // ────────────────────────────────────────────────────────── applicant

    public async Task<ServiceResult<PartnerRequestDto>> SubmitAsync(Guid userId, SubmitPartnerRequest x, CancellationToken ct)
    {
        var name = Text(x.FullName, 80);
        var current = Text(x.CurrentCity, 60);
        var target = Text(x.TargetCity, 60);
        var work = Text(x.Work, 120);
        var message = Text(x.Message, 1000);
        var email = Text(x.Email, 160);
        var budget = (x.Budget ?? "").Trim().ToUpperInvariant();

        if (name.Length < 3) return Fail<PartnerRequestDto>(400, "name_required", "Apna poora naam likhein.");
        if (current.Length < 2) return Fail<PartnerRequestDto>(400, "city_required", "Aap ka shehar likhein.");
        if (target.Length < 2) return Fail<PartnerRequestDto>(400, "target_required", "Kis city mein partnership chahiye, chunein.");
        if (!Budgets.Contains(budget)) return Fail<PartnerRequestDto>(400, "budget_invalid", "Budget chunein: 1M, 2M, 3M ya 4M+.");
        if (email.Length > 0 && !EmailPattern().IsMatch(email)) return Fail<PartnerRequestDto>(400, "email_invalid", "Email sahi nahi lagti.");
        foreach (var t in new[] { name, current, target, work, message, email })
        {
            if (RejectMarkupAttribute.IsUnsafe(t)) return Fail<PartnerRequestDto>(400, "text_not_allowed", "< aur > jaise nishan allowed nahi.");
        }

        await using var c = await OpenAsync(ct);
        string phone;
        await using (var cmd = new NpgsqlCommand("SELECT phone_number FROM udrive.users WHERE id = @u;", c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            phone = (await cmd.ExecuteScalarAsync(ct))?.ToString() ?? "";
        }
        if (phone.Length == 0) return Fail<PartnerRequestDto>(401, "account_unavailable", "Dobara login karein.");

        await using (var cmd = new NpgsqlCommand(
            "SELECT count(*)::int FROM udrive.partner_requests WHERE user_id = @u AND status = ANY(@open);", c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            cmd.Parameters.AddWithValue("open", Open);
            var open = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
            if (open > 0)
            {
                return Fail<PartnerRequestDto>(409, "request_open",
                    "Aap ki aik request pehle se chal rahi hai. Usi par message karein — My partnership request.");
            }
        }

        var reference = $"UDP-{DateTime.UtcNow.AddHours(5):yyMM}-{Random.Shared.Next(1000, 9999)}{Random.Shared.Next(0, 9)}";
        Guid id;
        await using var tx = await c.BeginTransactionAsync(ct);
        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.partner_requests (reference, user_id, full_name, phone, email, current_city, target_city, work, budget)
            VALUES (@ref, @u, @name, @phone, @email, @current, @target, @work, @budget)
            RETURNING id;
            """, c, tx))
        {
            cmd.Parameters.AddWithValue("ref", reference);
            cmd.Parameters.AddWithValue("u", userId);
            cmd.Parameters.AddWithValue("name", name);
            cmd.Parameters.AddWithValue("phone", phone);
            cmd.Parameters.Add(NullText("email", email));
            cmd.Parameters.AddWithValue("current", current);
            cmd.Parameters.AddWithValue("target", target);
            cmd.Parameters.Add(NullText("work", work));
            cmd.Parameters.AddWithValue("budget", budget);
            id = (Guid)(await cmd.ExecuteScalarAsync(ct))!;
        }

        if (message.Length > 0) await AddMessageAsync(c, tx, id, "Applicant", message, false, userId, ct);
        await tx.CommitAsync(ct);

        return ServiceResult<PartnerRequestDto>.Created((await MineAsync(c, userId, id, ct))!,
            "Shukriya! Request mil gayi. UDrive ki team WhatsApp par rabta karegi.");
    }

    public async Task<ServiceResult<IReadOnlyList<PartnerRequestDto>>> MineAsync(Guid userId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var ids = new List<Guid>();
        await using (var cmd = new NpgsqlCommand(
            "SELECT id FROM udrive.partner_requests WHERE user_id = @u ORDER BY created_at DESC LIMIT 10;", c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) ids.Add(r.GetGuid(0));
        }

        var list = new List<PartnerRequestDto>();
        foreach (var id in ids)
        {
            if (await MineAsync(c, userId, id, ct) is { } dto) list.Add(dto);
        }
        return ServiceResult<IReadOnlyList<PartnerRequestDto>>.Ok(list);
    }

    public async Task<ServiceResult<PartnerRequestDto>> ApplicantReplyAsync(Guid userId, Guid requestId, PartnerMessageRequest x, CancellationToken ct)
    {
        var body = Text(x.Body, 1000);
        if (body.Length < 1) return Fail<PartnerRequestDto>(400, "message_required", "Message likhein.");
        if (RejectMarkupAttribute.IsUnsafe(body)) return Fail<PartnerRequestDto>(400, "text_not_allowed", "< aur > jaise nishan allowed nahi.");

        await using var c = await OpenAsync(ct);
        await using (var cmd = new NpgsqlCommand(
            "SELECT status FROM udrive.partner_requests WHERE id = @id AND user_id = @u;", c))
        {
            cmd.Parameters.AddWithValue("id", requestId);
            cmd.Parameters.AddWithValue("u", userId);
            var status = (await cmd.ExecuteScalarAsync(ct))?.ToString();
            if (status is null) return Fail<PartnerRequestDto>(404, "request_not_found", "Request nahi mili.");
            if (status is "Closed" or "Declined") return Fail<PartnerRequestDto>(409, "request_closed", "Yeh request band ho chuki hai.");
        }

        // A burst of messages from one applicant is noise, not a conversation.
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT count(*)::int FROM udrive.partner_request_messages
             WHERE request_id = @id AND author = 'Applicant' AND created_at > now() - interval '1 hour';
            """, c))
        {
            cmd.Parameters.AddWithValue("id", requestId);
            if (Convert.ToInt32(await cmd.ExecuteScalarAsync(ct)) >= 10)
            {
                return Fail<PartnerRequestDto>(429, "too_many_messages", "Bohot zyada messages. Thori der baad likhein.");
            }
        }

        await AddMessageAsync(c, null, requestId, "Applicant", body, false, userId, ct);
        await Touch(c, requestId, ct);
        return ServiceResult<PartnerRequestDto>.Ok((await MineAsync(c, userId, requestId, ct))!, "Message bhej diya.");
    }

    // ────────────────────────────────────────────────────────────── admin

    public async Task<ServiceResult<AdminPartnerListDto>> AdminListAsync(string? status, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var rows = new List<AdminPartnerRowDto>();
        var filter = Statuses.Contains(status ?? "") ? status! : "";
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT p.id, p.reference, p.full_name, p.phone, p.target_city, p.budget, p.status,
                   (SELECT count(*)::int FROM udrive.partner_request_messages m
                     WHERE m.request_id = p.id AND m.author = 'Applicant'
                       AND m.created_at > COALESCE((SELECT max(t.created_at) FROM udrive.partner_request_messages t
                                                     WHERE t.request_id = p.id AND t.author IN ('Team', 'Note')), 'epoch')),
                   p.created_at, p.updated_at
              FROM udrive.partner_requests p
             WHERE (@status = '' OR p.status = @status)
             ORDER BY (p.status = 'New') DESC, p.updated_at DESC
             LIMIT 300;
            """, c))
        {
            cmd.Parameters.AddWithValue("status", filter);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                rows.Add(new AdminPartnerRowDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4),
                    r.GetString(5), r.GetString(6), r.GetInt32(7), r.GetFieldValue<DateTimeOffset>(8), r.GetFieldValue<DateTimeOffset>(9)));
            }
        }

        var counts = Statuses.ToDictionary(s => s, _ => 0);
        await using (var cmd = new NpgsqlCommand("SELECT status, count(*)::int FROM udrive.partner_requests GROUP BY status;", c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct)) counts[r.GetString(0)] = r.GetInt32(1);
        }

        return ServiceResult<AdminPartnerListDto>.Ok(new AdminPartnerListDto(rows, counts));
    }

    public async Task<ServiceResult<AdminPartnerDetailDto>> AdminGetAsync(Guid id, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var detail = await AdminDetailAsync(c, id, ct);
        return detail is null ? Fail<AdminPartnerDetailDto>(404, "request_not_found", "Request not found.") : ServiceResult<AdminPartnerDetailDto>.Ok(detail);
    }

    public async Task<ServiceResult<AdminPartnerDetailDto>> AdminStatusAsync(Guid adminId, Guid id, PartnerRequestStatusRequest x, CancellationToken ct)
    {
        var status = Statuses.FirstOrDefault(s => s.Equals((x.Status ?? "").Trim(), StringComparison.OrdinalIgnoreCase));
        if (status is null) return Fail<AdminPartnerDetailDto>(400, "status_invalid", "Status: " + string.Join(", ", Statuses));

        await using var c = await OpenAsync(ct);
        await using (var cmd = new NpgsqlCommand(
            "UPDATE udrive.partner_requests SET status = @s, updated_at = now() WHERE id = @id;", c))
        {
            cmd.Parameters.AddWithValue("s", status);
            cmd.Parameters.AddWithValue("id", id);
            if (await cmd.ExecuteNonQueryAsync(ct) == 0) return Fail<AdminPartnerDetailDto>(404, "request_not_found", "Request not found.");
        }

        await Audit(c, adminId, "PartnerRequestStatus", id, status, ct);
        return ServiceResult<AdminPartnerDetailDto>.Ok((await AdminDetailAsync(c, id, ct))!, "Status saved.");
    }

    public async Task<ServiceResult<AdminPartnerDetailDto>> AdminReplyAsync(Guid adminId, Guid id, AdminPartnerReplyRequest x, CancellationToken ct)
    {
        var body = Text(x.Body, 1000);
        if (body.Length < 1) return Fail<AdminPartnerDetailDto>(400, "message_required", "Write a message.");
        if (RejectMarkupAttribute.IsUnsafe(body)) return Fail<AdminPartnerDetailDto>(400, "text_not_allowed", "< and > are not allowed.");

        await using var c = await OpenAsync(ct);
        string? phone = null;
        string name = "";
        string reference = "";
        await using (var cmd = new NpgsqlCommand("SELECT phone, full_name, reference FROM udrive.partner_requests WHERE id = @id;", c))
        {
            cmd.Parameters.AddWithValue("id", id);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (await r.ReadAsync(ct))
            {
                phone = r.GetString(0);
                name = r.GetString(1);
                reference = r.GetString(2);
            }
        }
        if (phone is null) return Fail<AdminPartnerDetailDto>(404, "request_not_found", "Request not found.");

        var note = x.InternalNote;
        var whatsapp = !note && x.SendWhatsApp;
        await using var tx = await c.BeginTransactionAsync(ct);
        await AddMessageAsync(c, tx, id, note ? "Note" : "Team", body, whatsapp, adminId, ct);

        if (whatsapp)
        {
            var first = name.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
            var text = $"UDrive partnership ({reference})\n\nAssalam o Alaikum {first},\n{body}\n\nJawab dene ke liye UDrive website par login karein: My partnership request.";
            await using var outbox = new NpgsqlCommand(
                "INSERT INTO udrive.whatsapp_outbox (template_key, to_phone, body) VALUES ('partner_reply', @to, @body);", c, tx);
            outbox.Parameters.AddWithValue("to", phone);
            outbox.Parameters.AddWithValue("body", text);
            await outbox.ExecuteNonQueryAsync(ct);
        }

        if (!note)
        {
            // The first team reply moves a new request on, so the list shows who is waiting.
            await using var st = new NpgsqlCommand(
                "UPDATE udrive.partner_requests SET status = CASE WHEN status = 'New' THEN 'Contacted' ELSE status END, updated_at = now() WHERE id = @id;", c, tx);
            st.Parameters.AddWithValue("id", id);
            await st.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        await Audit(c, adminId, note ? "PartnerRequestNote" : "PartnerRequestReply", id, whatsapp ? "whatsapp" : "web", ct);
        return ServiceResult<AdminPartnerDetailDto>.Ok((await AdminDetailAsync(c, id, ct))!, note ? "Note saved." : whatsapp ? "Reply sent (WhatsApp too)." : "Reply sent.");
    }

    // ──────────────────────────────────────────────────────────── helpers

    private static async Task<PartnerRequestDto?> MineAsync(NpgsqlConnection c, Guid userId, Guid id, CancellationToken ct)
    {
        PartnerRequestDto? dto = null;
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT id, reference, full_name, current_city, target_city, budget, status, created_at
              FROM udrive.partner_requests WHERE id = @id AND user_id = @u;
            """, c))
        {
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("u", userId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (await r.ReadAsync(ct))
            {
                dto = new PartnerRequestDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4),
                    r.GetString(5), r.GetString(6), r.GetFieldValue<DateTimeOffset>(7), []);
            }
        }
        if (dto is null) return null;
        return dto with { Messages = await MessagesAsync(c, id, includeNotes: false, ct) };
    }

    private static async Task<AdminPartnerDetailDto?> AdminDetailAsync(NpgsqlConnection c, Guid id, CancellationToken ct)
    {
        AdminPartnerDetailDto? dto = null;
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT id, reference, full_name, phone, email, current_city, target_city, work, budget, status, created_at
              FROM udrive.partner_requests WHERE id = @id;
            """, c))
        {
            cmd.Parameters.AddWithValue("id", id);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (await r.ReadAsync(ct))
            {
                dto = new AdminPartnerDetailDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3),
                    r.IsDBNull(4) ? null : r.GetString(4), r.GetString(5), r.GetString(6), r.IsDBNull(7) ? null : r.GetString(7),
                    r.GetString(8), r.GetString(9), r.GetFieldValue<DateTimeOffset>(10), []);
            }
        }
        if (dto is null) return null;
        return dto with { Messages = await MessagesAsync(c, id, includeNotes: true, ct) };
    }

    private static async Task<IReadOnlyList<PartnerMessageDto>> MessagesAsync(NpgsqlConnection c, Guid id, bool includeNotes, CancellationToken ct)
    {
        var list = new List<PartnerMessageDto>();
        await using var cmd = new NpgsqlCommand(
            """
            SELECT id, author, body, whatsapp_sent, created_at FROM udrive.partner_request_messages
             WHERE request_id = @id AND (@notes OR author <> 'Note')
             ORDER BY created_at LIMIT 200;
            """, c);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("notes", includeNotes);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            list.Add(new PartnerMessageDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetBoolean(3), r.GetFieldValue<DateTimeOffset>(4)));
        }
        return list;
    }

    private static async Task AddMessageAsync(NpgsqlConnection c, NpgsqlTransaction? tx, Guid requestId, string author, string body,
        bool whatsapp, Guid userId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.partner_request_messages (request_id, author, body, whatsapp_sent, created_by)
            VALUES (@r, @a, @b, @w, @u);
            """, c, tx);
        cmd.Parameters.AddWithValue("r", requestId);
        cmd.Parameters.AddWithValue("a", author);
        cmd.Parameters.AddWithValue("b", body);
        cmd.Parameters.AddWithValue("w", whatsapp);
        cmd.Parameters.AddWithValue("u", userId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task Touch(NpgsqlConnection c, Guid id, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("UPDATE udrive.partner_requests SET updated_at = now() WHERE id = @id;", c);
        cmd.Parameters.AddWithValue("id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task Audit(NpgsqlConnection c, Guid adminId, string action, Guid id, string detail, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @a, @action, 'PartnerRequest', @id, jsonb_build_object('detail', @d), now(), now());
            """, c);
        cmd.Parameters.AddWithValue("a", adminId);
        cmd.Parameters.AddWithValue("action", action);
        cmd.Parameters.AddWithValue("id", id.ToString());
        cmd.Parameters.AddWithValue("d", detail);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static NpgsqlParameter NullText(string name, string value) =>
        new(name, NpgsqlTypes.NpgsqlDbType.Text) { Value = value.Length == 0 ? DBNull.Value : value };

    /// <summary>Trim, drop control characters, collapse runs of spaces, cap the length.</summary>
    internal static string Text(string? value, int max)
    {
        var clean = WebsiteService.Clean(value, max * 2) ?? "";
        clean = Regex.Replace(clean, @"[ \t]{2,}", " ");
        return clean.Length > max ? clean[..max].Trim() : clean;
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        return c;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) => ServiceResult<T>.Fail(status, code, message);
}
