# API and Flutter Testing Checklist

1. Login as a Customer and create a ride request.
2. Verify `expiresAt` is approximately one hour after `createdAt` in `GET /api/v1/bookings/ride-requests/my`.
3. Login as an approved Driver with a verified vehicle.
4. Verify the request appears in `GET /api/v1/driver/marketplace/ride-requests`.
5. Verify Driver dashboard displays the Customer fare and countdown.
6. Submit an offer with `POST /api/v1/driver/marketplace/ride-requests/{id}/offers`.
7. Verify the Customer sees the offer and can select it.
8. Create another request and do not submit an offer. After expiry, call the Customer or Driver request endpoint and verify status `NoDriverAccepted`.
9. Verify a request dated before the current Pakistan date does not appear in the Driver queue and becomes `Expired`.
10. Verify an unapproved Driver or Driver without a verified suitable vehicle cannot send an offer.
11. Verify a vehicle with insufficient seats is not selectable in the offer sheet.
