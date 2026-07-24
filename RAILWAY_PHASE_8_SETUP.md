# Railway Phase 8 setup

## 1. API service

Keep:

```text
Repository: wabwar786/udrive
Branch: main
Root Directory: /udrive_api
Healthcheck: /health/live
```

Do not add a custom build or start command because the API Dockerfile provides them.

## 2. API variables

Keep the existing PostGIS connection and add:

```env
AUTO_APPLY_MIGRATIONS=true
ENABLE_SWAGGER=true
ALLOWED_ORIGINS=https://udrive-mobile-production.up.railway.app,https://YOUR-ADMIN-DOMAIN

JWT_ISSUER=udrive-api
JWT_AUDIENCE=udrive-clients
JWT_SIGNING_KEY=REPLACE_WITH_A_LONG_RANDOM_SECRET
JWT_ACCESS_TOKEN_MINUTES=15
JWT_REFRESH_TOKEN_DAYS=30
OTP_HASH_SECRET=REPLACE_WITH_A_DIFFERENT_LONG_RANDOM_SECRET
IDENTITY_HASH_SECRET=REPLACE_WITH_ANOTHER_LONG_RANDOM_SECRET

OTP_PROVIDER=Development
DEVELOPMENT_OTP_CODE=1234
EXPOSE_DEVELOPMENT_OTP=false
UPLOAD_ROOT=/data/uploads
```

Generate three independent random secrets. Do not reuse the database password.

PowerShell example:

```powershell
$bytes = New-Object byte[] 64
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
[Convert]::ToBase64String($bytes)
```

Run the command separately for each secret.

## 3. Persistent verification-file volume

Attach a Railway volume to `udrive-api` with mount path:

```text
/data/uploads
```

The API stores protected Driver and vehicle evidence there. Without the volume, uploaded files can disappear after a deployment replacement.

## 4. Deploy API

Use `Deploy Latest Commit`. Confirm:

```text
/health/live      Healthy
/health/ready     Healthy
/swagger          opens
```

Application logs should show migration `004_phase8_authentication_and_verification` applied once.

## 5. Admin portal

Keep root directory:

```text
/admin_portal
```

Recommended build variable:

```env
NEXT_PUBLIC_API_BASE_URL=https://udrive-api-production.up.railway.app
```

After deployment open:

```text
https://YOUR-ADMIN-DOMAIN/verification
```

## 6. Mobile web

Keep root directory:

```text
/udrive_unified_mobile
```

The project defaults to the deployed production API URL. Deploy the latest commit and hard-refresh the browser.
