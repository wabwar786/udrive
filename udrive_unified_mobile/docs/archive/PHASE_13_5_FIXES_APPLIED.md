# Phase 13.5 Fixes Applied

## Fixed

1. Driver and vehicle verification compatibility
   - Driver statuses `Approved` and `Verified` are now accepted case-insensitively.
   - Vehicle statuses `Verified` and `Approved` are accepted in marketplace and trip assignment validation.

2. Ride-request expiry lifecycle
   - Past-departure open requests transition to `Expired`.
   - One-hour requests with no Driver offer transition to `NoDriverAccepted`.
   - One-hour requests that received offers but were not selected transition to `Expired`.
   - Lifecycle reconciliation runs when customer requests, Driver request queue, offers, and offer selection are loaded.
   - Added additive migration `014_phase13_5_status_compatibility.sql`.

3. Premature GPS sharing
   - `DriverAccepted` was removed from trackable GPS statuses.
   - GPS starts only for `DriverEnRoute`, `DriverArrived`, `TripStarted`, or `Emergency`.

4. Tracking synchronization
   - Driver active-trip synchronization changed from one minute to 10 seconds.
   - Customer package vehicle map refresh changed from one minute to 10 seconds.

## Changed files

- `udrive_api/Domain/Enums/AppEnums.cs`
- `udrive_api/Services/BookingService.cs`
- `udrive_api/Services/PackageMarketplaceService.cs`
- `udrive_api/Services/TripOperationsService.cs`
- `udrive_api/Infrastructure/Persistence/Migrations/014_phase13_5_status_compatibility.sql`
- `udrive_unified_mobile/lib/core/widgets/driver_location_coordinator.dart`
- `udrive_unified_mobile/lib/screens/customer/vehicle_live_map.dart`

## Validation note

Static source checks were completed. The current execution environment does not include the .NET SDK or Flutter SDK, so `dotnet publish`, `flutter analyze`, and `flutter build web` could not be executed here. Run the repository's documented CI/build commands before production deployment.
