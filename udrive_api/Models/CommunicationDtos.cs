namespace UDrive.Api.Models;

public sealed record NotificationDto(Guid Id,string Type,string Title,string Body,string? ActionPath,bool IsRead,DateTimeOffset CreatedAt);
public sealed record NotificationPageDto(IReadOnlyList<NotificationDto> Items,int UnreadCount);
public sealed record NotificationPreferencesDto(bool BookingAlerts,bool PackageAlerts,bool PayoutAlerts,bool ComplaintAlerts,bool PromotionalAlerts,bool PushEnabled,bool SmsEnabled);
public sealed record RegisterDeviceRequest(string DeviceToken,string Platform,string? DeviceName);
public sealed record BookingMessageDto(Guid Id,Guid BookingId,Guid SenderUserId,string SenderName,string Body,bool IsMine,bool IsRead,DateTimeOffset SentAt);
public sealed record SendBookingMessageRequest(string Body);
public sealed record WhatsAppLocationShareRequest(string To,string? ContactName,double Latitude,double Longitude);
public sealed record WhatsAppSendResultDto(bool Sent,string? ProviderMessageId);
