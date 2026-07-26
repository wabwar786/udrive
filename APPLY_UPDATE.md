# uDrive Driver Home Premium Update

## What this update changes

- Driver dashboard header now uses a time-based greeting and profile icon.
- Online/offline control is placed in the top application bar.
- Large hero, metric blocks and vehicle-readiness section are removed.
- Pending Customer requests are shown first in compact premium cards.
- Accept opens a verified-vehicle and fare-offer sheet.
- Reject hides the request only for the current Driver; other Drivers may still respond.
- Customer name and initials are returned from the live database.
- Latest assignment uses a new compact card.
- Four Driver tools use colorful action cards.
- Create Package is available directly from Driver Home.
- Driver-created packages and approval status are shown on Home.

## Apply order

1. Overlay all files in this ZIP onto the latest project.
2. Deploy the API first.
3. Confirm migration `012_driver_request_decisions.sql` was applied.
4. Confirm `/health/live` and `/health/ready` return HTTP 200.
5. Confirm Swagger includes:
   - `POST /api/v1/driver/marketplace/ride-requests/{rideRequestId}/reject`
6. Deploy Flutter web.
7. Logout/login once as Driver and hard refresh/clear the service worker cache.

## Driver test account

- Phone: `03109000001`
- Development OTP: `1234`

## Expected Driver flow

1. Customer submits a ride request with offered fare.
2. Driver Home shows the request at the top.
3. Driver taps green Accept.
4. Driver chooses a verified vehicle, edits fare and ETA, and sends the offer.
5. Request disappears from that Driver's pending queue.
6. Customer receives the Driver offer.
7. Red Reject removes the request only from the current Driver's queue.
