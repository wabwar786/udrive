using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace UDrive.Api.Middleware;

public sealed class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger,
    IProblemDetailsService problemDetailsService) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        var (status, title, detail) = exception switch
        {
            InvalidDataException invalidData => (
                StatusCodes.Status400BadRequest,
                "Invalid file or request data.",
                invalidData.Message),
            UnauthorizedAccessException => (
                StatusCodes.Status401Unauthorized,
                "Authentication is required.",
                "The current session is not authorized for this action."),
            // A CHECK violation is a disagreement between the code and the
            // schema, not a user mistake. It used to fall into the catch-all
            // 500 — which is how a constraint that forbade the value every
            // accept wrote ('Accepted' on driver_ride_request_decisions, see
            // migration 039) hid for weeks behind "temporarily unavailable".
            // Naming the constraint in the response makes the next one a
            // one-minute fix instead of a hunt.
            PostgresException { SqlState: PostgresErrorCodes.CheckViolation } check => (
                StatusCodes.Status409Conflict,
                "The request conflicts with a data rule.",
                $"Constraint '{check.ConstraintName ?? "unknown"}' on "
                + $"'{check.TableName ?? "unknown"}' rejected this value."),
            PostgresException { SqlState: PostgresErrorCodes.ForeignKeyViolation } fk => (
                StatusCodes.Status409Conflict,
                "A referenced record is missing.",
                $"Constraint '{fk.ConstraintName ?? "unknown"}' on "
                + $"'{fk.TableName ?? "unknown"}' could not be satisfied."),
            PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } => (
                StatusCodes.Status409Conflict,
                "The submitted record already exists.",
                "A CNIC, licence number, registration number or another unique value is already registered."),
            _ => (
                StatusCodes.Status500InternalServerError,
                "An unexpected error occurred.",
                "This service is temporarily unavailable. Please try again shortly.")
        };

        if (status >= 500)
        {
            logger.LogError(exception, "Unhandled API exception. TraceId: {TraceId}", httpContext.TraceIdentifier);
        }
        else
        {
            logger.LogWarning(exception, "Rejected API request. TraceId: {TraceId}", httpContext.TraceIdentifier);
        }

        // Put the CORS headers back before writing the error.
        //
        // `UseExceptionHandler` sits outside `UseCors` in the pipeline and
        // clears the response before an error is written, which strips the
        // `Access-Control-Allow-Origin` header the CORS middleware had already
        // set. The browser then refuses to read the response at all and reports
        // a generic network failure — Safari says only "Load failed" — so every
        // server-side error on the web app looked like the API was unreachable
        // rather than like the specific problem it was.
        //
        // Re-added here rather than by moving middleware, because the handler is
        // the thing that clears them and is the only place that knows they need
        // restoring.
        var origin = httpContext.Request.Headers.Origin.ToString();
        if (!string.IsNullOrWhiteSpace(origin)
            && !httpContext.Response.Headers.ContainsKey("Access-Control-Allow-Origin"))
        {
            httpContext.Response.Headers["Access-Control-Allow-Origin"] = origin;
            httpContext.Response.Headers["Vary"] = "Origin";
        }

        httpContext.Response.StatusCode = status;
        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = new ProblemDetails
            {
                Status = status,
                Title = title,
                Detail = detail,
                Extensions = { ["traceId"] = httpContext.TraceIdentifier }
            },
            Exception = exception
        });
    }
}
