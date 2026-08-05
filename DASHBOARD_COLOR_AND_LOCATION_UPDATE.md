# Dashboard Color, Simplicity and Location Update

## Implemented
- Applied the Local Ride selected navy (`#10212B`) with lime accent (`#8ED12B`) as the global Flutter app theme.
- Updated older green/teal hardcoded theme accents to the same navy/lime system.
- Local Ride now displays only From and To fields.
- Travel date is displayed only in Explore Kashmir mode.
- Local Ride searches upcoming matching rides without requiring a date.
- Removed upcoming-destination chips, half-booked strip, vehicle-type panel and booking-history strip from the main dashboard flow.
- Reduced dashboard/hero height and visual density.
- Kept active trip prominent without adding unrelated dashboard blocks.
- Improved automatic pickup detection with permission handling, current-position lookup, last-known-position fallback and coordinate fallback.
- Added clearer pickup-field messages when device location or permission is unavailable.

## Location requirement
On Flutter Web, browser location works only on HTTPS or localhost and the user must allow location permission. Android and iOS location permissions are already present in the project.
