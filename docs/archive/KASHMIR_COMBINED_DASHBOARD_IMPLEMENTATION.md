# Kashmir Combined Dashboard Implementation

Implemented in the Flutter unified mobile application.

## Customer dashboard
- Added a clear `Local Ride` / `Explore Kashmir` selector.
- Local Ride is the default for daily coaster, van, car and per-seat transport.
- Added travel-date selection directly in the primary search card.
- Search results now use the selected service and date.
- Added a prominent active-trip card beside the booking controls.
- Reduced the hero area so core booking controls remain easier to reach.
- Added live connectivity detection and an offline-mode notice.
- Offline notice explains that cached routes may be viewed and SMS confirmation will be needed when the SMS phase is enabled.
- Kept existing destination carousel, current-location lookup, vehicle filters, reviews, pickup points and live trip tracking.

## Driver dashboard
- Added an Online/Offline availability card at the top.
- Added next-trip route and departure information to the top card.
- Prioritized the next accepted trip before secondary dashboard content.
- Renamed the main creation action to `Create local route` / `Daily seat departure` for local operators.
- Changed the section label to `Quick actions` for simpler navigation.

## Offline/SMS readiness
- Connectivity detection is now part of the customer dashboard.
- UI clearly distinguishes offline state from a confirmed online booking.
- Existing connectivity_plus dependency is reused; no new package was added.
- Actual SMS gateway booking/confirmation remains a later backend integration because an SMS provider, receiving number and callback/webhook credentials are required.

## Files changed
- `udrive_unified_mobile/lib/screens/customer/customer_home_screen.dart`
- `udrive_unified_mobile/lib/screens/driver/driver_home_screen.dart`

## Validation note
The container did not include Flutter/Dart SDK, so a Flutter compile could not be run here. A structural delimiter check passed for both changed Dart files. The repository's existing custom validator still reports pre-existing issues in unrelated screens (`customer_operations_screen.dart`, `driver_requests_screen.dart`, `home_screen.dart`, and `explore_screen.dart`).
