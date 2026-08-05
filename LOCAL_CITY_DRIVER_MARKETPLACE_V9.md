# UDrive local city marketplace V9

Implemented:
- Home `Where to?` opens Travel within city.
- Both From and To are editable and searchable.
- City vehicle screen includes Bike, Car, Rickshaw and Coster.
- Per-seat and whole-vehicle booking modes are available for every vehicle.
- Default per-seat and whole-vehicle prices load from PostgreSQL `udrive.service_vehicle_rates`.
- Customer can edit either suggested rate before sending the request.
- Driver presence is published from the online Driver dashboard.
- Driver marketplace returns only verified Drivers whose fresh presence is within 5 km of pickup.
- Multiple Drivers can submit their own fare and arrival time; customer offer screen already polls them.
- Customer confirmation now shows driver arrival minutes and opens live tracking.
- Customer live tracking refreshes every 10 seconds using the existing tracking service.

Database migration added:
`udrive_api/Infrastructure/Persistence/Migrations/023_local_pricing_and_driver_presence.sql`

Important:
The seeded prices in migration 023 are initial database values. Change them in the database/admin pricing interface according to operational rates.
