# Phase 9 API Endpoints

## Customer rides

```text
POST /api/v1/bookings/ride-requests
GET  /api/v1/bookings/ride-requests/my
GET  /api/v1/bookings/ride-requests/{id}/offers
POST /api/v1/bookings/ride-requests/{id}/offers/{offerId}/select
GET  /api/v1/bookings/my
POST /api/v1/bookings/{id}/cancel
PUT  /api/v1/bookings/{id}/reschedule
GET  /api/v1/bookings/{id}/history
```

## Driver marketplace

```text
GET  /api/v1/driver/marketplace/ride-requests
POST /api/v1/driver/marketplace/ride-requests/{id}/offers
GET  /api/v1/driver/marketplace/packages
POST /api/v1/driver/marketplace/packages
PUT  /api/v1/driver/marketplace/packages/{id}
POST /api/v1/driver/marketplace/packages/{id}/submit
POST /api/v1/driver/marketplace/packages/{id}/pause
POST /api/v1/driver/marketplace/packages/{id}/activate
GET  /api/v1/driver/marketplace/packages/bookings
GET  /api/v1/driver/marketplace/packages/offers
PUT  /api/v1/driver/marketplace/packages/offers/{id}
GET  /api/v1/driver/marketplace/packages/waitlist
GET  /api/v1/driver/marketplace/bookings/{id}/passengers
```

## Public and Customer packages

```text
GET  /api/v1/packages
GET  /api/v1/packages/{id}
GET  /api/v1/packages/{id}/availability
POST /api/v1/packages/{id}/holds
POST /api/v1/packages/{id}/bookings
POST /api/v1/packages/{id}/offers
GET  /api/v1/packages/offers/my
POST /api/v1/packages/offers/{id}/confirm
POST /api/v1/packages/{id}/waitlist
GET  /api/v1/packages/waitlist/my
```

## Tour matching

```text
POST /api/v1/tour-interests
GET  /api/v1/tour-interests/my
GET  /api/v1/tour-interests/matches
PUT  /api/v1/tour-interests/{id}/active
```

## Admin package approval

```text
GET /api/v1/admin/packages/pending
PUT /api/v1/admin/packages/{id}/review
```
