# Railway Deployment

1. Keep PostGIS volume mounted at `/var/lib/postgresql/data`.
2. Keep API upload volume mounted separately at `/app/uploads`.
3. Keep `UPLOAD_ROOT=/app/uploads` on the API service.
4. Deploy API first.
5. Verify `/health/live` and `/health/ready` return HTTP 200.
6. Confirm migration `009_phase13_finance_wallets.sql` in logs/database.
7. Confirm Finance endpoints in Swagger.
8. Deploy Admin portal.
9. Hard refresh Admin portal and open **Finance & settlements**.
10. Deploy Flutter web only when required. Do not create APK/AAB.
