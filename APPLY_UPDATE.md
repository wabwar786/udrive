# Customer Booking Session Refresh Hotfix

Overlay the `udrive_unified_mobile` folder onto the latest source and redeploy Flutter web.

## Why this is needed

The UI can restore a cached user from SharedPreferences while browser secure storage fails to return the access/refresh tokens. Also, multiple repositories previously performed independent refresh-token rotations at the same time.

## Fixes

- Mirrors tokens to a persistent SharedPreferences recovery store.
- Uses one app-wide refresh operation across all ApiClient instances.
- Retries the original authenticated request after refresh.
- Does not force refresh just because old sessions lack expiry metadata.
- Clears the session only when the API definitively rejects the refresh token.

## Deployment

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

After the first deployment, sign out and sign in once so the current tokens are written to both stores. Future booking submissions will refresh automatically.
