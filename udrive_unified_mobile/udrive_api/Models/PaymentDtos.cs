using System.ComponentModel.DataAnnotations;
namespace UDrive.Api.Models;
public sealed record BookingPaymentSummaryDto(Guid BookingId,string BookingReference,decimal TotalAmount,decimal PaidAmount,decimal RefundedAmount,decimal RemainingAmount,string Currency,IReadOnlyList<PaymentRecordDto> Payments);
public sealed record PaymentRecordDto(Guid Id,string Method,string PaymentType,decimal Amount,string Currency,string Status,string? Provider,string? ProviderReference,string? FailureReason,DateTimeOffset CreatedAt,DateTimeOffset? PaidAt);
public sealed record CreateBookingPaymentRequest(Guid BookingId,[Required,StringLength(40)] string Method,[Required,StringLength(32)] string PaymentType,[Range(1,100000000)] decimal Amount,[Required,StringLength(120)] string IdempotencyKey);
public sealed record ConfirmBookingPaymentRequest([Required,StringLength(32)] string Status,[StringLength(160)] string? ProviderReference,[StringLength(500)] string? FailureReason);
public sealed record PayoutAccountDto(Guid Id,string Method,string AccountTitle,string AccountIdentifierMasked,string? BankName,bool IsDefault,bool IsVerified);
public sealed record SavePayoutAccountRequest([Required,StringLength(40)] string Method,[Required,StringLength(160)] string AccountTitle,[Required,StringLength(200)] string AccountIdentifier,[StringLength(120)] string? BankName,bool IsDefault);
public sealed record WalletFreezeRequest(bool IsFrozen,[StringLength(500)] string? Reason,int ExpectedVersion);
