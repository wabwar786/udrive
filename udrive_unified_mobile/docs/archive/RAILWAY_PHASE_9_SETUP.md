# Railway Phase 9 Setup

No new Railway service is required.

## API variables

Keep all Phase 8 variables and add:

```env
ENABLE_DEMO_MARKETPLACE=true
```

Recommended testing values:

```env
AUTO_APPLY_MIGRATIONS=true
ENABLE_SWAGGER=true
ENABLE_DEMO_MARKETPLACE=true
```

The existing `DATABASE_URL`, JWT secrets, OTP secrets, CORS configuration and `/data/uploads` volume remain unchanged.

## API deployment

Service root:

```text
/udrive_api
```

Healthcheck:

```text
/health/live
```

Expected migration log:

```text
Applied database migration 005_phase9_live_booking_marketplace
```

Verify:

```text
https://udrive-api-production.up.railway.app/health/live
https://udrive-api-production.up.railway.app/health/ready
https://udrive-api-production.up.railway.app/swagger
```

## Admin deployment

Service root:

```text
/admin_portal
```

Variable:

```env
NEXT_PUBLIC_API_BASE_URL=https://udrive-api-production.up.railway.app
```

Open:

```text
https://YOUR-ADMIN-DOMAIN/marketplace
```

## Mobile deployment

Service root:

```text
/udrive_unified_mobile
```

The mobile app defaults to:

```text
https://udrive-api-production.up.railway.app
```

After deployment use a hard refresh or clear the previous Flutter web cache once.
