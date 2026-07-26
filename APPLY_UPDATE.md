# Driver Marketplace merged hotfix

Replace these files in the latest project:

- `udrive_api/Services/BookingService.cs`
- `udrive_unified_mobile/lib/screens/driver/live_driver_requests_screen.dart`

Deploy API first, then Flutter web.

This package preserves the customer-offers TraceId safety changes and restores the prior `pickupAt` compile fix. It also accepts both `Approved` and `Verified` driver/vehicle verification values so seeded and legacy verified fleet records appear in Driver mode.
