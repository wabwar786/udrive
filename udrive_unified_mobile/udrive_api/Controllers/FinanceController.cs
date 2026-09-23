using Microsoft.AspNetCore.Authorization;using Microsoft.AspNetCore.Mvc;using UDrive.Api.Common;using UDrive.Api.Models;using UDrive.Api.Security;using UDrive.Api.Services;
namespace UDrive.Api.Controllers;
[ApiController][Route("api/v1/admin/finance")][Authorize(Roles="SuperAdmin,Admin,FinanceOfficer")]
public sealed class FinanceController(FinanceService service):ControllerBase{
[HttpGet("dashboard")]public async Task<IActionResult> Dashboard(CancellationToken ct)=>Result(await service.DashboardAsync(ct));
[HttpGet("transactions")]public async Task<IActionResult> Transactions([FromQuery]string? search,[FromQuery]string? status,[FromQuery]int page=1,[FromQuery]int pageSize=25,CancellationToken ct=default)=>Result(await service.TransactionsAsync(search,status,page,pageSize,ct));
[HttpGet("earnings")]public async Task<IActionResult> Earnings(CancellationToken ct)=>Result(await service.EarningsAsync(ct));
[HttpGet("wallets")]public async Task<IActionResult> Wallets(CancellationToken ct)=>Result(await service.WalletsAsync(ct));
[HttpGet("payouts")]public async Task<IActionResult> Payouts(CancellationToken ct)=>Result(await service.PayoutsAsync(ct));
[HttpPut("payouts/{id:guid}")]public async Task<IActionResult> ReviewPayout(Guid id,ReviewPayoutRequest request,CancellationToken ct)=>Result(await service.ReviewPayoutAsync(User.GetRequiredUserId(),id,request,ct));
[HttpGet("refunds")]public async Task<IActionResult> Refunds(CancellationToken ct)=>Result(await service.RefundsAsync(ct));
[HttpPost("refunds")]public async Task<IActionResult> CreateRefund(CreateRefundRequest request,CancellationToken ct)=>Result(await service.CreateRefundAsync(User.GetRequiredUserId(),request,ct));
[HttpPut("refunds/{id:guid}")]public async Task<IActionResult> ReviewRefund(Guid id,ReviewRefundRequest request,CancellationToken ct)=>Result(await service.ReviewRefundAsync(User.GetRequiredUserId(),id,request,ct));
[HttpGet("commission-rules")]public async Task<IActionResult> Rules(CancellationToken ct)=>Result(await service.CommissionRulesAsync(ct));
[Authorize(Roles="SuperAdmin")][HttpPost("commission-rules")]public async Task<IActionResult> CreateRule(CreateCommissionRuleRequest request,CancellationToken ct)=>Result(await service.CreateCommissionRuleAsync(User.GetRequiredUserId(),request,ct));
[Authorize(Roles="SuperAdmin")][HttpPost("adjustments")]public async Task<IActionResult> Adjustment(CreateFinancialAdjustmentRequest request,CancellationToken ct)=>Result(await service.CreateAdjustmentAsync(User.GetRequiredUserId(),request,ct));
[Authorize(Roles="SuperAdmin")][HttpPost("reconcile-completed-trips")]public async Task<IActionResult> Reconcile(CancellationToken ct)=>Result(await service.ReconcileCompletedTripsAsync(User.GetRequiredUserId(),ct));
IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});}

[ApiController][Route("api/v1/driver/finance")][Authorize(Roles="Driver")]
public sealed class DriverFinanceController(FinanceService service):ControllerBase{
[HttpGet]public async Task<IActionResult> Mine(CancellationToken ct)=>Result(await service.DriverSummaryAsync(User.GetRequiredUserId(),ct));
[HttpPost("payouts")]public async Task<IActionResult> Payout(CreatePayoutRequest request,CancellationToken ct)=>Result(await service.CreatePayoutAsync(User.GetRequiredUserId(),request,ct));
IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});}
