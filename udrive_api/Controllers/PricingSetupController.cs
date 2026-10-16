using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The admin Pricing page: everyday rates, switches, suggestions, fare check.</summary>
/// <remarks>
/// Same roles as the pricing rules: anyone on the pricing team can look and
/// check a fare; only SuperAdmin, Admin and FinanceOfficer can save.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,FinanceOfficer")]
[Route("api/v1/admin/pricing-setup")]
public sealed class PricingSetupController(PricingSetupService service, FareEngine engine) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct) =>
        HubResults.From(this, await service.GetAsync(ct));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPut("rates")]
    public async Task<IActionResult> SaveRates(SavePricingRatesRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveRatesAsync(User.GetRequiredUserId(), request, ct));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPut("switches")]
    public async Task<IActionResult> SaveSwitches(SavePricingSwitchesRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveSwitchesAsync(User.GetRequiredUserId(), request, ct));

    /// <summary>The real quote for a sample trip, line by line. Saves nothing.</summary>
    [HttpPost("check")]
    public async Task<IActionResult> Check(PricingCheckRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.CheckAsync(User.GetRequiredUserId(), request, engine, ct));
}
