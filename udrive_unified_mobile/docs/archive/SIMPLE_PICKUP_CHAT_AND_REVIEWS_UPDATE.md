# Simple Pickup, Chat and Reviews Update

## Implemented

- Driver package creation keeps pickup point mandatory and clearly labels it as required.
- Customer package cards and detail screens prominently show the pickup point.
- Confirmed/active bookings now include a real `Chat with driver` button using the existing booking chat API.
- Greeting now follows local device time: morning, afternoon, evening and night.
- Destination rating and vehicle rating are shown separately on home ride cards, package cards and package details.
- Package detail includes a Reviews section before booking.
- Destination and vehicle review counts use API-compatible getters with safe display fallbacks until dedicated destination/vehicle rating fields are returned by the backend.

## Main files

- `udrive_unified_mobile/lib/screens/customer/customer_home_screen.dart`
- `udrive_unified_mobile/lib/screens/customer/live_packages_screen.dart`
- `udrive_unified_mobile/lib/screens/customer/live_bookings_screen.dart`
- `udrive_unified_mobile/lib/screens/driver/live_create_package_screen.dart`
- `udrive_unified_mobile/lib/models/booking_models.dart`
