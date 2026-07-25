# uDrive Web Session Token Priority Hotfix

Replace:

`udrive_unified_mobile/lib/core/auth/session_store.dart`

## Why this is required

On Flutter web, an old value in FlutterSecureStorage can remain readable after its writes/deletes stop working. The app then shows the newly logged-in user from SharedPreferences but sends the stale secure-storage access/refresh token to the API.

This hotfix makes the browser session mirror (SharedPreferences/localStorage) authoritative on web, while native Android/iOS continues to prefer secure storage.

## After deployment

1. Deploy Flutter web.
2. Log out once.
3. Log in again.
4. Submit `Find verified drivers`.
5. Confirm the request appears in Driver mode > Live requests.
