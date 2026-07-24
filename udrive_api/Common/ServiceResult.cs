using Microsoft.AspNetCore.Http;

namespace UDrive.Api.Common;

public sealed record ServiceResult<T>(
    bool Success,
    int StatusCode,
    T? Data,
    string? ErrorCode,
    string? Message)
{
    public static ServiceResult<T> Ok(T data, string? message = null) =>
        new(true, StatusCodes.Status200OK, data, null, message);

    public static ServiceResult<T> Created(T data, string? message = null) =>
        new(true, StatusCodes.Status201Created, data, null, message);

    public static ServiceResult<T> Fail(
        int statusCode,
        string errorCode,
        string message) =>
        new(false, statusCode, default, errorCode, message);
}
