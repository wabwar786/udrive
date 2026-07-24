# Apply uDrive Phase 3–6 Update

This package is designed for the `wabwar786/udrive` monorepo.

## Safe replacement

1. Extract this ZIP.
2. In your local repository, delete the existing `udrive_unified_mobile` folder.
3. Copy the extracted `udrive_unified_mobile` folder into the repository root.
4. Copy/merge `.github/workflows/build-mobile.yml` into the repository root.
5. Do not replace or delete `admin_portal`.

Expected structure:

```text
udrive/
├── .github/workflows/build-mobile.yml
├── admin_portal/
├── docs/
└── udrive_unified_mobile/
```

## Push

```bash
git status
git add .
git commit -m "Add uDrive tourism phases 3 to 6"
git push origin main
```

## Railway

Keep the Mobile service root directory:

```text
/udrive_unified_mobile
```

Use **Deploy Latest Commit**. Do not configure a custom build command, start command or manual `PORT` variable.

## APK and AAB

Open GitHub → Actions → **Build uDrive APK and AAB** → Run workflow.

Artifacts:

- `udrive-tourism-phase-3-6-apk`
- `udrive-tourism-phase-3-6-aab`
