using Npgsql;

namespace UDrive.Api.Services;

public sealed record VerificationFileLookupResult(
    bool MetadataFound,
    string? StoredUrl,
    ResolvedStoredFile? File);

public sealed class VerificationFileLookupService(
    string connectionString,
    LocalFileStorageService fileStorage)
{
    /// <summary>
    /// A Driver's own document, only if it really is theirs.
    /// </summary>
    /// <remarks>
    /// The admin lookups above take a document id and nothing else, which is
    /// right for a reviewer and wrong for a Driver: a document id in a URL
    /// would otherwise let any signed-in Driver read any other Driver's CNIC.
    /// The user id is part of the WHERE clause, not checked afterwards.
    /// </remarks>
    public Task<VerificationFileLookupResult> FindOwnDriverDocumentAsync(
        Guid documentId,
        Guid userId,
        CancellationToken cancellationToken) =>
        FindOwnedAsync(
            """
            SELECT d.file_url
            FROM udrive.driver_documents d
            JOIN udrive.driver_profiles dp ON dp.id = d.driver_profile_id
            WHERE d.id = @id AND dp.user_id = @user
            LIMIT 1;
            """,
            documentId,
            userId,
            cancellationToken);

    /// <summary>A vehicle document belonging to this Driver's own vehicle.</summary>
    public Task<VerificationFileLookupResult> FindOwnVehicleDocumentAsync(
        Guid documentId,
        Guid userId,
        CancellationToken cancellationToken) =>
        FindOwnedAsync(
            """
            SELECT vd.file_url
            FROM udrive.vehicle_documents vd
            JOIN udrive.vehicles v ON v.id = vd.vehicle_id
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE vd.id = @id AND dp.user_id = @user
            LIMIT 1;
            """,
            documentId,
            userId,
            cancellationToken);

    private async Task<VerificationFileLookupResult> FindOwnedAsync(
        string sql,
        Guid documentId,
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", documentId);
        command.Parameters.AddWithValue("user", userId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not string storedUrl || string.IsNullOrWhiteSpace(storedUrl))
        {
            return new VerificationFileLookupResult(false, null, null);
        }

        return new VerificationFileLookupResult(
            true,
            storedUrl,
            fileStorage.ResolveStoredUrl(storedUrl));
    }

    public Task<VerificationFileLookupResult> FindDriverDocumentAsync(
        Guid documentId,
        CancellationToken cancellationToken) =>
        FindAsync(
            "SELECT file_url FROM udrive.driver_documents WHERE id = @id LIMIT 1;",
            documentId,
            cancellationToken);

    public Task<VerificationFileLookupResult> FindVehicleDocumentAsync(
        Guid documentId,
        CancellationToken cancellationToken) =>
        FindAsync(
            "SELECT file_url FROM udrive.vehicle_documents WHERE id = @id LIMIT 1;",
            documentId,
            cancellationToken);

    private async Task<VerificationFileLookupResult> FindAsync(
        string sql,
        Guid documentId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", documentId);
        var storedUrl = await command.ExecuteScalarAsync(cancellationToken) as string;
        return storedUrl is null
            ? new VerificationFileLookupResult(false, null, null)
            : new VerificationFileLookupResult(true, storedUrl, fileStorage.ResolveStoredUrl(storedUrl));
    }
}
