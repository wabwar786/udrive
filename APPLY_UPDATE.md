# Apply this update to `wabwar786/udrive`

This package is aligned with the existing monorepo. It intentionally contains only:

```text
.github/workflows/build-mobile.yml
udrive_unified_mobile/
```

It does not replace or modify `admin_portal` or `docs`.

## Windows steps

1. Download and extract this ZIP.
2. Open your local cloned `udrive` repository.
3. Delete the existing `udrive_unified_mobile` folder.
4. Copy the extracted `.github` and `udrive_unified_mobile` folders into the repository root.
5. Confirm the repository looks like:

```text
udrive/
├── .github/
│   └── workflows/
│       └── build-mobile.yml
├── admin_portal/
├── docs/
└── udrive_unified_mobile/
```

6. Commit and push:

```bash
git add .
git commit -m "Upgrade unified uDrive premium mobile app"
git push origin main
```

## Railway

Keep the mobile service root directory as:

```text
/udrive_unified_mobile
```

The included Dockerfile builds and hosts the Flutter web preview.

## Download APK from GitHub

1. Open the repository on GitHub.
2. Select **Actions**.
3. Open **Build uDrive APK and AAB**.
4. Select **Run workflow**.
5. Open the completed run.
6. Download `udrive-premium-apk` under **Artifacts**.
7. Extract the artifact ZIP to get `app-release.apk`.

The `udrive-play-store-aab` artifact is for Google Play after production signing is configured.
