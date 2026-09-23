# Customer Home UI and Pickup Address Update

Updated on 01 August 2026.

## Changes completed

- Rebuilt the customer home screen in the supplied dark Kashmir tourism style.
- Added a full-width interactive Kashmir map hero.
- Added an in-screen menu button, Discover Kashmir heading, pickup card and map recenter button.
- Added Explore Kashmir promotional banner.
- Added tourism service cards for Explore, Stay, Transport and Activities.
- Added a dark destination search/list section using existing Kashmir image assets.
- Preserved incoming-driver tracking and available-rides sections.
- Removed the standard app bar from the customer home screen so the new map hero starts from the top.
- Changed advance-booking current pickup from raw latitude/longitude text to a readable reverse-geocoded address.
- Latitude and longitude are still retained internally and still sent to the API.
- Added the Flutter `geocoding` dependency.

## Required command after opening the project

```bash
flutter pub get
flutter analyze
flutter run
```

## Validation note

The current execution environment does not contain the Flutter SDK, so `flutter pub get` and `flutter analyze` could not be run here. The updated source has been packaged for validation in your Flutter development environment or GitHub build workflow.
