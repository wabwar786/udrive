# Railway Phase 10 Setup

## API service

Root Directory:

```text
/udrive_api
```

Keep existing API variables unchanged.

Recommended:

```env
AUTO_APPLY_MIGRATIONS=true
ENABLE_SWAGGER=true
ALLOWED_ORIGINS=https://udrive-mobile-production.up.railway.app,https://YOUR-ADMIN-DOMAIN
```

Deploy the latest commit. In deployment logs confirm:

```text
Applied database migration 006_phase10_admin_operations
```

Test:

```text
https://udrive-api-production.up.railway.app/health/live
https://udrive-api-production.up.railway.app/health/ready
https://udrive-api-production.up.railway.app/swagger/v1/swagger.json
https://udrive-api-production.up.railway.app/swagger
```

## Admin service

Root Directory:

```text
/admin_portal
```

Variable:

```env
NEXT_PUBLIC_API_BASE_URL=https://udrive-api-production.up.railway.app
```

Do not add a custom build command, custom start command, or manual `PORT`.

Deploy the latest commit and hard refresh the browser.

## Admin test login

```text
Phone: 03000000099
OTP: 1234
```
