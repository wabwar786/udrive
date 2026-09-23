# Apply Driver Verification Update

This update replaces only:

- `admin_portal/app/verification/page.tsx`
- `admin_portal/app/verification/verification.module.css`
- `admin_portal/app/lib/admin-api.ts`
- `udrive_api/Controllers/AdminVerificationController.cs`
- `udrive_api/Controllers/VerificationFilesController.cs`

It does not change the mobile app or database schema.

## Apply

Extract the ZIP into the root of the local `udrive` repository and allow
matching files to be replaced.

```bash
git status
git add admin_portal/app/verification admin_portal/app/lib/admin-api.ts udrive_api/Controllers
git commit -m "Add complete Driver document verification workspace"
git push origin main
```

## Deploy

Deploy API first, then Admin:

1. `udrive-api` → Deploy Latest Commit
2. Confirm `/health/live` and `/health/ready`
3. `udrive-admin` → Deploy Latest Commit
4. Hard refresh the Admin browser
