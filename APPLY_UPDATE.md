# Apply Update

Extract this ZIP into the repository root and replace matching files.

```bash
git status
git add admin_portal udrive_api
git commit -m "Use compact Admin UI and delete rejected verification files"
git push origin main
```

Deploy `udrive-api` first, then `udrive-admin`. No database migration is required.
