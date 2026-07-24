# Apply Phase 8 to the existing uDrive repository

This update is structured for the existing monorepo.

## Included paths

```text
.github/workflows/build-api.yml
.github/workflows/build-mobile.yml
admin_portal/app/verification/
udrive_api/
udrive_unified_mobile/
```

The update does not replace the rest of `admin_portal`.

## Apply

1. Extract the ZIP.
2. Copy all extracted items into the root of the local `udrive` repository.
3. Allow matching files and folders to be replaced.
4. Do not delete the existing Admin portal outside `app/verification`.
5. Run:

```bash
git status
git add .
git commit -m "Add Phase 8 live authentication and verification"
git push origin main
```

## Deployment order

1. Deploy `udrive-api` first.
2. Confirm migration `004_phase8_authentication_and_verification` is applied.
3. Test authentication and Swagger.
4. Deploy `udrive-admin`.
5. Deploy `udrive-mobile`.
6. Build the APK from GitHub Actions.
