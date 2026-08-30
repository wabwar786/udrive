# Phase 17 — Safety, Emergency & Trust

Implemented:
- SOS emergency cases with GPS coordinates and Admin notifications
- Trusted contacts with one primary emergency contact
- 4-digit trip boarding PIN generation, expiry, failed-attempt lock and Driver verification
- Unsafe-driving/safety reports linked to bookings
- Admin Safety Centre dashboard and emergency case actions
- GPS stale-trip metrics
- Driver compliance document schema and expiry index
- Emergency status timeline foundation

Migration: `018_phase17_safety_emergency_trust.sql`

Deploy API first, confirm migration 018, then deploy Admin and Flutter web.
