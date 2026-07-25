# Phase 13 API runtime/migration hotfix

Replace these files in the current project:

- `udrive_api/Dockerfile`
- `udrive_api/Infrastructure/Persistence/SqlMigrationRunner.cs`
- `udrive_api/Infrastructure/Persistence/Migrations/009_phase13_finance_wallets.sql`

## Why the API crashed

Migration 009 contained its own `BEGIN` and `COMMIT`, while `SqlMigrationRunner` already wraps each migration in an Npgsql transaction. The SQL `COMMIT` completed the outer transaction before the runner inserted the migration record and called `CommitAsync`. The catch block then attempted to roll back the already-completed transaction and masked the original error.

The corrected migration removes transaction-control statements. The runner now logs the original migration exception and safely handles a rollback that is no longer possible. The runtime image also installs `libgssapi-krb5-2`.

## Deployment

1. Overlay the three files.
2. Commit and deploy the API service.
3. Confirm the deployment log contains `Applied database migration 009_phase13_finance_wallets` or starts normally if it was already recorded.
4. Verify `/health/live`, `/health/ready`, and Swagger.
5. Check the migration record:

```sql
SELECT migration_id, applied_at
FROM public.schema_migrations
WHERE migration_id = '009_phase13_finance_wallets';
```

The migration is idempotent, so a previous partially/fully applied attempt can be rerun safely after this hotfix.
