# uDrive API — Phase 7

Production-oriented backend foundation for the uDrive Kashmir tourism application.

## Stack

- ASP.NET Core 10 LTS
- PostgreSQL 17
- PostGIS 3.5
- EF Core 10 with Npgsql and NetTopologySuite
- Embedded, ordered SQL migrations
- Railway Docker deployment
- Swagger/OpenAPI
- Readiness and liveness health checks

## Local run

```bash
docker compose up --build
```

Open:

- API: `http://localhost:8080/api/v1/system/status`
- Swagger: `http://localhost:8080/swagger`
- Liveness: `http://localhost:8080/health/live`
- Readiness: `http://localhost:8080/health/ready`

## Current endpoints

- `GET /api/v1/system/status`
- `GET /api/v1/catalog/destinations?language=en`
- `GET /api/v1/catalog/routes`
- `GET /api/v1/catalog/packages`

## Database migrations

SQL files inside `Infrastructure/Persistence/Migrations` are embedded in the API assembly and applied in filename order. Applied migration IDs are recorded in `public.schema_migrations`.

Set `AUTO_APPLY_MIGRATIONS=false` to disable startup migrations.
