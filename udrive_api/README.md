# uDrive API — Phase 8

Live authentication and verification backend for the uDrive Kashmir tourism application.

## Stack

- ASP.NET Core 10
- PostgreSQL 17 + PostGIS 3.5
- EF Core/Npgsql
- JWT access tokens and rotating refresh tokens
- Server-side OTP challenges
- Driver and vehicle verification
- Protected verification-file storage
- Railway Docker deployment
- Swagger/OpenAPI and health checks

## Phase 8 endpoints

### Authentication

- `POST /api/v1/auth/otp/request`
- `POST /api/v1/auth/otp/verify`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/logout`

### Driver onboarding

- `GET /api/v1/driver/onboarding`
- `PUT /api/v1/driver/onboarding`
- `POST /api/v1/driver/onboarding/submit`
- `GET /api/v1/driver/documents`
- `POST /api/v1/driver/documents`
- `GET /api/v1/driver/vehicles`
- `POST /api/v1/driver/vehicles`
- `PUT /api/v1/driver/vehicles/{vehicleId}`
- `POST /api/v1/driver/vehicles/{vehicleId}/documents`
- `POST /api/v1/driver/vehicles/{vehicleId}/submit`

### Admin verification

- `GET /api/v1/admin/verification/drivers`
- `GET /api/v1/admin/verification/drivers/{driverProfileId}`
- `PUT /api/v1/admin/verification/drivers/{driverProfileId}`
- `GET /api/v1/admin/verification/vehicles`
- `GET /api/v1/admin/verification/vehicles/{vehicleId}`
- `PUT /api/v1/admin/verification/vehicles/{vehicleId}`
- `GET /api/v1/admin/verification/files/{category}/{owner}/{fileName}`

## Development test accounts

- Approved Driver: `03000000001`, OTP `1234`
- Admin: `03000000099`, OTP `1234`
- New Customer: any valid Pakistani mobile number, OTP `1234`

The fixed OTP provider is for staging/testing only. Configure a real SMS provider before a public launch.

## Required Railway variables

Copy values from `.env.phase8.example`. Replace all signing/hash secrets with strong independent random values.

Attach a persistent volume to the API service:

```text
Mount path: /data/uploads
UPLOAD_ROOT=/data/uploads
```

## Database migrations

Embedded SQL migrations are applied in filename order. Phase 8 is migration:

```text
004_phase8_authentication_and_verification.sql
```

Applied migration IDs are recorded in `public.schema_migrations`.
