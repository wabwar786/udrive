# Phase 11–12 API Endpoints

## Admin operations

- `GET /api/v1/admin/trip-operations`
- `GET /api/v1/admin/trip-operations/{bookingId}`
- `GET /api/v1/admin/trip-operations/{bookingId}/suitable-drivers`
- `POST /api/v1/admin/trip-operations/{bookingId}/assign`
- `POST /api/v1/admin/trip-operations/{bookingId}/offers`
- `PUT /api/v1/admin/trip-operations/{bookingId}/status`
- `POST /api/v1/admin/trip-operations/{bookingId}/notes`
- `PUT /api/v1/admin/trip-operations/{bookingId}/schedule`

## Driver and customer operations

- `GET /api/v1/trips/driver/offers`
- `PUT /api/v1/trips/driver/offers/{offerId}`
- `GET /api/v1/trips/driver/my`
- `GET /api/v1/trips/customer/my`
- `PUT /api/v1/trips/{bookingId}/driver-status`
- `PUT /api/v1/trips/{bookingId}/customer-status`
- `GET /api/v1/trips/{bookingId}/tracking`
- `POST /api/v1/trips/{bookingId}/tracking-link`
- `DELETE /api/v1/trips/{bookingId}/tracking-link`

## Tracking

- `POST /api/v1/tracking/driver/location`
- `GET /api/v1/tracking/admin/active`
- `GET /api/v1/tracking/admin/{bookingId}`
- `GET /api/v1/public/tracking/{token}`

Admin endpoints require SuperAdmin/Admin/Manager/Operations. Private mobile endpoints require authentication and booking ownership/assignment.
