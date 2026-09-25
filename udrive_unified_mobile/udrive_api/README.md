# Udrive API — Phase 8

Live authentication and verification backend for the Udrive Kashmir tourism application.

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

Seeded users (`003_seed_catalog.sql`, `004_phase8_authentication_and_verification.sql`):

- Approved Driver: `03000000001` — "Adeel Khan", vehicle `AJK-DEMO-01`
- SuperAdmin: `03000000099`
- Any other valid Pakistani mobile number creates a Customer on first verify

**Which code works depends on the provider, not on the account.**

- Provider `Development` — *every* number on the platform accepts
  `DEVELOPMENT_OTP_CODE` (default `1234`) and nothing is sent. This is a
  staging-only mode: with it on, anyone who knows the code can sign in as
  anyone. Never leave it on for a deployment real users can reach.
- Provider `WhatsApp` — a random 4-digit code goes out over WA Engine, and only
  the reviewer number below bypasses it.

The reviewer number (`otp.test.phone` / `otp.test.code`, set under Services →
WhatsApp OTP in the admin portal, SuperAdmin only) accepts its fixed code under
*any* provider and sends nothing. For the Play Store submission it is set to
`03000000001` / `5095`.

Note that `OTP_PROVIDER_OVERRIDE` beats the database setting, and that an
unrecognised provider value falls back to `Development` silently — so
`OTP_PROVIDER=ProductionProvider` means the fixed code is live. Check the
portal, which states the effective provider, rather than the variable.

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

## Phase 9 — Live Booking Marketplace

Phase 9 adds database-backed advance ride requests, Driver offers, transactional offer selection, live bookings, tourism package approval, ten-minute seat holds, whole-vehicle locking, package negotiation, passenger manifests, waiting lists and tour-interest matching.

For development testing add:

```env
ENABLE_DEMO_MARKETPLACE=true
```

Swagger contains all Phase 9 endpoints after migration `005_phase9_live_booking_marketplace` is applied.
