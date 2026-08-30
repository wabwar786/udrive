# Admin Portal Railway Build Fix

## Error fixed

The previous image used `node:22-alpine`, where npm can fail during `npm ci`
with `Exit handler never called`. The previous `package-lock.json` also stored
private build-environment registry URLs.

## Changes

- Replaced Node 22 Alpine with Node 20 Debian (`node:20-bookworm-slim`).
- Removed private registry tarball URLs from `package-lock.json`.
- Added a public npm registry `.npmrc`.
- Enabled Next.js standalone output.
- Changed the runtime to the generated minimal `server.js`.
- Kept Railway's dynamic `PORT` support.

## Deploy the correction

Commit and push the changed files:

```bash
git add admin_portal ADMIN_RAILWAY_FIX.md
git commit -m "Fix Railway admin Docker build"
git push
```

If your repository root is the complete UDrive project, use:

```bash
git add .
git commit -m "Fix Railway admin Docker build"
git push
```

In Railway, keep the Admin service Root Directory set to:

```text
/admin_portal
```

Then deploy the latest commit. No custom build or start command is required,
because Railway will detect `admin_portal/Dockerfile` after applying the root
directory.
