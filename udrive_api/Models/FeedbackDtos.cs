namespace UDrive.Api.Models;

public sealed record SubmitRatingRequest(Guid BookingId,int OverallRating,int? DrivingRating,int? BehaviourRating,int? CleanlinessRating,int? PunctualityRating,int? CommunicationRating,string? ReviewText);
public sealed record RatingDto(Guid Id,Guid BookingId,string BookingReference,Guid ReviewerUserId,string ReviewerName,Guid RevieweeUserId,string RevieweeName,string ReviewerRole,int OverallRating,int? DrivingRating,int? BehaviourRating,int? CleanlinessRating,int? PunctualityRating,int? CommunicationRating,string? ReviewText,DateTimeOffset CreatedAt);
public sealed record RatingSummaryDto(Guid UserId,decimal AverageRating,int RatingCount,IReadOnlyList<RatingDto> RecentRatings);
public sealed record EligibleRatingBookingDto(Guid BookingId,string BookingReference,string OtherPartyName,string Role,DateTimeOffset PickupAt,decimal TotalAmount,bool AlreadyRated);

public sealed record CreateDisputeCaseRequest(Guid? BookingId,string Category,string Priority,string Subject,string Description,string? RequestedResolution,decimal? DisputedAmount);
public sealed record UpdateCaseRequest(string Status,string? ResolutionSummary,int ExpectedVersion);
public sealed record AssignCaseRequest(Guid? AssignedAdminUserId,int ExpectedVersion);
public sealed record AddCaseEventRequest(string Message,bool IsInternal,string EventType="Note");
public sealed record DisputeEvidenceDto(Guid Id,string FileUrl,string FileName,string ContentType,long FileSize,string? Description,DateTimeOffset CreatedAt);
public sealed record DisputeCaseEventDto(Guid Id,Guid? ActorUserId,string? ActorName,string EventType,bool IsInternal,string Message,DateTimeOffset CreatedAt);
public sealed record DisputeCaseDto(Guid Id,string CaseReference,Guid? BookingId,string? BookingReference,Guid OpenedByUserId,string OpenedByName,Guid? AgainstUserId,string? AgainstUserName,string Category,string Priority,string Subject,string Description,string? RequestedResolution,decimal? DisputedAmount,string Status,Guid? AssignedAdminUserId,string? AssignedAdminName,string? ResolutionSummary,int Version,DateTimeOffset CreatedAt,DateTimeOffset? ResolvedAt,IReadOnlyList<DisputeEvidenceDto>? Evidence=null,IReadOnlyList<DisputeCaseEventDto>? Events=null);
public sealed record DisputeDashboardDto(int Open,int InReview,int AwaitingResponse,int Resolved,int Urgent);

public sealed record CaseActionRequest(string ActionType,Guid? TargetUserId,string Reason,decimal? Amount);
