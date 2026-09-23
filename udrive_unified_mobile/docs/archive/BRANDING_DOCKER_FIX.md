# Udrive Admin Branding Docker Fix

The Admin portal used static images from `/public/branding`, but the standalone Docker runner only copied `.next/standalone` and `.next/static`.

Fixed by adding:

```dockerfile
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
```

This makes the following runtime URLs available:

- `/branding/udrive-icon.png`
- `/branding/udrive-wordmark.png`

Only the Admin portal needs redeployment for this fix.
