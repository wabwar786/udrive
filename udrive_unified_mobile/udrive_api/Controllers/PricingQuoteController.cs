using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// What a trip costs, decided here rather than in the app.
/// </summary>
/// <remarks>
/// Requires a signed-in customer. The rate card itself stays public at
/// <c>/api/v1/catalog/service-rates</c> so a browsing customer still sees
/// indicative prices, but a quote is a commitment the server will be held to
/// later, and issuing those to anybody who asks is how a pricing model gets
/// mapped by whoever wants it.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/pricing")]
public sealed class PricingQuoteController(FareEngine fareEngine) : ControllerBase
{
    [HttpPost("quote")]
    public async Task<IActionResult> Quote(
        FareQuoteRequest request,
        CancellationToken cancellationToken) =>
        Result(await fareEngine.QuoteAsync(
            User.GetRequiredUserId(), request, cancellationToken));

    private IActionResult Result<T>(ServiceResult<T> result)
    {
        if (!result.Success)
        {
            return StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
                traceId = HttpContext.TraceIdentifier,
            });
        }

        var body = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(StatusCodes.Status201Created, body)
            : Ok(body);
    }
}
