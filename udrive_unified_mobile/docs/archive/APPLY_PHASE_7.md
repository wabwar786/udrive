# Apply Phase 7 to the existing repository

Copy these items into the root of `wabwar786/udrive`:

```text
.github/workflows/build-api.yml
udrive_api/
PHASE_7_DATABASE_DECISION.md
RAILWAY_PHASE_7_SETUP.md
```

Then run:

```bash
git add .
git commit -m "Add Phase 7 PostgreSQL PostGIS API foundation"
git push origin main
```

This update does not replace `admin_portal` or `udrive_unified_mobile`.
