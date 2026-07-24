namespace UDrive.Api.Domain.Enums;

public enum UserRole { Customer, Driver, Admin, Operations, Safety, Finance, Support }
public enum AccountStatus { Draft, Submitted, UnderReview, ChangesRequired, Approved, Suspended, Rejected }
public enum VehicleStatus { Draft, PendingReview, ChangesRequired, Verified, Suspended, Expired }
public enum BookingType { PerSeat, WholeVehicle }
public enum BookingStatus { Draft, Pending, Confirmed, DriverAssigned, InProgress, Completed, Cancelled, Disputed }
public enum PackageStatus { Draft, PendingApproval, ChangesRequired, Approved, Active, Paused, Rejected, Suspended, Expired }
public enum RideRequestStatus { Open, ReceivingOffers, DriverSelected, Confirmed, Cancelled, Expired }
public enum OfferStatus { Pending, Accepted, Countered, Rejected, Expired, Withdrawn, Selected }
public enum IncidentSeverity { Information, Caution, High, Critical }
public enum PaymentStatus { Pending, Authorized, Paid, Failed, Refunded, PartiallyRefunded }
