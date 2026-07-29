# Customer Location Priority UI Update

Updated customer-facing listings so route/location is the primary visual hierarchy.

## Updated screens
- Customer Home scheduled vehicle cards
- View All Vehicles (shared scheduled vehicle card)
- Tourism booking matching-vehicle previews
- Live package marketplace cards
- Join Tour cards
- Live tour matching cards

## UI rules applied
- Pickup → destination appears first in a highlighted route panel.
- Destination uses stronger typography and primary branding.
- Vehicle name, registration, package title and image are compact secondary information.
- Free-seat badges have filled availability colors:
  - Green: more than 2 seats
  - Orange: 1–2 seats
  - Red: full/unavailable where supported
- Fare remains prominent without competing with the route.

## Build note
Flutter SDK was not available in the execution environment, so `flutter analyze` and `flutter build web` could not be run here. Structural delimiter checks passed for all edited Dart files.
