# Apply uDrive Phase 9

This repository update adds the live booking marketplace on top of Phase 8.

## Included folders

- `.github/workflows`
- `udrive_api`
- `udrive_unified_mobile`
- `admin_portal/app/marketplace`

The rest of the Admin portal remains unchanged.

## Apply locally

1. Extract this ZIP.
2. Copy all extracted items into the root of the local `udrive` repository.
3. Allow matching files to be replaced.
4. Do not delete the remaining Admin portal files.
5. Run:

```bash
git status
git add .
git commit -m "Add Phase 9 live booking marketplace"
git push origin main
```

## Railway deployment order

1. `udrive-api` — deploy latest commit first.
2. Confirm migration `005_phase9_live_booking_marketplace` was applied.
3. `udrive-admin` — deploy latest commit.
4. `udrive-mobile` — deploy latest commit.

Existing service root directories remain:

```text
/udrive_api
/admin_portal
/udrive_unified_mobile
```

## Testing variable

Add this to the API service while testing:

```env
ENABLE_DEMO_MARKETPLACE=true
```

This creates one verified demo Driver offer when a Customer submits a ride request. Set it to `false` when real Drivers are being used.

## Admin marketplace

Open:

```text
https://YOUR-ADMIN-DOMAIN/marketplace
```

Development Admin login:

```text
Phone: 03000000099
OTP: 1234
```
