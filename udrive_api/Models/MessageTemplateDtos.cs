using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

/// <summary>One WhatsApp message the platform sends, as Admin edits it.</summary>
public sealed record MessageTemplateDto(
    string Key,
    string Title,
    string Audience,
    string Description,
    IReadOnlyList<string> Placeholders,
    string Body,
    string DefaultBody,
    bool IsActive,
    DateTimeOffset UpdatedAt,
    int SentLast7Days,
    int FailedLast7Days);

public sealed record UpdateMessageTemplateRequest(
    [Required, StringLength(1000, MinimumLength = 1)] string Body,
    bool IsActive);
