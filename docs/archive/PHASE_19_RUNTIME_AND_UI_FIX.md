# Phase 19 runtime and UI fix

## Runtime root cause
The production `udrive.destinations` table uses `name_en` and `name_ur`. Three Phase 19 queries incorrectly referenced a non-existent `name` column:

- Unified bookings
- Executive operations
- Tourism marketplace inventory

All references now use `name_en`.

## Reliability improvement
Tourism Marketplace now loads the package inventory and pending-review queue independently with `Promise.allSettled`. A failure in one source no longer hides the other source.

## UI redesign
- Finance & Settlements: compact summary header, six focused metrics, segmented tabs, better search, status pills, denser professional tables.
- Tourism Marketplace: route-first cards and rows, clear approval queue, occupancy metric, seat inventory bar, compact Driver/vehicle details.
