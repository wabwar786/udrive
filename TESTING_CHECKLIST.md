# Phase 11–12 Testing Checklist

## API and migration

- [ ] `/health/live` returns success.
- [ ] `/health/ready` confirms PostgreSQL.
- [ ] Migration 008 appears in migration history.
- [ ] Existing bookings have one `trip_operations` row.
- [ ] Existing booking/authentication/verification endpoints still work.

## Operations

- [ ] Admin filters/search/pagination work.
- [ ] Unverified/suspended driver cannot be assigned.
- [ ] Unverified/suspended vehicle cannot be assigned.
- [ ] Vehicle below passenger capacity is blocked.
- [ ] Driver/vehicle overlap is blocked.
- [ ] Duplicate pending offer is blocked.
- [ ] Driver can accept or reject with reason.
- [ ] Other driver cannot respond to the offer.
- [ ] Invalid lifecycle transition returns 409.
- [ ] Trip cannot start before accepted verified assignment.
- [ ] Completed/cancelled trip cannot restart without authorized override.
- [ ] Audit log and notifications are created.

## Tracking

- [ ] Another driver cannot update the trip location.
- [ ] Another customer cannot view tracking.
- [ ] Invalid coordinates/timestamps are rejected.
- [ ] Fast repeated updates receive 429 or are suppressed.
- [ ] Duplicate client event is idempotent.
- [ ] Admin sees live/stale/emergency indicators.
- [ ] Customer sees only their trip.
- [ ] Public token expires and can be revoked.
- [ ] Public token stops after completion/cancellation.
- [ ] Offline points retry in chronological order.
- [ ] Older cached point does not overwrite newer latest location.

## UI

- [ ] Desktop/tablet/mobile Admin layouts remain compact.
- [ ] Driver Dispatch and Marketplace tabs both work.
- [ ] Customer My Trips shows assignment and status progression.
- [ ] English/Urdu application mode remains functional.
- [ ] No APK/AAB is generated.
