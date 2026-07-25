using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/tour-interests")]
public sealed class TourInterestsController(
    TourInterestService tourInterestService) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        CreateTourInterestRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await tourInterestService.CreateAsync(
            User.GetRequiredUserId(),
            request,
            cancellationToken));

    [HttpGet("my")]
    public async Task<IActionResult> GetMine(
        CancellationToken cancellationToken) =>
        ToActionResult(await tourInterestService.GetMineAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [HttpGet("matches")]
    public async Task<IActionResult> GetMatches(
        [FromQuery] Guid? interestId,
        CancellationToken cancellationToken) =>
        ToActionResult(await tourInterestService.GetMatchesAsync(
            User.GetRequiredUserId(),
            interestId,
            cancellationToken));

    [HttpPut("{interestId:guid}/active")]
    public async Task<IActionResult> SetActive(
        Guid interestId,
        [FromBody] SetTourInterestActiveRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await tourInterestService.SetActiveAsync(
            User.GetRequiredUserId(),
            interestId,
            request.Active,
            cancellationToken));

    private IActionResult ToActionResult<T>(ServiceResult<T> result)
    {
        if (!result.Success)
        {
            return StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
                traceId = HttpContext.TraceIdentifier
            });
        }

        var response = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(StatusCodes.Status201Created, response)
            : Ok(response);
    }
}

public sealed record SetTourInterestActiveRequest(bool Active);
