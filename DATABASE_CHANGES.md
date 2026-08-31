# Database Changes

Migration `009_phase13_finance_wallets.sql` is additive.

New tables:
- `commission_rules`
- `driver_wallets`
- `driver_earnings`
- `driver_wallet_entries`
- `driver_payout_requests`
- `refund_requests`
- `financial_adjustments`

Added safe columns/indexes on `payments` for idempotency, refund totals, and finance review metadata.

A PostgreSQL trigger calls `udrive.ensure_driver_earning(booking_id)` when a booking first changes to `Completed`. The booking remains the source of truth for gross fare. The selected commission rule is resolved server-side, and only one earning can exist per booking.

## 033_travel_vehicle_rates (rev 51)

- Adds `Hiace` rows to `udrive.service_vehicle_rates` for `City` and
  `PrivateVehicle`. It had no row at all, so its fare came from the app's
  built-in fallback and the admin could not change it.
- Deactivates `Rickshaw` for those two service types. It is not one of the four
  travel options the customer app offers. Set `is_active = true` to bring it
  back — the rows are not deleted.
- Adds column comments recording what the three rate columns actually mean:
  `per_km_rate` scales with distance; `whole_vehicle_rate` and `per_seat_rate`
  are flat **minimums**, not per-kilometre figures. The mobile app had been
  multiplying `whole_vehicle_rate` by the trip distance.

## 034_driver_presence_heading (rev 53)

- Adds a nullable `heading` column to `udrive.driver_presence_locations`, so the
  customer's map can rotate each vehicle to the direction its driver is facing.
- Nullable on purpose: a stationary phone reports no heading and an older Driver
  build sends none. Those vehicles are drawn unrotated rather than pointed
  somewhere invented. The upsert keeps the last known heading when a new reading
  has none.
