using Microsoft.AspNetCore.Authorization;using Microsoft.AspNetCore.Mvc;using UDrive.Api.Common;using UDrive.Api.Models;using UDrive.Api.Security;using UDrive.Api.Services;
namespace UDrive.Api.Controllers;
[ApiController][Route("api/v1/payments")][Authorize]
public sealed class PaymentsController(PaymentService service):ControllerBase{
[HttpGet("booking/{bookingId:guid}")]public async Task<IActionResult> Summary(Guid bookingId,CancellationToken ct)=>Result(await service.BookingSummaryAsync(User.GetRequiredUserId(),User.IsInRole("SuperAdmin")||User.IsInRole("Admin")||User.IsInRole("FinanceOfficer"),bookingId,ct));
[HttpPost]public async Task<IActionResult> Create(CreateBookingPaymentRequest request,CancellationToken ct)=>Result(await service.CreateAsync(User.GetRequiredUserId(),false,request,ct));
[Authorize(Roles="SuperAdmin,Admin,FinanceOfficer")][HttpPut("{paymentId:guid}/confirm")]public async Task<IActionResult> Confirm(Guid paymentId,ConfirmBookingPaymentRequest request,CancellationToken ct)=>Result(await service.ConfirmAsync(User.GetRequiredUserId(),paymentId,request,ct));
IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});}
[ApiController][Route("api/v1/driver/payout-accounts")][Authorize(Roles="Driver")]
public sealed class DriverPayoutAccountsController(PaymentService service):ControllerBase{
[HttpGet]public async Task<IActionResult> List(CancellationToken ct)=>Result(await service.AccountsAsync(User.GetRequiredUserId(),ct));
[HttpPost]public async Task<IActionResult> Save(SavePayoutAccountRequest request,CancellationToken ct)=>Result(await service.SaveAccountAsync(User.GetRequiredUserId(),request,ct));
IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});}
