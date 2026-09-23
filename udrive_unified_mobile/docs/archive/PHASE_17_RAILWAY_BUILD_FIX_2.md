# Phase 17 Railway Build Fix 2

Resolved from Railway logs dated 2026-07-30:

1. Flutter `main_shell.dart` referenced three screen classes that do not exist in the project. The legacy drawer destinations now route to the consolidated `SafetyHubScreen`, which contains the live trusted-contact and safety controls.
2. Migration 018 assumed `trusted_contacts.is_active` and `is_primary` would be created by `CREATE TABLE IF NOT EXISTS`. Older databases already have this table, so those columns were not added. Migration 018 now upgrades the existing table with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` before creating indexes. It also adds defaults for `id`, `created_at`, and `updated_at`, required by the Phase 17 insert API.

Redeploy API first so migration 018 can retry successfully, then redeploy Flutter web.
