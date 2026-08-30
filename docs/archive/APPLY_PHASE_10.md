# Apply Phase 10

This package intentionally contains only:

- `admin_portal/` — complete replacement
- `udrive_api/` — Phase 10 API additions and Swagger fix
- Phase 10 documentation

It does not contain the Flutter mobile app, APK workflow, or AAB workflow.

## Apply

1. Back up the existing repository.
2. Delete the existing local `admin_portal` folder.
3. Copy the new `admin_portal` folder from this package.
4. Copy the included `udrive_api` folder over the repository's existing
   `udrive_api` folder and allow matching files to be replaced.
5. Do not delete the other existing API files.
6. Commit:

```bash
git status
git add admin_portal udrive_api
git commit -m "Add Phase 10 complete Admin operations portal"
git push origin main
```

## Deployment order

1. Deploy `udrive-api` first.
2. Confirm migration `006_phase10_admin_operations` is applied.
3. Test Swagger JSON.
4. Deploy `udrive-admin`.
5. Hard refresh the Admin browser.
