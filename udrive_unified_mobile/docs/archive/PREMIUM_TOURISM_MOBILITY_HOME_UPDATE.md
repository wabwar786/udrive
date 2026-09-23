# Premium Tourism + Mobility Home Update

Implemented the approved dark Kashmir tourism and ride-hailing home-screen direction.

## Customer home screen
- Map-first Kashmir hero with tourism branding and destination pins.
- Professional pickup address bubble using reverse geocoding.
- Ride planner with readable pickup address and destination action.
- Vehicle selection carousel using live marketplace data with bundled artwork fallbacks.
- Tourism destination cards.
- Local experiences and stays cards.
- Existing incoming-driver tracking remains available.
- Existing refresh and live marketplace behavior remains intact.

## Address behavior
- Current latitude/longitude is reverse-geocoded to a readable street/locality/city/region/country address.
- Coordinates remain available internally for API and map use.
- Advance booking's readable-address update remains included.

## Main changed file
- `udrive_unified_mobile/lib/screens/customer/customer_home_screen.dart`
