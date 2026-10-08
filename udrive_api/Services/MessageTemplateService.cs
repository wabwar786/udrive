using Microsoft.AspNetCore.Http;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>Setup → WhatsApp messages: the text of every message, and on/off.</summary>
public sealed class MessageTemplateService(string connectionString)
{
    public async Task<ServiceResult<IReadOnlyList<MessageTemplateDto>>> ListAsync(CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return ServiceResult<IReadOnlyList<MessageTemplateDto>>.Ok(await ReadAsync(connection, null, ct));
    }

    public async Task<ServiceResult<MessageTemplateDto>> UpdateAsync(
        Guid adminId, string key, UpdateMessageTemplateRequest request, CancellationToken ct)
    {
        var body = request.Body.Replace("\r\n", "\n").Trim();
        if (body.Length == 0 || body.Length > 1000)
        {
            return ServiceResult<MessageTemplateDto>.Fail(
                StatusCodes.Status400BadRequest, "body_invalid", "Message 1 se 1000 characters ka hona chahiye.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        var current = (await ReadAsync(connection, key, ct)).FirstOrDefault();
        if (current is null)
        {
            return ServiceResult<MessageTemplateDto>.Fail(
                StatusCodes.Status404NotFound, "template_not_found", "Yeh message nahi mila.");
        }

        // A misspelt {placeholder} would go out to customers as "—"; say so instead.
        var unknown = WhatsAppOutbox.PlaceholdersIn(body).Except(current.Placeholders).ToList();
        if (unknown.Count > 0)
        {
            return ServiceResult<MessageTemplateDto>.Fail(
                StatusCodes.Status400BadRequest, "placeholder_unknown",
                "Yeh {} is message mein nahi chalte: " + string.Join(", ", unknown.Select(u => "{" + u + "}"))
                + ". Sirf neeche diye gaye {} use karein.");
        }

        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.message_templates
            SET body = @body, is_active = @active, updated_at = now(), updated_by = @admin
            WHERE key = @key;

            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @admin, 'MessageTemplateUpdated', 'MessageTemplate', @key,
                    jsonb_build_object('isActive', @active), now(), now());
            """, connection))
        {
            command.Parameters.AddWithValue("key", key);
            command.Parameters.AddWithValue("body", body);
            command.Parameters.AddWithValue("active", request.IsActive);
            command.Parameters.AddWithValue("admin", adminId);
            await command.ExecuteNonQueryAsync(ct);
        }

        var saved = (await ReadAsync(connection, key, ct)).First();
        return ServiceResult<MessageTemplateDto>.Ok(saved, saved.IsActive ? "Message save ho gaya." : "Message save ho gaya — band hai, nahi jayega.");
    }

    private static async Task<IReadOnlyList<MessageTemplateDto>> ReadAsync(
        NpgsqlConnection connection, string? key, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT t.key, t.title, t.audience, t.description, t.placeholders, t.body, t.default_body,
                   t.is_active, t.updated_at,
                   (SELECT count(*)::int FROM udrive.whatsapp_outbox o
                     WHERE o.template_key = t.key AND o.status = 'Sent' AND o.created_at > now() - interval '7 days'),
                   (SELECT count(*)::int FROM udrive.whatsapp_outbox o
                     WHERE o.template_key = t.key AND o.status = 'Failed' AND o.created_at > now() - interval '7 days')
            FROM udrive.message_templates t
            WHERE (@key::text IS NULL OR t.key = @key::text)
            ORDER BY t.sort_order, t.key;
            """, connection);
        command.Parameters.Add(new NpgsqlParameter("key", NpgsqlTypes.NpgsqlDbType.Text) { Value = (object?)key ?? DBNull.Value });
        var list = new List<MessageTemplateDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new MessageTemplateDto(
                reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetFieldValue<string[]>(4), reader.GetString(5), reader.GetString(6),
                reader.GetBoolean(7), reader.GetFieldValue<DateTimeOffset>(8),
                reader.GetInt32(9), reader.GetInt32(10)));
        }

        return list;
    }
}
