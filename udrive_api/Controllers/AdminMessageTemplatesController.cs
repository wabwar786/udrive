using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Setup → WhatsApp messages.</summary>
[ApiController]
[Authorize(Roles = "Admin,SuperAdmin")]
[Route("api/v1/admin/message-templates")]
public sealed class AdminMessageTemplatesController(MessageTemplateService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) =>
        HubResults.From(this, await service.ListAsync(ct));

    [HttpPut("{key}")]
    public async Task<IActionResult> Update(string key, UpdateMessageTemplateRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.UpdateAsync(User.GetRequiredUserId(), key.Trim().ToLowerInvariant(), request, ct));
}
