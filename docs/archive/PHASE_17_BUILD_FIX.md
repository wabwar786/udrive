# Phase 17 Railway Build Fix

## Flutter
Removed invalid `const` usage for screens whose constructors are not const:
- `TrustedContactsScreen()`
- `TourGuardianScreen()`
- `OfflineTravelCardScreen()`

File:
`udrive_unified_mobile/lib/screens/main_shell.dart`

## Admin portal
Added explicit response types to `apiFetch<T>()` calls and used the returned data directly. `apiFetch` already unwraps the API envelope, so `.data` was incorrect and left the responses inferred as `unknown`.

File:
`admin_portal/app/safety/page.tsx`

Corrected behavior:
- `apiFetch<D>(...)`
- `apiFetch<C[]>(...)`
- `setD(a)`
- `setRows(b)`

## Validation
The exact compiler errors from Railway are resolved in source.
Local Admin dependency installation could not complete because the internal package mirror did not contain `undici-types@6.21.0`; Railway already resolves dependencies and should run the authoritative build.
