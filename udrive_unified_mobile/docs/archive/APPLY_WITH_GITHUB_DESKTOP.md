# Apply without Git command line

The PowerShell message `git is not recognized` means Git CLI is not
available in the current PowerShell PATH. You also ran the commands from
`C:\Users\waseem`, not from the repository folder.

## 1. Extract correctly

Extract this ZIP directly into:

```text
C:\Users\waseem\Desktop\udrive
```

The file below must exist:

```text
C:\Users\waseem\Desktop\udrive\apply_verification_fix.ps1
```

## 2. Apply the patch

Open PowerShell inside the repository folder:

```powershell
cd C:\Users\waseem\Desktop\udrive
powershell -ExecutionPolicy Bypass -File .\apply_verification_fix.ps1
```

Expected output:

```text
Updated admin_portal\app\verification\page.tsx
Updated admin_portal\app\verification\verification.module.css
Updated admin_portal\app\lib\admin-api.ts
Patch applied successfully.
```

## 3. Commit with GitHub Desktop

1. Open GitHub Desktop.
2. Select **File → Add local repository**.
3. Choose `C:\Users\waseem\Desktop\udrive`.
4. Open the **Changes** tab.
5. Confirm the three Admin files are listed.
6. Summary:
   `Fix attachment previews and verification list`
7. Click **Commit to main**.
8. Click **Push origin**.

## 4. Railway

Redeploy only:

```text
udrive-admin → Deployments → Deploy Latest Commit
```

The API does not need redeployment for this patch.

After deployment use `Ctrl + Shift + R`.
