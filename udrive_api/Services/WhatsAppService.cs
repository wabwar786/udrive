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
    private readonly string _safetyNumber = configuration["UDRIVE_SAFETY_WHATSAPP_NUMBER"]
        ?? Environment.GetEnvironmentVariable("UDRIVE_SAFETY_WHATSAPP_NUMBER")
        ?? string.Empty;

    public async Task<ServiceResult<WhatsAppSendResultDto>> ShareLocationAsync(
        WhatsAppLocationShareRequest request,
        CancellationToken cancellationToken)
    {
        var number = NormalizePhone(request.To);
        if (number.Length < 10 || number.Length > 15)
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(400, "invalid_whatsapp_number", "A valid WhatsApp mobile number is required.");
        }

        if (!ValidLocation(request.Latitude, request.Longitude))
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(400, "invalid_location", "The supplied location is invalid.");
        }

        if (!Configured())
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(503, "whatsapp_not_configured", "WhatsApp sharing is temporarily unavailable.");
        }

        var mapsUrl = MapsUrl(request.Latitude, request.Longitude);
        var contactName = string.IsNullOrWhiteSpace(request.ContactName) ? "Trusted contact" : request.ContactName.Trim();
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
                LogProviderFailure(response, responseBody, "location share");
                return ServiceResult<WhatsAppSendResultDto>.Fail(502, "whatsapp_delivery_failed", "The location could not be sent through WhatsApp.");
            }

            return ServiceResult<WhatsAppSendResultDto>.Ok(
                new WhatsAppSendResultDto(true, ProviderMessageId(responseBody)),
                "Location shared through WhatsApp.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ServiceResult<WhatsAppSendResultDto>.Fail(504, "whatsapp_timeout", "WhatsApp sharing timed out. Please try again.");
        }
        catch (HttpRequestException exception)
        {
            logger.LogError(exception, "WA Engine location-share request failed.");
            return ServiceResult<WhatsAppSendResultDto>.Fail(503, "whatsapp_unavailable", "WhatsApp sharing is temporarily unavailable.");
        }
    }

    public async Task<ServiceResult<WhatsAppBulkSendResultDto>> SendEmergencyBroadcastAsync(
        WhatsAppEmergencyBroadcastRequest request,
        CancellationToken cancellationToken)
    {
        if (!ValidLocation(request.Latitude, request.Longitude))
        {
            return ServiceResult<WhatsAppBulkSendResultDto>.Fail(400, "invalid_location", "The supplied location is invalid.");
        }

        var numbers = request.Numbers
            .Append(_safetyNumber)
            .Select(NormalizePhone)
            .Where(number => number.Length is >= 10 and <= 15)
            .Distinct(StringComparer.Ordinal)
            .Take(12)
            .ToArray();

        if (numbers.Length == 0)
        {
            return ServiceResult<WhatsAppBulkSendResultDto>.Fail(400, "no_emergency_contacts", "Add at least one valid trusted WhatsApp contact first.");
        }

        if (!Configured())
        {
            return ServiceResult<WhatsAppBulkSendResultDto>.Fail(503, "whatsapp_not_configured", "WhatsApp emergency alerts are temporarily unavailable.");
        }

        var customer = string.IsNullOrWhiteSpace(request.CustomerName) ? "A Udrive traveller" : request.CustomerName.Trim();
        var mapsUrl = MapsUrl(request.Latitude, request.Longitude);
        var accuracy = request.AccuracyMeters is > 0 ? $" (accuracy about {request.AccuracyMeters.Value:F0} m)" : string.Empty;
        var message =
            $"🚨 UDRIVE EMERGENCY ALERT 🚨\n\n" +
            $"{customer} has activated the emergency microphone/panic alert.\n" +
            $"Current location: {mapsUrl}\n" +
            $"Coordinates: {request.Latitude:F6}, {request.Longitude:F6}{accuracy}\n" +
            $"Alert time: {DateTimeOffset.UtcNow:yyyy-MM-dd HH:mm} UTC\n\n" +
            "Please call the traveller immediately and contact Rescue 1122 or Police 15 when required.";

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "api/send-bulk");
        httpRequest.Headers.TryAddWithoutValidation("x-api-key", _apiKey);
        httpRequest.Content = JsonContent.Create(new { numbers, message });

        try
        {
            using var response = await client.SendAsync(httpRequest, cancellationToken);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                LogProviderFailure(response, responseBody, "emergency broadcast");
                return ServiceResult<WhatsAppBulkSendResultDto>.Fail(502, "whatsapp_bulk_delivery_failed", "The emergency alert could not be sent through WhatsApp.");
            }

            return ServiceResult<WhatsAppBulkSendResultDto>.Ok(
                new WhatsAppBulkSendResultDto(true, numbers.Length),
                $"Emergency alert sent to {numbers.Length} WhatsApp contact(s).");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ServiceResult<WhatsAppBulkSendResultDto>.Fail(504, "whatsapp_timeout", "WhatsApp emergency alert timed out. Please try again.");
        }
        catch (HttpRequestException exception)
        {
            logger.LogError(exception, "WA Engine emergency-broadcast request failed.");
            return ServiceResult<WhatsAppBulkSendResultDto>.Fail(503, "whatsapp_unavailable", "WhatsApp emergency alerts are temporarily unavailable.");
        }
    }

    private bool Configured()
    {
        if (!string.IsNullOrWhiteSpace(_apiKey)) return true;
        logger.LogError("WA_ENGINE_API_KEY is not configured.");
        return false;
    }

    private void LogProviderFailure(HttpResponseMessage response, string body, string operation) =>
        logger.LogWarning(
            "WA Engine rejected {Operation} with status {StatusCode}. Response: {Response}",
            operation,
            (int)response.StatusCode,
            body.Length > 500 ? body[..500] : body);

    private static bool ValidLocation(double latitude, double longitude) =>
        latitude is >= -90 and <= 90 && longitude is >= -180 and <= 180;

    private static string MapsUrl(double latitude, double longitude) =>
        $"https://maps.google.com/?q={latitude:F6},{longitude:F6}";

    private static string? ProviderMessageId(string responseBody)
    {
        try
        {
            using var document = JsonDocument.Parse(responseBody);
            if (document.RootElement.TryGetProperty("messageId", out var id)) return id.ToString();
            if (document.RootElement.TryGetProperty("id", out id)) return id.ToString();
        }
        catch (JsonException)
        {
            // A successful plain-text response is acceptable.
        }
        return null;
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
