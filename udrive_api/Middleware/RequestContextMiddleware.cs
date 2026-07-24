namespace UDrive.Api.Middleware;

public sealed class RequestContextMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var requestId = context.Request.Headers.TryGetValue("X-Request-Id", out var supplied)
            ? supplied.ToString()
            : Guid.NewGuid().ToString("N");

        context.TraceIdentifier = requestId;
        context.Response.Headers["X-Request-Id"] = requestId;
        await next(context);
    }
}
