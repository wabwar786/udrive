# Phase 19 all-pages runtime fix

- All Admin page endpoint references were checked against API controllers.
- API errors are globally converted into user-friendly messages; trace IDs remain server-side only.
- Resource tables stop loading and clear stale data after an error.
- Migration 021 upgrades legacy production schemas used by Drivers, Vehicles, Payments, Support, Settings and Safety pages.
- Vehicles now have explicit `wheel_type`: `2Wheel`, `3Wheel`, or `4Wheel`. Existing rows are classified from category and new rows default to `4Wheel`.
