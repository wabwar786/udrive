# Phase 20 — Production Hardening and Launch Readiness

## Implemented in this package

### API security
- Global per-client rate limiter (300 requests/minute)
- Existing strict OTP, GPS and public-tracking limiters preserved
- Friendly HTTP 429 response
- JWT token-version/session revocation validation preserved
- Production configuration validator for secrets, CORS and development OTP
- Security response headers
- Server header suppression
- Generic user-facing 500 response; trace ID remains available in logs/response metadata

### Data lifecycle
A background maintenance service runs every six hours by default and:
- deletes expired OTP challenges
- deletes old expired/revoked refresh tokens
- expires stale seat holds
- deletes old tracking links
- removes trip-location history older than 30 days
- removes read notifications older than 180 days

### Migration
`022_phase20_production_hardening.sql` adds cleanup/reporting indexes and production settings.

### Container hardening
- API container runs as a non-root user
- upload directory created with correct ownership
- Admin already runs as non-root
- Admin and Flutter web security headers added

### Release tooling
- `scripts/validate_release.sh` runs API, Admin and Flutter release validation
- `scripts/smoke_test.sh` checks live/ready health plus optional Admin/mobile URLs
- `PHASE_20_ENVIRONMENT.example` lists required production variables

## Deployment sequence
1. Back up PostgreSQL and uploaded evidence/documents.
2. Configure production secrets and allowed origins.
3. Deploy API and confirm migration 022.
4. Verify `/health/live` and `/health/ready`.
5. Deploy Admin.
6. Deploy Flutter web.
7. Run `scripts/smoke_test.sh`.
8. Test Customer, Driver, tourism, finance, safety and Admin flows.
9. Set `ENFORCE_PRODUCTION_SECURITY=true` only after all secrets/provider settings are complete.
10. Begin soft launch and monitor errors before public launch.

## Provider-dependent launch items
The codebase has foundations for these, but real provider credentials and external setup are still required:
- production SMS/OTP provider
- payment gateway webhooks and signatures
- Firebase/APNs push delivery
- native Android/iOS background GPS permissions and services
- Google Play/App Store signing and submissions
