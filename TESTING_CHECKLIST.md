# Testing checklist

- [ ] API builds successfully.
- [ ] Migration 013 appears in schema migrations.
- [ ] Customer acceptance creates booking with `DriverAccepted` status.
- [ ] `trip_operations` row exists.
- [ ] Active `trip_assignments` row exists.
- [ ] Driver sees accepted ride.
- [ ] Start changes status to `DriverEnRoute`.
- [ ] Customer notification is created.
- [ ] Driver map opens in app.
- [ ] Driver location history receives points about every 10 seconds.
- [ ] Customer map refreshes about every 10 seconds.
- [ ] Driver can mark arrived.
- [ ] Unauthorized users cannot track the booking.
