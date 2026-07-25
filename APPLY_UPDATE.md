# Apply SuperAdmin, User Creation and Attachment Preview Update

Extract this ZIP into the root of the local `udrive` repository and allow
matching files to replace.

```bash
git status
git add admin_portal udrive_api
git commit -m "Add SuperAdmin deletion controls user creation and attachment preview fix"
git push origin main
```

Deploy in this order:

1. `udrive-api` → Deploy Latest Commit.
2. Confirm migration `007_super_admin_access` in API logs.
3. Confirm `/health/live` and `/health/ready`.
4. `udrive-admin` → Deploy Latest Commit.
5. Sign out of the Admin portal and sign in again so the new SuperAdmin role
   is included in the JWT.
6. Hard refresh the portal.

No mobile app, APK or AAB files are included.
