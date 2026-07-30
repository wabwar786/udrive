using System.Net.Http.Json;
using System.Text.Json;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class WhatsAppService(HttpClient client, IConfiguration configuration, ILogger<WhatsAppService> logger)
{
    private readonly string _apiKey = configuration["WA_ENGINE_API_KEY"]
        ?? Environment.GetEnvironmentVariable("WA_ENGINE_API_KEY")
        ?? string.Empty;

    public async Task<ServiceResult<WhatsAppSendResultDto>> ShareLocationAsync(
        WhatsAppLocationShareRequest request,
        CancellationToken cancellationToken)
    {
        var number = NormalizePhone(request.To);
        if (number.Length < 10 || number.Length > 15)
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(
                400,
                "invalid_whatsapp_number",
                "A valid WhatsApp mobile number is required.");
        }

        if (request.Latitude is < -90 or > 90 || request.Longitude is < -180 or > 180)
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(
                400,
                "invalid_location",
                "The supplied location is invalid.");
        }

        if (string.IsNullOrWhiteSpace(_apiKey))
        {
            logger.LogError("WA_ENGINE_API_KEY is not configured.");
            return ServiceResult<WhatsAppSendResultDto>.Fail(
                503,
                "whatsapp_not_configured",
                "WhatsApp sharing is temporarily unavailable.");
        }

        var mapsUrl = $"https://maps.google.com/?q={request.Latitude:F6},{request.Longitude:F6}";
        var contactName = string.IsNullOrWhiteSpace(request.ContactName)
            ? "Trusted contact"
            : request.ContactName.Trim();
        var message =
            $"Udrive SOS location share\n\n" +
            $"Contact: {contactName}\n" +
            $"Current location: {mapsUrl}\n" +
            $"Coordinates: {request.Latitude:F6}, {request.Longitude:F6}\n" +
            $"Shared at: {DateTimeOffset.UtcNow:yyyy-MM-dd HH:mm} UTC\n\n" +
            "Please contact the traveller immediately. If this is an emergency, contact local emergency services.";

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "api/send");
        httpRequest.Headers.TryAddWithoutValidation("x-api-key", _apiKey);
        httpRequest.Content = JsonContent.Create(new { to = number, message });

        try
        {
            using var response = await client.SendAsync(httpRequest, cancellationToken);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning(
                    "WA Engine rejected location share with status {StatusCode}. Response: {Response}",
                    (int)response.StatusCode,
                    responseBody.Length > 500 ? responseBody[..500] : responseBody);
                return ServiceResult<WhatsAppSendResultDto>.Fail(
                    502,
                    "whatsapp_delivery_failed",
                    "The location could not be sent through WhatsApp.");
            }

            string? providerMessageId = null;
            try
            {
                using var document = JsonDocument.Parse(responseBody);
                if (document.RootElement.TryGetProperty("messageId", out var id))
                    providerMessageId = id.ToString();
                else if (document.RootElement.TryGetProperty("id", out id))
                    providerMessageId = id.ToString();
            }
            catch (JsonException)
            {
                // Provider may return plain text. A successful HTTP response is sufficient.
            }

            return ServiceResult<WhatsAppSendResultDto>.Ok(
                new WhatsAppSendResultDto(true, providerMessageId),
                "Location shared through WhatsApp.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(
                504,
                "whatsapp_timeout",
                "WhatsApp sharing timed out. Please try again.");
        }
        catch (HttpRequestException exception)
        {
            logger.LogError(exception, "WA Engine request failed.");
            return ServiceResult<WhatsAppSendResultDto>.Fail(
                503,
                "whatsapp_unavailable",
                "WhatsApp sharing is temporarily unavailable.");
        }
    }

    private static string NormalizePhone(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return string.Empty;
        var digits = new string(raw.Where(char.IsDigit).ToArray());
        if (digits.StartsWith("00", StringComparison.Ordinal)) digits = digits[2..];
        if (digits.StartsWith('0') && digits.Length == 11) digits = $"92{digits[1..]}";
        return digits;
    }
}
