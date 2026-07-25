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
