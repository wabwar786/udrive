using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using UDrive.Api.Common;
using UDrive.Api.Infrastructure.Persistence;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/system")]
public sealed class SystemController(UDriveDbContext db) : ControllerBase
{
    [HttpGet("status")]
    public async Task<ActionResult<ApiResponse<object>>> GetStatus(CancellationToken cancellationToken)
    {
        var databaseAvailable = await db.Database.CanConnectAsync(cancellationToken);
        var data = new
        {
            service = "udrive-api",
            phase = 7,
            database = databaseAvailable ? "connected" : "unavailable",
            spatialDatabase = "PostgreSQL + PostGIS",
            utcTime = DateTimeOffset.UtcNow,
            traceId = HttpContext.TraceIdentifier
        };

        return Ok(ApiResponse<object>.Ok(data));
    }
}
