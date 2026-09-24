namespace UDrive.Api.Domain.Enums;

public enum UserRole { Customer, Driver, Admin, Operations, Safety, Finance, Support }
public enum AccountStatus { Draft, Submitted, UnderReview, ChangesRequired, Approved, Suspended, Rejected }
public enum VehicleStatus { Draft, PendingReview, ChangesRequired, Verified, Suspended, Expired }
public enum BookingType { PerSeat, WholeVehicle }
// DriverAccepted is the status a marketplace booking is actually created with
// (BookingService.SelectDriverOffer writes it to bookings.status and to
// trip_operations.trip_status). It was missing from this enum for a long time
// while the columns are plain varchar, so nothing caught it and three separate
// "is a ride running?" checks silently failed to recognise it.
public enum BookingStatus { Draft, SearchingDrivers, ReceivingOffers, DriverSelected, DriverAccepted, Pending, Confirmed, DriverAssigned, DriverEnRoute, DriverArrived, InProgress, Completed, Cancelled, NoShow, Disputed }
public enum PackageStatus { Draft, PendingApproval, ChangesRequired, Approved, Active, Paused, Rejected, Suspended, Expired }
public enum RideRequestStatus { Draft, Open, SearchingDrivers, ReceivingOffers, DriverSelected, Confirmed, Cancelled, NoDriverAccepted, Expired }
public enum OfferStatus { Pending, Accepted, Countered, Rejected, Expired, Withdrawn, Selected }
public enum IncidentSeverity { Information, Caution, High, Critical }
public enum PaymentStatus { Pending, Authorized, Paid, Failed, Refunded, PartiallyRefunded }
