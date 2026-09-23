namespace UDrive.Api.Models;

public sealed record ExecutiveMetricDto(string Label, decimal Value, decimal PreviousValue, decimal ChangePercent, string Tone);
public sealed record ExecutiveDashboardDto(
    IReadOnlyList<ExecutiveMetricDto> Metrics,
    IReadOnlyDictionary<string,int> BookingStatuses,
    IReadOnlyDictionary<string,int> ActionQueues,
    IReadOnlyList<ExecutiveActivityDto> RecentActivity);
public sealed record ExecutiveActivityDto(string Type,string Title,string Subtitle,string Status,DateTimeOffset OccurredAt);
public sealed record LiveOperationDto(Guid BookingId,string Reference,string BookingType,string Status,string Customer,string? Driver,string? Vehicle,string? Registration,string Route,DateTimeOffset PickupAt,double? Latitude,double? Longitude,DateTimeOffset? LastLocationAt,bool IsStale,bool HasEmergency);
public sealed record AdminBookingRowDto(Guid Id,string Reference,string BookingType,string Status,string Customer,string? Driver,string? Vehicle,string Route,int Seats,decimal Total,decimal Paid,decimal Remaining,DateTimeOffset PickupAt,DateTimeOffset CreatedAt);
public sealed record FinanceReconciliationDto(decimal GrossBookingValue,decimal Collected,decimal Refunded,decimal Commission,decimal DriverEarnings,decimal PaidOut,decimal Outstanding,decimal Difference,IReadOnlyList<FinanceMismatchDto> Mismatches);
public sealed record FinanceMismatchDto(Guid BookingId,string Reference,decimal BookingTotal,decimal Collected,decimal Refunded,decimal DriverEarning,decimal Difference);
public sealed record ReportRowDto(string Period,int Bookings,int Completed,int Cancelled,decimal GrossValue,decimal Collected,decimal Commission,decimal DriverEarnings,decimal Refunds);
public sealed record DiagnosticsDto(string ApiStatus,string DatabaseStatus,string LatestMigration,int PendingMigrations,int FailedNotifications,int StaleTrackingTrips,int OpenEmergencies,int OpenDisputes,DateTimeOffset CheckedAt);
public sealed record AuditRowDto(Guid Id,string? Actor,string Action,string EntityType,string EntityId,string Changes,DateTimeOffset CreatedAt);
