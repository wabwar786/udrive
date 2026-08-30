# Railway Setup — Phase 7

## 1. Add PostGIS

In the existing Railway project, add the **PostGIS** database template rather than the standard PostgreSQL template.

Recommended image/template: PostgreSQL 17 + PostGIS 3.5.

## 2. Add API service

Create a new service from the same GitHub repository.

- Service name: `udrive-api`
- Root directory: `/udrive_api`
- Branch: `main`
- Custom build command: blank
- Custom start command: blank

Railway will use `udrive_api/Dockerfile`.

## 3. Variables

Set the API variable by referencing the PostGIS service:

```text
DATABASE_URL=${{PostGIS.DATABASE_URL}}
AUTO_APPLY_MIGRATIONS=true
ENABLE_SWAGGER=true
ALLOWED_ORIGINS=https://udrive-mobile-production.up.railway.app
```

The exact PostGIS service name may differ. Use Railway's variable-reference UI.

## 4. Networking

Generate a public domain for `udrive-api`.

Test:

```text
https://YOUR-API-DOMAIN/health/ready
https://YOUR-API-DOMAIN/api/v1/system/status
https://YOUR-API-DOMAIN/api/v1/catalog/destinations
https://YOUR-API-DOMAIN/swagger
```

## 5. Backups

Enable Railway volume backups before storing real customer, driver or payment data.
