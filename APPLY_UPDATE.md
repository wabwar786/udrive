# Customer Offers Screen TraceId Hotfix

Overlay the included files on the latest codebase.

## Deployment order
1. Deploy API.
2. Confirm `/health/live` and `/health/ready`.
3. Deploy Flutter web.
4. Log out/in once, create a new ride request, and open the offers screen.

No database migration is required.
