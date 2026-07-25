# Direct upload instructions

No PowerShell script is required.

Upload/replace these exact files:

1. `admin_portal/app/verification/page.tsx`
2. `admin_portal/app/verification/verification.module.css`
3. `admin_portal/app/lib/admin-api.ts`

These files are deliberately different from the previous upload:

- Default table size is now 50 rows.
- Verification header shows `List v2`.
- Failed attachments have a `Retry attachment` button.
- Retry uses a cache-busting request key.
- Admin API exports build marker `verification-list-v2`.

After uploading all three files, commit to `main`, then redeploy only
the Railway `udrive-admin` service.
