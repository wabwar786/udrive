namespace UDrive.Api.Common;

public sealed record ApiResponse<T>(bool Success, T Data, string? Message = null)
{
    public static ApiResponse<T> Ok(T data, string? message = null) => new(true, data, message);
}
