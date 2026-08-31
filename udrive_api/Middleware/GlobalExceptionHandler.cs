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
