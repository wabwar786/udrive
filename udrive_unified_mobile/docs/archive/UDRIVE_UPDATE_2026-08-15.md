# UDrive update - 15 Aug 2026

Implemented requested customer-app changes:

1. Home service cards made more compact. Existing four service images were kept unchanged.
2. Added Emergency / Ambulance service card.
   - Kashmir city selection.
   - Direct Rescue 1122 call button.
   - Ambulance request uses the existing Udrive Safety/SOS API with current pickup coordinates.
3. Removed the redundant City-to-city / Tour booking / Seat booking / Full vehicle controls from the route-entry screen.
4. Reworked the destination -> vehicle screen to remove the fragile network-map background dependency that could render as a black/blank page. It now uses a stable visible layout with pickup -> destination summary and the existing vehicle/booking content.

Changed files:
- udrive_unified_mobile/lib/screens/customer/customer_home_screen.dart
- udrive_unified_mobile/lib/screens/customer/udrive_route_flow_screen.dart
- udrive_unified_mobile/lib/screens/customer/emergency_ambulance_screen.dart (new)

Note: Flutter/Dart SDK was not installed in the execution environment, so `flutter analyze` / `dart format` could not be run here.
