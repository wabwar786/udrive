using Microsoft.AspNetCore.Mvc;
using Npgsql;
using System.Text.Json;
using UDrive.Api.Common;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Exposes the subset of <c>udrive.system_settings</c> that is marked
/// <c>is_public</c>, so mobile clients can read admin-controlled values such as
/// the Home hero artwork without authenticating.
/// </summary>
/// <remarks>
/// Only rows with <c>is_public = true</c> are ever returned. Operational
/// settings stay private; an admin has to explicitly publish a key before it
/// leaves the server. This is what lets the Home hero images be changed from
/// the admin portal without shipping a new app build.
/// </remarks>
[ApiController]
[Route("api/v1/settings")]
public sealed class PublicSettingsController(IConfiguration configuration) : ControllerBase
{
    // Same resolution the rest of the API uses, so Railway's DATABASE_URL and
    // a local connection string both work without special-casing here.
    private string ConnectionString => ConnectionStringFactory.Resolve(configuration);

    [HttpGet("public")]
    [ResponseCache(Duration = 60, Location = ResponseCacheLocation.Any)]
    public async Task<ActionResult<ApiResponse<Dictionary<string, object?>>>> GetPublicSettings(
        CancellationToken cancellationToken)
    {
        var values = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);

        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync(cancellationToken);

        const string sql =
            "select key, value_json::text from udrive.system_settings where is_public = true order by key";

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var key = reader.GetString(0);
            var raw = reader.GetString(1);

            // Values are stored as jsonb. Unwrap scalars so clients receive
            // "https://..." rather than "\"https://...\"".
            try
            {
                using var document = JsonDocument.Parse(raw);
                values[key] = document.RootElement.ValueKind switch
                {
                    JsonValueKind.String => document.RootElement.GetString(),
                    JsonValueKind.Number => document.RootElement.GetDouble(),
                    JsonValueKind.True => true,
                    JsonValueKind.False => false,
                    JsonValueKind.Null => null,
                    _ => raw
                };
            }
            catch (JsonException)
            {
                values[key] = raw;
            }
        }

        return Ok(ApiResponse<Dictionary<string, object?>>.Ok(values));
    }
}
