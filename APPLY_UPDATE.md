# uDrive Phase 13 Update

Overlay the included files on the latest Phase 11–12 codebase. Do not delete existing files or migrations.

1. Back up the Railway PostgreSQL database.
2. Copy the update files preserving paths.
3. Deploy `udrive_api`; migration `009_phase13_finance_wallets.sql` is additive and auto-applies when `AUTO_APPLY_MIGRATIONS` is not `false`.
4. Confirm `/health/live`, `/health/ready`, and Swagger.
5. In Swagger confirm `Finance` and `DriverFinance` controllers.
6. Deploy `admin_portal` and hard refresh.
7. Run `flutter pub get`; deploy Flutter web only when required. Do not build APK/AAB yet.
8. As SuperAdmin call `POST /api/v1/admin/finance/reconcile-completed-trips` once to create missing earnings for historical completed trips.
