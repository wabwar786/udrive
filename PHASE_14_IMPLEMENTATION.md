# Phase 14 — Ratings, Reviews, Complaints and Disputes

Implemented on top of the Phase 13.5 fixed codebase.

## Database
- Migration `015_phase14_ratings_complaints_disputes.sql`
- Trip ratings with one rating per reviewer per booking
- Complaint/dispute cases with optimistic versioning
- Protected evidence attachments
- Immutable case timeline/events
- Queue indexes and audit records

## API
### Customer and Driver
- `GET /api/v1/feedback/eligible-bookings`
- `POST /api/v1/feedback/ratings`
- `GET /api/v1/feedback/ratings/me`
- `POST /api/v1/feedback/cases`
- `GET /api/v1/feedback/cases/my`
- `GET /api/v1/feedback/cases/{id}`
- `POST /api/v1/feedback/cases/{id}/events`
- `POST /api/v1/feedback/cases/{id}/evidence`

### Admin
- `GET /api/v1/admin/disputes/dashboard`
- `GET /api/v1/admin/disputes`
- `GET /api/v1/admin/disputes/{id}`
- `PUT /api/v1/admin/disputes/{id}/assign`
- `PUT /api/v1/admin/disputes/{id}/status`
- `POST /api/v1/admin/disputes/{id}/events`
- `POST /api/v1/admin/disputes/{id}/actions`
- `POST /api/v1/admin/disputes/{id}/evidence`

Actions include warnings, temporary/permanent suspension, refund recommendations and financial-adjustment recommendations. Permanent suspension is restricted to SuperAdmin.

## Flutter
- Ratings & complaints center linked from Customer and Driver profile screens
- Completed-trip rating flow
- Complaint creation and personal case list
- API repository and models

## Admin portal
- Complaint dashboard cards
- Search/status/priority filters
- Case detail drawer
- Evidence viewing through authenticated API fetch
- Timeline, internal notes, assignment, status and resolution controls
- Warning/suspension/refund recommendation actions

## Deployment
1. Deploy API first so migration 015 runs.
2. Deploy Admin portal.
3. Deploy Flutter web.
4. Test rating after a completed booking and create one complaint with an attachment.

## Build environment note
The current sandbox did not contain .NET or Flutter SDK. Admin dependency installation was blocked by the internal package mirror missing `undici-types@6.21.0`. Run normal Railway/CI build commands before production acceptance.
