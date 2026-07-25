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
