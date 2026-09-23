using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

public sealed record CustomPlaceDto(
    Guid Id,
    string Name,
    string District,
    string[] Aliases,
    double Latitude,
    double Longitude,
    string Note,
    bool IsActive);

public sealed record CustomPlaceRequest(
    string Name,
    string? District,
    string[]? Aliases,
    double Latitude,
    double Longitude,
    string? Note,
    bool IsActive = true);

/// <summary>
/// Places an admin has pinned by hand.
/// </summary>
/// <remarks>
/// Exists because Google does not know most of Azad Kashmir's villages, and
/// nothing at all about the tracks that reach them. An admin who knows the area
/// can drop a pin and name it, and customers can then find it.
///
/// Writing requires an admin; reading is done by <see cref="PlacesController"/>
/// as part of ordinary search.
/// </remarks>
[ApiController]
[Route("api/v1/admin/places")]
[Authorize(Roles = "Admin,SuperAdmin")]
public sealed class AdminPlacesController(IConfiguration configuration) : ControllerBase
{
    private string ConnectionString => ConnectionStringFactory.Resolve(configuration);

    [HttpGet]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<CustomPlaceDto>>>> List(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, name, district, aliases, latitude, longitude, note, is_active
            FROM udrive.custom_places
            ORDER BY district, name;
            """;

        var list = new List<CustomPlaceDto>();
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new CustomPlaceDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetFieldValue<string[]>(3),
                reader.GetDouble(4),
                reader.GetDouble(5),
                reader.GetString(6),
                reader.GetBoolean(7)));
        }

        return Ok(ApiResponse<IReadOnlyList<CustomPlaceDto>>.Ok(list));
    }

    [HttpPost]
    public async Task<ActionResult<object>> Create(
        [FromBody] CustomPlaceRequest request,
        CancellationToken cancellationToken)
    {
        var error = Validate(request);
        if (error is not null) return BadRequest(new { success = false, message = error });

        const string sql = """
            INSERT INTO udrive.custom_places
                (name, district, aliases, latitude, longitude, note, is_active)
            VALUES (@name, @district, @aliases, @lat, @lng, @note, @active)
            RETURNING id;
            """;

        try
        {
            await using var connection = new NpgsqlConnection(ConnectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(sql, connection);
            Bind(command, request);

            var id = await command.ExecuteScalarAsync(cancellationToken);
            return Ok(ApiResponse<object>.Ok(new { id }));
        }
        catch (PostgresException ex) when (ex.SqlState == "23505")
        {
            return Conflict(new
            {
                success = false,
                message = $"A place named \"{request.Name.Trim()}\" already exists."
            });
        }
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<object>> Update(
        Guid id,
        [FromBody] CustomPlaceRequest request,
        CancellationToken cancellationToken)
    {
        var error = Validate(request);
        if (error is not null) return BadRequest(new { success = false, message = error });

        const string sql = """
            UPDATE udrive.custom_places
               SET name = @name,
                   district = @district,
                   aliases = @aliases,
                   latitude = @lat,
                   longitude = @lng,
                   note = @note,
                   is_active = @active,
                   updated_at = now()
             WHERE id = @id;
            """;

        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        Bind(command, request);

        var rows = await command.ExecuteNonQueryAsync(cancellationToken);
        if (rows == 0) return NotFound(new { success = false, message = "Place not found." });

        return Ok(ApiResponse<object>.Ok(new { id }));
    }

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<object>> Delete(Guid id, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "DELETE FROM udrive.custom_places WHERE id = @id;", connection);
        command.Parameters.AddWithValue("id", id);

        var rows = await command.ExecuteNonQueryAsync(cancellationToken);
        if (rows == 0) return NotFound(new { success = false, message = "Place not found." });

        return Ok(ApiResponse<object>.Ok(new { id }));
    }

    /// <summary>
    /// Rejects input that would produce a pin nobody can use.
    /// </summary>
    /// <remarks>
    /// The bounds are Pakistan-wide rather than Kashmir-only, so a legitimate
    /// pin just outside AJK is still accepted — but a transposed or mistyped
    /// coordinate landing in another continent is caught before a driver is
    /// sent there.
    /// </remarks>
    private static string? Validate(CustomPlaceRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return "Give the place a name.";
        }

        if (!double.IsFinite(request.Latitude) || !double.IsFinite(request.Longitude))
        {
            return "Latitude and longitude must be numbers.";
        }

        if (request.Latitude is < 23 or > 38 || request.Longitude is < 60 or > 78)
        {
            return "That coordinate is outside Pakistan. Check the two numbers "
                 + "are not swapped — latitude comes first.";
        }

        return null;
    }

    private static void Bind(NpgsqlCommand command, CustomPlaceRequest request)
    {
        var aliases = (request.Aliases ?? [])
            .Select(alias => alias.Trim().ToLowerInvariant())
            .Where(alias => alias.Length > 0)
            .Distinct()
            .ToArray();

        command.Parameters.AddWithValue("name", request.Name.Trim());
        command.Parameters.AddWithValue("district", request.District?.Trim() ?? string.Empty);
        command.Parameters.AddWithValue("aliases", aliases);
        command.Parameters.AddWithValue("lat", request.Latitude);
        command.Parameters.AddWithValue("lng", request.Longitude);
        command.Parameters.AddWithValue("note", request.Note?.Trim() ?? string.Empty);
        command.Parameters.AddWithValue("active", request.IsActive);
    }
}
