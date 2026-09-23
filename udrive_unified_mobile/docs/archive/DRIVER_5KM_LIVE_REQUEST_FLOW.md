# Driver 5 KM Live Request Flow

## Driver home
- Driver mode starts online by default.
- GPS presence publishes immediately and every 15 seconds while online.
- Nearby ride marketplace refreshes every 5 seconds.
- API returns only approved-driver requests whose pickup is within 5,000 metres of the driver's latest server-side GPS presence.

## Instant City-to-City compatibility
- Instant requests remain eligible for driver discovery for up to 15 minutes rather than being closed as soon as pickupAt reaches the current time.
- Driver offers for instant rides remain valid during the offer window instead of expiring immediately at pickupAt.

## Request card
- Pickup and destination
- Customer estimated fare
- Clear WHOLE VEHICLE or N SEAT badge
- Map button for pickup/destination preview
- Reject and Accept actions

## Accept
- App automatically chooses a compatible verified vehicle belonging to the driver.
- Driver is asked only for their fare.
- ETA and message are not customer-facing inputs in this simplified flow.
- Fare is submitted to the existing marketplace and customer auto-matching continues.
