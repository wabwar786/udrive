# Phase 12 — Live GPS Tracking and Maps

Implemented:

- JWT-owned Driver location endpoint. Driver ID is derived from the authenticated user and the assigned booking.
- Coordinate, timestamp, speed, heading, accuracy, battery, permission, and source validation/storage.
- Rate limiting, minimum update interval, duplicate event ID protection, duplicate-point suppression, and active-state enforcement.
- PostGIS latest-location and bounded trip-history tables with GiST/time indexes.
- Admin Live Tracking page with active-trip list, route path, pickup/destination/driver markers, speed, heading, accuracy, online/stale status, emergency state, and filters.
- Customer private tracking limited to booking owner or assigned driver/admin roles.
- Random 256-bit share token, SHA-256 database hash, expiry, revocation, trip scope, read-only response, completion/cancellation shutdown, and public rate limiting.
- Flutter offline queue with chronological retry, duplicate client IDs, maximum queue size, and old points not promoted over newer current locations.
- Tracking stops when no eligible active trip is present.
- Internal notifications and audit-compatible events remain extensible for external push credentials.

Retention setting `tracking.history_retention_days` is seeded. A scheduled cleanup job can delete history older than that setting without affecting latest locations.
