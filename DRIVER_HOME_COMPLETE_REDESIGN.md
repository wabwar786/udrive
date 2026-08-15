# Driver Home Complete Redesign — 15 Aug 2026

## Home screen focus
Driver Home is now an operations-first dashboard. It focuses on Active Ride, Nearby Ride Requests, and My Fare Offers / customer approval status. Unrelated quick-action/package sections are removed from the home feed.

## Live nearby requests
- Driver presence is published every 15 seconds while online.
- Nearby marketplace requests refresh every 5 seconds.
- Backend keeps the existing PostGIS 5 KM pickup-radius eligibility rule.
- New rides appear automatically; manual search is not required.

## Fare workflow
- Request card shows customer, pickup, destination, customer estimate, Single Seat / seat count or Whole Vehicle, and Map.
- Driver taps accept and enters only their PKR fare; compatible verified vehicle is selected automatically.
- Sent fares stay visible on Driver Home through the new `GET /api/v1/driver/marketplace/ride-offers` endpoint.
- Offer status is shown as Waiting for Customer, Approved, or Closed / Not Selected.

## Active ride
When the customer selects the driver's offer, the accepted booking appears as an Active Ride card on Driver Home with route, customer, fare, trip status and Open live ride action.

## Next-ride rule
During an assigned ride, new marketplace requests are blocked. During `TripStarted`, requests unlock only once the driver's live presence is within 1 KM of the current ride destination. After unlock, the normal 5 KM pickup-radius rule still applies.
