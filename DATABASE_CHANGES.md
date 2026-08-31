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

## 035_pricing_rules (rev 56)

- New table `udrive.pricing_rules`: a per-km rate, a minimum fare and a
  per-minute rate, optionally narrowed to particular ISO days (`days_of_week`,
  1 = Monday) and to a circular area (`area_latitude`, `area_longitude`,
  `area_radius_km`). Empty scopes mean everywhere and every day.
- A `CHECK` requires an area to have all three parts or none. A half-set circle
  would match nothing and look like a rule that simply does not work.
- Seeds one global rule per active row in `service_vehicle_rates`, so the day
  this ships nothing changes and the admin opens a filled table rather than an
  empty one.
- Resolution picks exactly one rule — highest `priority`, then area over
  everywhere, then smaller area, then named days over every day. Blending
  several would make a fare impossible to trace back to anything typed.
- The day is read as `EXTRACT(ISODOW FROM now() AT TIME ZONE 'Asia/Karachi')`
  inside the query, so the answer does not depend on the server's clock.

## 036_vehicle_tour_rates (rev 57)

- Adds `tour_per_day_rate`, `tour_per_km_rate`, `tour_minimum_fare` and
  `tour_notes` to `udrive.vehicles`. Tourism is priced by the driver, not by the
  admin's per-kilometre rules: a multi-day mountain trip is not a metered ride,
  and what it is worth is a judgement only the person driving can make.
- All nullable. Null means the driver has not published a price, which is not
  the same as offering to tour for free — the service treats zero as unset for
  the same reason.
- Partial index on tour-ready vehicles that have actually named a price, since
  that is the only set ever read.

## 037_seat_fares (rev 58)

- New table `udrive.seat_fares`: a fixed fare per passenger for a named route,
  with both ends stored as a labelled circle (centre plus radius) because
  passengers board somewhere in a town rather than at one coordinate.
- `applies_both_ways` defaults true, so an admin enters Muzaffarabad →
  Rawalakot once instead of twice and the two halves cannot drift apart.
- Only affects per-seat trips. Hiring a whole Coster is still priced per
  kilometre and still negotiable.

## 038_trip_messages (rev 64)

- New table `udrive.trip_messages`, scoped to a booking. `sender_role` is
  denormalised so the app can lay a message left or right without a join.
- `read_at` drives the unread badge and nothing else is inferred from it.
- Passenger standing is computed from the existing `udrive.trip_ratings`, which
  has recorded ratings in both directions since phase 14 — nobody was reading
  the Customer half. No new rating capture was added.
