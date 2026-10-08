namespace UDrive.Api.Models;

/// <summary>Approved-page counts per tab (live + suspended) and open re-claims.</summary>
public sealed record ApprovedSummaryDto(
    int City, int Tour, int Rent, int Hotels, int Businesses, int Suspended, int ClaimsWaiting);

/// <param name="State">Live or Suspended.</param>
public sealed record ApprovedRowDto(
    VerificationRowDto Row,
    string State,
    string? HoldReason,
    DateTimeOffset? HeldAt,
    bool ClaimWaiting);

/// <param name="Key">A document type, e.g. REGISTRATION_BOOK.</param>
public sealed record HoldDocDto(string Key, string Label, bool Uploaded);

public sealed record HoldClaimDto(
    Guid Id,
    string Type,
    string Message,
    IReadOnlyList<string> Photos,
    string Status,
    string? AdminNote,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DecidedAt);

/// <summary>An open review / suspension, as the owner and the Admin see it.</summary>
/// <param name="Kind">city, tour, rent, hotels or businesses.</param>
/// <param name="Type">Review or Suspend.</param>
public sealed record HoldDto(
    Guid Id,
    string Kind,
    Guid EntityId,
    string Title,
    string Type,
    string Reason,
    IReadOnlyList<HoldDocDto> Documents,
    DateTimeOffset CreatedAt,
    string? CreatedBy,
    DateTimeOffset? SubmittedAt,
    HoldClaimDto? Claim);

public sealed record ApprovedDetailDto(
    VerificationDetailDto Detail,
    string State,
    HoldDto? Hold,
    IReadOnlyList<HoldDocDto> Requestable);

/// <param name="Documents">Document types to ask for again; empty = just look again.</param>
public sealed record HoldReviewRequest(string? Note, IReadOnlyList<string>? Documents);

public sealed record HoldNoteRequest(string? Note);
