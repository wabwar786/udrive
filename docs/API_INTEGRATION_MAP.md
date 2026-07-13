# API Integration Map

The Phase 1 source uses in-memory dummy data. Replace each data file with a repository implementation later.

## Customer endpoints

- `POST /auth/request-otp`
- `POST /auth/verify-otp`
- `POST /ride-requests`
- `GET /ride-requests/{id}/offers`
- `POST /ride-requests/{id}/select-driver`
- `GET /tour-packages`
- `GET /tour-packages/{id}`
- `POST /tour-packages/{id}/offers`
- `GET /customers/me/trips`

## Driver endpoints

- `GET /drivers/me/ride-requests`
- `POST /ride-requests/{id}/accept`
- `POST /ride-requests/{id}/counteroffer`
- `GET /drivers/me/packages`
- `POST /drivers/me/packages`
- `PUT /drivers/me/packages/{id}`
- `POST /drivers/me/packages/{id}/submit`
- `GET /drivers/me/earnings`

## Admin endpoints

- `GET /admin/dashboard`
- `GET /admin/packages?status=pending`
- `POST /admin/packages/{id}/approve`
- `POST /admin/packages/{id}/request-changes`
- `GET /admin/live-operations`
- `GET /admin/drivers/pending-verification`
