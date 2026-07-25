# uDrive Phase 13.5 — Customer & Driver Live UI Update

1. Apply this package on top of the latest Phase 13 codebase.
2. Copy the `udrive_unified_mobile` folder over the existing folder while preserving all other files.
3. Run `flutter pub get`.
4. Run `flutter analyze`.
5. Build Flutter web only: `flutter build web --release`.
6. Deploy the generated web build when required. Do not build APK/AAB yet.

No database migration is required for this UI-only update. It consumes the existing authenticated API endpoints and database-backed models.
