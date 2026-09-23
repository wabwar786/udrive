# Apply Attachment Preview Regression Fix

Apply this patch after the latest SuperAdmin, user-creation and
attachment-management update.

This patch changes only:

- `admin_portal/app/verification/page.tsx`
- `admin_portal/app/lib/admin-api.ts`

It does not modify:

- API code
- Database
- SuperAdmin permissions
- User creation
- Driver, vehicle or attachment deletion

## Apply

Extract the ZIP into the root of the local `udrive` repository and allow
the two files to replace the current versions.

```bash
git status
git add admin_portal/app/verification/page.tsx admin_portal/app/lib/admin-api.ts
git commit -m "Restore compatible verification attachment previews"
git push origin main
```

## Railway

Redeploy only:

```text
udrive-admin
-> Deployments
-> Deploy Latest Commit
```

API redeployment is not required.

After deployment:

```text
Ctrl + Shift + R
```

or test in an Incognito window.
