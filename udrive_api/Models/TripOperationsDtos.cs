using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount, int TotalPages);
public sealed record OperationsSummaryDto(int Upcoming, int PendingAssignments, int AwaitingDriverResponse, int Active, int Completed, int Cancelled, int Emergency, int Disputed);
public sealed record OperationsBookingDto(Guid Id,string BookingReference,string CustomerName,string CustomerPhone,string? DriverName,string? DriverPhone,string? Vehicle,string? VehicleRegistration,string? PickupLabel,string? DestinationLabel,DateTimeOffset PickupAt,DateTimeOffset? ReturnAt,string BookingType,int PassengerCount,string PaymentStatus,string TripStatus,string OperationalStatus,DateTimeOffset LastActivityAt,bool Emergency);
public sealed record OperationsDashboardDto(OperationsSummaryDto Summary,PagedResult<OperationsBookingDto> Bookings);
public sealed record TripPersonDto(Guid Id,string FullName,string PhoneNumber,string? Email);
public sealed record TripVehicleDto(Guid Id,string Make,string Model,string RegistrationNumber,string Category,int PassengerCapacity,string Status);
public sealed record TripTimelineDto(string Status,string? PreviousStatus,string Source,string? Reason,string? ChangedBy,DateTimeOffset CreatedAt);
public sealed record TripNoteDto(Guid Id,string NoteType,string Note,string Author,bool IsCustomerVisible,DateTimeOffset CreatedAt);
public sealed record OperationsDriverOfferDto(Guid Id,Guid DriverProfileId,string DriverName,string? Vehicle,string Status,DateTimeOffset ExpiresAt,string? RejectionReason,string? OfferNotes,DateTimeOffset CreatedAt);
public sealed record TripOperationsDetailDto(OperationsBookingDto Booking,TripPersonDto Customer,TripPersonDto? Driver,TripVehicleDto? Vehicle,string? TourismPackage,decimal Fare,string? SpecialInstructions,string? EmergencyContact,IReadOnlyList<TripTimelineDto> Timeline,IReadOnlyList<TripNoteDto> Notes,IReadOnlyList<OperationsDriverOfferDto> Offers,int Version);
public sealed record SuitableDriverDto(Guid DriverProfileId,Guid UserId,string DriverName,string Phone,string VerificationStatus,bool IsOnline,int ActiveTrips,decimal Rating,string City,Guid? VehicleId,string? Vehicle,string? Registration,int? Capacity,string VehicleStatus,double? DistanceKm,bool Available,string? UnavailableReason);

public sealed record AssignTripRequest([Required] Guid DriverProfileId,[Required] Guid VehicleId,[StringLength(1000)] string? Notes,bool EmergencyReplacement=false);
public sealed record SendDriverBookingOfferRequest([Required] Guid DriverProfileId,[Required] Guid VehicleId,[Range(1,1440)] int ExpiresInMinutes=15,[StringLength(1000)] string? Notes=null);
public sealed record RespondDriverBookingOfferRequest([Required,RegularExpression("Accept|Reject")] string Decision,[StringLength(500)] string? RejectionReason);
public sealed record ChangeTripStatusRequest([Required,StringLength(40)] string Status,[StringLength(1000)] string? Reason,int? ExpectedVersion=null,bool Override=false,[StringLength(8)] string? TripOtp=null);
public sealed record AddTripNoteRequest([Required,StringLength(2000)] string Note,[StringLength(32)] string NoteType="Operational",bool IsCustomerVisible=false);
public sealed record RescheduleTripRequest([Required] DateTimeOffset PickupAt,DateTimeOffset? ReturnAt,[Required,StringLength(1000)] string Reason);
public sealed record RaiseIncidentRequest([Required,StringLength(64)] string IncidentType,[Required,StringLength(32)] string Severity,[Required,StringLength(4000)] string Description);
public sealed record ResolveIncidentRequest([Required,StringLength(2000)] string ResolutionNotes);

public sealed record DriverTripOfferDto(Guid OfferId,Guid BookingId,string BookingReference,string CustomerName,string PickupLabel,string DestinationLabel,DateTimeOffset PickupAt,int PassengerCount,string BookingType,string Vehicle,string RegistrationNumber,DateTimeOffset ExpiresAt,string? Notes);
public sealed record MobileTripDto(Guid BookingId,string BookingReference,string CustomerName,string CustomerPhone,string? DriverName,string? DriverPhone,string? Vehicle,string? RegistrationNumber,string PickupLabel,string DestinationLabel,DateTimeOffset PickupAt,DateTimeOffset? ReturnAt,int PassengerCount,string BookingType,decimal Fare,string PaymentStatus,string TripStatus,string OperationalStatus,string? Instructions,DateTimeOffset LastActivityAt);

public sealed record DriverLocationUpdateRequest([Required] Guid ClientEventId,[Required] Guid TripId,[Range(-90,90)] double Latitude,[Range(-180,180)] double Longitude,[Range(0,10000)] double? Accuracy,[Range(0,360)] double? Heading,[Range(0,400)] double? SpeedKph,DateTimeOffset DeviceTimestamp,[Range(0,100)] int? BatteryLevel,[StringLength(32)] string? PermissionStatus,[StringLength(64)] string? Source);
public sealed record LocationAcceptedDto(Guid ClientEventId,DateTimeOffset ServerTimestamp,bool Duplicate,bool Current,bool Stale);
public sealed record TrackingPointDto(double Latitude,double Longitude,double? Accuracy,double? Heading,double? SpeedKph,int? BatteryLevel,DateTimeOffset DeviceTimestamp,DateTimeOffset ServerTimestamp,bool Stale,bool Online,bool Emergency);
public sealed record TripTrackingDto(Guid BookingId,string BookingReference,string TripStatus,string PickupLabel,string DestinationLabel,double? PickupLatitude,double? PickupLongitude,double? DestinationLatitude,double? DestinationLongitude,string? DriverName,string? Vehicle,string? RegistrationNumber,TrackingPointDto? DriverLocation,IReadOnlyList<TrackingPointDto> RecentPath);
public sealed record ActiveTrackingListItemDto(Guid BookingId,string BookingReference,string DriverName,string Vehicle,string RegistrationNumber,string TripStatus,string City,DateTimeOffset? LastUpdate,bool Stale,bool Emergency,double? SpeedKph,double? Heading,double? Accuracy);
public sealed record CreateTrackingLinkRequest([Range(5,1440)] int ExpiresInMinutes=120);
public sealed record TrackingLinkDto(string Token,DateTimeOffset ExpiresAt);
