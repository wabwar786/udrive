# Apply Phase 11–12 Update

This package is an additive overlay for the latest uDrive repository. Do not delete existing folders.

1. Back up the production PostgreSQL database.
2. Copy the included files into the repository, preserving paths.
3. Confirm Railway API volume mount `/app/uploads` and `UPLOAD_ROOT=/app/uploads`.
4. Deploy `udrive_api`. Migration `008_phase11_12_trip_operations_tracking.sql` is embedded and applied by the existing migration runner when `AUTO_APPLY_MIGRATIONS` is not `false`.
5. Confirm `/health/live` and `/health/ready`.
6. Confirm all Phase 11–12 tables and indexes listed in `DATABASE_CHANGES.md`.
7. Deploy `admin_portal`.
8. Run `flutter pub get`, configure Android/iOS location permissions, then deploy Flutter web only when required. Do not build APK/AAB for this phase.

No existing table or production column is removed or renamed.
