using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The Customer's identity documents, needed only to drive a rented car.
/// </summary>
/// <remarks>
/// Four columns on <c>customer_profiles</c> rather than a table with a status, a
/// reviewer and a queue. Nobody at UDrive reviews these, and that is a decision
/// rather than an omission: the owner handing over the car checks the documents
/// against the person standing in front of them, which is the only check that
/// proves anything. An Admin approving a photograph of a CNIC a week earlier
/// proves nothing and makes the platform look as though it vouched for the
/// person.
///
/// Asked once. A second rental does not ask again.
///
/// They are never public. The upload lands in a protected category and comes
/// back only to the owner of a vehicle this Customer has actually booked, while
/// that booking is live — see <c>RentalController</c>.
/// </remarks>
public sealed class CustomerDocumentsService(
    string connectionString,
    LocalFileStorageService fileStorage)
{
    private static readonly string[] Kinds =
        ["cnic-front", "cnic-back", "driving-licence", "selfie"];

    public async Task<ServiceResult<CustomerDocumentsDto>> GetAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        return ServiceResult<CustomerDocumentsDto>.Ok(
            await ReadAsync(connection, userId, cancellationToken));
    }

    /// <summary>Stores one of the four, replacing whatever was there.</summary>
    public async Task<ServiceResult<CustomerDocumentsDto>> UploadAsync(
        Guid userId,
        string kind,
        IFormFile file,
        CancellationToken cancellationToken)
    {
        var column = Column(kind);
        if (column is null)
        {
            return ServiceResult<CustomerDocumentsDto>.Fail(
                StatusCodes.Status400BadRequest,
                "document_kind_invalid",
                $"Send one of: {string.Join(", ", Kinds)}.");
        }

        StoredFile stored;
        try
        {
            stored = await fileStorage.SaveAsync(
                file, "customer-documents", userId, cancellationToken);
        }
        catch (InvalidDataException error)
        {
            return ServiceResult<CustomerDocumentsDto>.Fail(
                StatusCodes.Status400BadRequest, "file_invalid", error.Message);
        }
        catch (InvalidOperationException error)
        {
            return ServiceResult<CustomerDocumentsDto>.Fail(
                StatusCodes.Status503ServiceUnavailable, "storage_unavailable", error.Message);
        }

        // The profile row is created at sign-up, but a customer who predates
        // that is not made to fail here over a row they never knew about.
        var sql = $"""
            INSERT INTO udrive.customer_profiles
                (id, user_id, {column}, documents_updated_at, created_at, updated_at)
            VALUES (gen_random_uuid(), @userId, @url, now(), now(), now())
            ON CONFLICT (user_id) DO UPDATE
            SET {column} = EXCLUDED.{column},
                documents_updated_at = now(),
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.Add(new NpgsqlParameter("url", NpgsqlDbType.Text)
            {
                Value = stored.RelativeUrl,
            });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        return ServiceResult<CustomerDocumentsDto>.Ok(
            await ReadAsync(connection, userId, cancellationToken));
    }

    /// <summary>
    /// The stored path of one document, for the owner of a live booking.
    /// </summary>
    /// <remarks>
    /// The caller must already have established that this user is entitled to
    /// see it. Nothing here checks that, and nothing here is reachable from a
    /// route that does not.
    /// </remarks>
    public async Task<string?> StoredUrlAsync(
        Guid customerUserId,
        string kind,
        CancellationToken cancellationToken)
    {
        var column = Column(kind);
        if (column is null) return null;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            $"SELECT {column} FROM udrive.customer_profiles WHERE user_id = @userId;",
            connection);
        command.Parameters.AddWithValue("userId", customerUserId);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }

    private static async Task<CustomerDocumentsDto> ReadAsync(
        NpgsqlConnection connection,
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT cnic_front_url IS NOT NULL, cnic_back_url IS NOT NULL,
                   driving_licence_url IS NOT NULL, selfie_url IS NOT NULL,
                   documents_updated_at
            FROM udrive.customer_profiles
            WHERE user_id = @userId;
            """,
            connection);
        command.Parameters.AddWithValue("userId", userId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return new CustomerDocumentsDto(false, false, false, false, false, null);
        }

        var front = reader.GetBoolean(0);
        var back = reader.GetBoolean(1);
        var licence = reader.GetBoolean(2);
        var selfie = reader.GetBoolean(3);

        return new CustomerDocumentsDto(
            front, back, licence, selfie,
            front && back && licence && selfie,
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4));
    }

    /// <remarks>
    /// A fixed map, never the caller's string. These names are interpolated
    /// into SQL, and a column name cannot be a parameter — so the only safe
    /// shape is one where no caller-supplied text ever reaches the statement.
    /// </remarks>
    private static string? Column(string? kind) => kind?.Trim().ToLowerInvariant() switch
    {
        "cnic-front" => "cnic_front_url",
        "cnic-back" => "cnic_back_url",
        "driving-licence" => "driving_licence_url",
        "selfie" => "selfie_url",
        _ => null,
    };
}
