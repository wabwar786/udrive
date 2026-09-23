using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

/// <summary>Current OTP configuration as the admin portal sees it. The API key is never returned.</summary>
public sealed record OtpSettingsDto(
    string Provider,
    string EffectiveProvider,
    bool ProviderOverriddenByEnvironment,
    string BaseUrl,
    bool ApiKeySet,
    string ApiKeyHint,
    string SendPath,
    string MessageTemplate,
    string TestPhone,
    bool TestCodeSet,
    DateTimeOffset? LastTestOkAt,
    bool CurrentConfigTested);

/// <summary>
/// Admin update. Null <see cref="ApiKey"/> / <see cref="TestCode"/> keep the stored value;
/// an empty string clears it.
/// </summary>
public sealed record UpdateOtpSettingsRequest(
    string Provider,
    string BaseUrl,
    string? ApiKey,
    string SendPath,
    string MessageTemplate,
    string? TestPhone,
    string? TestCode);

public sealed record OtpTestRequest(string PhoneNumber);

public sealed record OtpTestResultDto(bool Delivered, int? StatusCode, string ProviderResponse);

/// <summary>
/// Chooses how login codes are delivered and delivers them.
///
/// Providers:
///  * <c>Development</c> – fixed code from DEVELOPMENT_OTP_CODE, nothing is sent.
///  * <c>WhatsApp</c>    – random 4-digit code sent through WA Engine
///                         (POST {baseUrl}{sendPath}, header x-api-key, body { to, message }).
///
/// Settings live in udrive.system_settings under <c>otp.*</c>, are never public, and are
/// hidden from the generic settings page so the API key cannot leak there.
///
/// Safety rails:
///  * WhatsApp can only be switched on after a successful test message with the
///    current base URL / key / path, so an admin cannot lock everyone out.
///  * OTP_PROVIDER_OVERRIDE (env) wins over the database — the recovery switch if
///    WA Engine is down and nobody can sign in to the portal.
///  * A reviewer number with a fixed code (Google Play "App access") works under
///    any provider and never sends a message.
/// </summary>
public sealed class OtpDeliveryService(
    string connectionString,
    AuthOptions authOptions,
    IHttpClientFactory httpClientFactory,
    ILogger<OtpDeliveryService> logger)
{
    public const string HttpClientName = "wa-otp";
    public const string DefaultBaseUrl = "https://wa-engine-deploy-production.up.railway.app";
    public const string DefaultSendPath = "/api/send";
    public const string DefaultTemplate =
        "Your UDrive verification code is {code}. It expires in 5 minutes. Do not share this code with anyone.";

    private const string KeyProvider = "otp.provider";
    private const string KeyBaseUrl = "otp.whatsapp.base_url";
    private const string KeyApiKey = "otp.whatsapp.api_key";
    private const string KeySendPath = "otp.whatsapp.send_path";
    private const string KeyTemplate = "otp.whatsapp.template";
    private const string KeyTestPhone = "otp.test.phone";
    private const string KeyTestCode = "otp.test.code";
    private const string KeyLastTestOk = "otp.whatsapp.last_test_ok";

    /// <summary>What <see cref="AuthService"/> needs to create one challenge.</summary>
    public sealed record OtpPlan(string Provider, string Code, bool Send, string? DevelopmentCodeToExpose);

    private sealed record Stored(
        string Provider, string BaseUrl, string ApiKey, string SendPath,
        string Template, string TestPhone, string TestCode, string LastTestOk);

    // ------------------------------------------------------------------ login

    /// <summary>Decides provider and code for a phone number (already normalised, e.g. 923001234567).</summary>
    public async Task<OtpPlan> PlanAsync(string phoneNumber, CancellationToken ct)
    {
        var s = await ReadAsync(ct);

        if (s.TestPhone.Length > 0 && s.TestCode.Length > 0 &&
            PhoneNumberDigits(s.TestPhone) == PhoneNumberDigits(phoneNumber))
        {
            return new OtpPlan("Test", s.TestCode, Send: false, DevelopmentCodeToExpose: null);
        }

        var provider = EffectiveProvider(s.Provider);
        if (provider == "WhatsApp")
        {
            var code = RandomNumberGenerator.GetInt32(0, 10000).ToString("D4");
            return new OtpPlan("WhatsApp", code, Send: true, DevelopmentCodeToExpose: null);
        }

        return new OtpPlan(
            "Development",
            authOptions.DevelopmentOtpCode,
            Send: false,
            authOptions.ExposeDevelopmentOtp ? authOptions.DevelopmentOtpCode : null);
    }

    /// <summary>Sends the login code on WhatsApp. Returns false (already logged) when WA Engine fails.</summary>
    public async Task<bool> SendLoginCodeAsync(string phoneNumber, string code, CancellationToken ct)
    {
        var s = await ReadAsync(ct);
        var template = s.Template.Contains("{code}", StringComparison.Ordinal) ? s.Template : DefaultTemplate;
        var result = await SendAsync(s, phoneNumber, template.Replace("{code}", code, StringComparison.Ordinal), ct);
        return result.Delivered;
    }

    // ------------------------------------------------------------------ admin

    public async Task<OtpSettingsDto> GetAsync(CancellationToken ct) => ToDto(await ReadAsync(ct));

    public async Task<ServiceResult<OtpSettingsDto>> UpdateAsync(
        Guid adminUserId, UpdateOtpSettingsRequest request, CancellationToken ct)
    {
        var provider = NormaliseProvider(request.Provider);
        if (provider is null)
            return Fail<OtpSettingsDto>(400, "invalid_provider", "Provider must be Development or WhatsApp.");

        var baseUrl = (request.BaseUrl ?? string.Empty).Trim().TrimEnd('/');
        if (baseUrl.Length == 0) baseUrl = DefaultBaseUrl;
        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            return Fail<OtpSettingsDto>(400, "invalid_base_url", "Base URL must be a full https:// address.");

        var sendPath = (request.SendPath ?? string.Empty).Trim();
        if (sendPath.Length == 0) sendPath = DefaultSendPath;
        if (!sendPath.StartsWith('/')) sendPath = "/" + sendPath;
        if (sendPath.Length > 120 || sendPath.Contains("://", StringComparison.Ordinal))
            return Fail<OtpSettingsDto>(400, "invalid_send_path", "Send path must look like /api/send.");

        var template = (request.MessageTemplate ?? string.Empty).Trim();
        if (template.Length == 0) template = DefaultTemplate;
        if (!template.Contains("{code}", StringComparison.Ordinal))
            return Fail<OtpSettingsDto>(400, "template_missing_code", "The message must contain {code}.");
        if (template.Length > 500)
            return Fail<OtpSettingsDto>(400, "template_too_long", "Keep the message under 500 characters.");

        var current = await ReadAsync(ct);
        var apiKey = request.ApiKey is null ? current.ApiKey : request.ApiKey.Trim();
        if (apiKey.Length > 200)
            return Fail<OtpSettingsDto>(400, "invalid_api_key", "The API key is too long.");

        var testPhone = (request.TestPhone ?? string.Empty).Trim();
        if (testPhone.Length > 0)
        {
            if (!PhoneNumberNormalizer.TryNormalizePakistan(testPhone, out var normalised))
                return Fail<OtpSettingsDto>(400, "invalid_test_phone", "Reviewer number must be a valid Pakistani mobile number.");
            testPhone = normalised;
        }

        var testCode = request.TestCode is null ? current.TestCode : request.TestCode.Trim();
        if (testCode.Length > 0 && (testCode.Length != 4 || !testCode.All(char.IsDigit)))
            return Fail<OtpSettingsDto>(400, "invalid_test_code", "Reviewer code must be exactly 4 digits.");
        if (testPhone.Length > 0 && testCode.Length == 0)
            return Fail<OtpSettingsDto>(400, "test_code_required", "Set a 4-digit code for the reviewer number.");

        var next = current with
        {
            Provider = provider, BaseUrl = baseUrl, ApiKey = apiKey, SendPath = sendPath,
            Template = template, TestPhone = testPhone, TestCode = testCode
        };

        if (provider == "WhatsApp")
        {
            if (apiKey.Length == 0)
                return Fail<OtpSettingsDto>(400, "api_key_required", "Enter the WA Engine API key before switching on WhatsApp.");
            if (current.LastTestOk.Split('|', 2)[0] != Fingerprint(next))
                return Fail<OtpSettingsDto>(409, "test_required",
                    "Save these settings with provider Development, send a test message, then switch on WhatsApp.");
        }

        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);
        await using var tx = await cn.BeginTransactionAsync(ct);
        await WriteAsync(cn, tx, adminUserId, KeyProvider, provider, "Login code delivery: Development or WhatsApp.", ct);
        await WriteAsync(cn, tx, adminUserId, KeyBaseUrl, baseUrl, "WA Engine base URL for login codes.", ct);
        await WriteAsync(cn, tx, adminUserId, KeyApiKey, apiKey, "WA Engine API key (secret).", ct);
        await WriteAsync(cn, tx, adminUserId, KeySendPath, sendPath, "WA Engine send endpoint path.", ct);
        await WriteAsync(cn, tx, adminUserId, KeyTemplate, template, "WhatsApp login code message; {code} is replaced.", ct);
        await WriteAsync(cn, tx, adminUserId, KeyTestPhone, testPhone, "Reviewer number that always accepts the reviewer code.", ct);
        await WriteAsync(cn, tx, adminUserId, KeyTestCode, testCode, "Reviewer code (secret).", ct);
        await using (var audit = new NpgsqlCommand("""
            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @a, 'OtpSettingsUpdated', 'SystemSettings', 'otp',
                    jsonb_build_object('provider', @p, 'baseUrl', @b, 'sendPath', @s, 'apiKeyChanged', @k), now(), now());
            """, cn, tx))
        {
            audit.Parameters.AddWithValue("a", adminUserId);
            audit.Parameters.AddWithValue("p", provider);
            audit.Parameters.AddWithValue("b", baseUrl);
            audit.Parameters.AddWithValue("s", sendPath);
            audit.Parameters.AddWithValue("k", apiKey != current.ApiKey);
            await audit.ExecuteNonQueryAsync(ct);
        }
        await tx.CommitAsync(ct);

        return ServiceResult<OtpSettingsDto>.Ok(await GetAsync(ct), "OTP settings saved.");
    }

    /// <summary>Sends a test message with the stored settings and remembers success for this configuration.</summary>
    public async Task<ServiceResult<OtpTestResultDto>> TestAsync(Guid adminUserId, string phoneNumber, CancellationToken ct)
    {
        if (!PhoneNumberNormalizer.TryNormalizePakistan(phoneNumber, out var phone))
            return Fail<OtpTestResultDto>(400, "invalid_phone_number", "Enter a valid Pakistani mobile number, for example 03001234567.");

        var s = await ReadAsync(ct);
        if (s.ApiKey.Length == 0)
            return Fail<OtpTestResultDto>(400, "api_key_required", "Save the WA Engine API key first.");

        var result = await SendAsync(s, phone,
            "UDrive test: WhatsApp login codes are connected. You can ignore this message.", ct);

        if (result.Delivered)
        {
            await using var cn = new NpgsqlConnection(connectionString);
            await cn.OpenAsync(ct);
            await WriteAsync(cn, null, adminUserId, KeyLastTestOk, Fingerprint(s) + "|" + DateTimeOffset.UtcNow.ToString("O"),
                "Fingerprint of the last WA settings that delivered a test message.", ct);
        }

        return ServiceResult<OtpTestResultDto>.Ok(result,
            result.Delivered ? "Test message sent. Check WhatsApp on that number." : "WA Engine did not accept the message.");
    }

    /// <summary>
    /// The WA Engine connection every other WhatsApp feature should use (SOS
    /// location share, emergency broadcast), so the whole platform follows the
    /// one place an admin configures.
    /// </summary>
    public async Task<(string BaseUrl, string ApiKey, string SendPath, string BulkPath)> EndpointAsync(
        CancellationToken ct)
    {
        var s = await ReadAsync(ct);
        var bulkPath = s.SendPath.EndsWith("/send", StringComparison.OrdinalIgnoreCase)
            ? s.SendPath + "-bulk"
            : "/api/send-bulk";
        return (s.BaseUrl.TrimEnd('/'), s.ApiKey, s.SendPath, bulkPath);
    }

    /// <summary>Asks WA Engine whether its WhatsApp session is connected (GET /api/status).</summary>
    public async Task<ServiceResult<OtpTestResultDto>> StatusAsync(CancellationToken ct)
    {
        var s = await ReadAsync(ct);
        if (s.ApiKey.Length == 0)
        {
            return ServiceResult<OtpTestResultDto>.Fail(
                400, "api_key_required", "Save the WA Engine API key first.");
        }

        var url = s.BaseUrl.TrimEnd('/') + "/api/status";
        try
        {
            var client = httpClientFactory.CreateClient(HttpClientName);
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("x-api-key", s.ApiKey);
            using var response = await client.SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);
            var snippet = body.Length > 300 ? body[..300] : body;
            var ok = response.IsSuccessStatusCode && !ReportsFailure(body);
            return ServiceResult<OtpTestResultDto>.Ok(
                new OtpTestResultDto(ok, (int)response.StatusCode, snippet),
                ok ? "WA Engine answered." : "WA Engine is reachable but reported a problem.");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            logger.LogError(ex, "WA Engine status check to {Url} failed.", url);
            return ServiceResult<OtpTestResultDto>.Ok(
                new OtpTestResultDto(false, null, ex is TaskCanceledException ? "Timed out." : ex.Message),
                "WA Engine could not be reached.");
        }
    }

    // ------------------------------------------------------------------ internals

    private async Task<OtpTestResultDto> SendAsync(Stored s, string phoneNumber, string message, CancellationToken ct)
    {
        if (s.ApiKey.Length == 0)
        {
            logger.LogError("WhatsApp OTP requested but no WA Engine API key is configured.");
            return new OtpTestResultDto(false, null, "No API key configured.");
        }

        var to = PhoneNumberDigits(phoneNumber);
        var url = s.BaseUrl.TrimEnd('/') + s.SendPath;
        try
        {
            var client = httpClientFactory.CreateClient(HttpClientName);
            using var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.TryAddWithoutValidation("x-api-key", s.ApiKey);
            request.Content = JsonContent.Create(new { to, message });

            using var response = await client.SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);
            var snippet = body.Length > 300 ? body[..300] : body;
            var delivered = response.IsSuccessStatusCode && !ReportsFailure(body);
            if (!delivered)
            {
                logger.LogWarning("WA Engine rejected an OTP message ({Status}): {Body}", (int)response.StatusCode, snippet);
            }
            return new OtpTestResultDto(delivered, (int)response.StatusCode, snippet);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            logger.LogError(ex, "WA Engine OTP request to {Url} failed.", url);
            return new OtpTestResultDto(false, null, ex is TaskCanceledException ? "Timed out." : ex.Message);
        }
    }

    /// <summary>WA Engine may answer 200 with { success:false } — treat that as a failure.</summary>
    private static bool ReportsFailure(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return false;
            foreach (var name in new[] { "success", "ok" })
            {
                if (doc.RootElement.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.False)
                    return true;
            }
        }
        catch (JsonException)
        {
            // Plain-text success responses are acceptable.
        }
        return false;
    }

    private string EffectiveProvider(string stored) =>
        NormaliseProvider(Environment.GetEnvironmentVariable("OTP_PROVIDER_OVERRIDE"))
        ?? NormaliseProvider(stored)
        ?? NormaliseProvider(authOptions.OtpProvider)
        ?? "Development";

    private static string? NormaliseProvider(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "whatsapp" => "WhatsApp",
        "development" => "Development",
        _ => null
    };

    private static string PhoneNumberDigits(string value) => new(value.Where(char.IsDigit).ToArray());

    /// <summary>Hash of everything that decides whether a message can be delivered.</summary>
    private static string Fingerprint(Stored s)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{s.BaseUrl}\n{s.SendPath}\n{s.ApiKey}"));
        return Convert.ToHexString(bytes)[..24];
    }

    private OtpSettingsDto ToDto(Stored s)
    {
        var lastOkParts = s.LastTestOk.Split('|', 2);
        DateTimeOffset? lastOkAt = lastOkParts.Length == 2 && DateTimeOffset.TryParse(lastOkParts[1], out var at) ? at : null;
        var tested = lastOkParts.Length == 2 && lastOkParts[0] == Fingerprint(s);
        var overridden = NormaliseProvider(Environment.GetEnvironmentVariable("OTP_PROVIDER_OVERRIDE")) is not null;
        return new OtpSettingsDto(
            NormaliseProvider(s.Provider) ?? NormaliseProvider(authOptions.OtpProvider) ?? "Development",
            EffectiveProvider(s.Provider),
            overridden,
            s.BaseUrl,
            s.ApiKey.Length > 0,
            s.ApiKey.Length > 4 ? "••••" + s.ApiKey[^4..] : (s.ApiKey.Length > 0 ? "••••" : ""),
            s.SendPath,
            s.Template,
            s.TestPhone,
            s.TestCode.Length > 0,
            lastOkAt,
            tested);
    }

    private async Task<Stored> ReadAsync(CancellationToken ct)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        await using (var cn = new NpgsqlConnection(connectionString))
        {
            await cn.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                "SELECT key, value_json #>> '{}' FROM udrive.system_settings WHERE key LIKE 'otp.%';", cn);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                values[r.GetString(0)] = r.IsDBNull(1) ? string.Empty : r.GetString(1);
            }
        }

        string Get(string key, string fallback) =>
            values.TryGetValue(key, out var v) && !string.IsNullOrWhiteSpace(v) ? v.Trim() : fallback;

        var stored = new Stored(
            Get(KeyProvider, authOptions.OtpProvider),
            Get(KeyBaseUrl, DefaultBaseUrl).TrimEnd('/'),
            Get(KeyApiKey, Environment.GetEnvironmentVariable("WA_ENGINE_API_KEY") ?? string.Empty),
            Get(KeySendPath, DefaultSendPath),
            Get(KeyTemplate, DefaultTemplate),
            Get(KeyTestPhone, string.Empty),
            Get(KeyTestCode, string.Empty),
            Get(KeyLastTestOk, string.Empty));

        return stored;
    }

    private static async Task WriteAsync(
        NpgsqlConnection cn, NpgsqlTransaction? tx, Guid adminUserId,
        string key, string value, string description, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO udrive.system_settings (key, value_json, description, is_public, updated_by_user_id, created_at, updated_at)
            VALUES (@key, to_jsonb(@value::text), @description, false, @admin, now(), now())
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                description = EXCLUDED.description,
                is_public = false,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """, cn, tx);
        cmd.Parameters.AddWithValue("key", key);
        cmd.Parameters.AddWithValue("value", value);
        cmd.Parameters.AddWithValue("description", description);
        cmd.Parameters.AddWithValue("admin", adminUserId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) =>
        ServiceResult<T>.Fail(status, code, message);
}
