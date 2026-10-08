using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The hotel owner's prepaid wallet: balance, history and top-ups.</summary>
[ApiController]
[Authorize]
[Route("api/v1/hotels/owner/wallet")]
public sealed class HotelWalletController(HotelWalletService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Wallet(CancellationToken ct) =>
        HubResults.From(this, await service.WalletAsync(User.GetRequiredUserId(), ct));

    /// <summary>Multipart: amount, senderReference, file (the screenshot, optional).</summary>
    [HttpPost("topups")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(11 * 1024 * 1024)]
    public async Task<IActionResult> Topup(
        [FromForm] decimal amount, [FromForm] string? senderReference, IFormFile? file, CancellationToken ct) =>
        HubResults.From(this, await service.SubmitTopupAsync(User.GetRequiredUserId(), amount, senderReference, file, ct));
}
