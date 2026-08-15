# UDrive update — Emergency Ambulance + City-to-City flow

## Emergency
- Home Emergency card now uses a dedicated ambulance image asset.
- Removed Rescue 1122 hard-coded call flow.
- Added database migration `025_ambulance_directory_and_distance_rates.sql`.
- New table: `udrive.ambulance_services`.
- Public API returns only active ambulance cities and active ambulances for the selected city.
- Ambulance result shows name, city, phone and PKR/km fare.
- Call icon opens the selected ambulance's saved phone number.
- No fake emergency phone records are seeded. Add real verified ambulance records to `udrive.ambulance_services`.

Example record shape (replace values with verified real data):

```sql
INSERT INTO udrive.ambulance_services(name, city, phone_number, per_km_fare)
VALUES ('<verified ambulance name>', '<city>', '<verified phone>', <per-km-fare>);
```

## City-to-City
- Destination tap opens the ride selection screen with route summary instead of relying on map rendering.
- Route screen shows estimated distance, database per-km rate, estimated fare and available vehicles.
- Added `per_km_rate` to `udrive.service_vehicle_rates` and public catalog response.
- Vehicle cards show the database per-km rate and estimated route fare.
- Selecting a vehicle updates the default fare automatically.
- `Book selected ride` creates the existing live ride request.
- Existing driver marketplace offers, customer driver selection, confirmed booking and live tracking flow remain connected.

## Deployment
The API's existing SQL migration runner automatically applies migration 025 when automatic migrations are enabled.
