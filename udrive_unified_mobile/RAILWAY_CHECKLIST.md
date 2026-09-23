# Railway Checklist

API service variables:

```env
UPLOAD_ROOT=/data/uploads
AUTO_APPLY_MIGRATIONS=true
ENABLE_SWAGGER=true
```

The API service must have a persistent volume mounted at:

```text
/data/uploads
```

After API deployment, log out and back in with:

```text
03000000099
OTP 1234
```

The JWT must then contain `SuperAdmin`.

When an attachment card says the database record exists but the physical file
is missing, that binary was lost before the volume was attached. It cannot be
reconstructed from metadata and the Driver must upload that specific file
again.

## File storage (uploads) — required

Driver documents, vehicle photographs and payment screenshots are written to
`UPLOAD_ROOT`. Without a volume they live inside the container image and **every
deploy destroys them**; the database keeps the rows, so the admin portal shows a
document that exists with a file that does not.

On the `udrive-api` service (not PostGIS — they are separate containers with
separate filesystems):

1. Volumes → add one with mount path **`/data`**
2. Variables → **`UPLOAD_ROOT=/data/uploads`**
3. Redeploy

Then open **Admin → Diagnostics → File storage** and confirm all three:

| Row | Must say |
|---|---|
| Upload root | `/data/uploads` |
| Survives a deploy | Yes |
| Writable | Yes |

The container starts as root only long enough to create that directory and give
it to uid 10001, then drops privileges — a Railway volume is mounted owned by
root, and the API runs unprivileged, so without that step it cannot write to its
own upload directory. Anything chowned at build time is hidden the moment the
volume is mounted over it, which is why this happens at start-up instead.
