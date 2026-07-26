# Customer → Driver Marketplace Consolidated Fix

Apply this ZIP over the latest uDrive source tree. It intentionally includes the complete current versions of the five affected files so older hotfixes are not reintroduced.

## Fixes

- Adds editable **Customer offered fare (PKR)** on booking review.
- Saves that exact offer in `udrive.ride_requests.customer_offer`.
- Adds a prominent **Open customer requests** card on Driver Home.
- Loads open ride requests independently from package APIs.
- Accepts both `Approved` and `Verified` legacy statuses for Drivers/vehicles.
- Removes invalid `vehicles.is_active` dependency from Driver eligibility SQL.
- Keeps ride requests active for one hour.
- Repairs `pickupAt` scope and offer-expiry calculation.
- Makes customer offer reads tolerant of missing/null display information.

## Deployment

1. Overlay all files.
2. Deploy API first.
3. Confirm `/health/live` and `/health/ready` return HTTP 200.
4. Deploy Flutter web.
5. Log out and sign in once on both Customer and Driver browsers.
6. Customer creates a future request and enters a fare.
7. Driver `03109000001` opens Driver Home → Open customer requests.

## API checks

Customer:
- `POST /api/v1/bookings/ride-requests`
- `GET /api/v1/bookings/ride-requests/{id}/offers`

Driver:
- `GET /api/v1/driver/marketplace/ride-requests`
- `POST /api/v1/driver/marketplace/ride-requests/{id}/offers`
