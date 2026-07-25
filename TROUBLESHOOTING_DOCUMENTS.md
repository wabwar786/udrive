# Document Preview Troubleshooting

## Preview says "file not found"

Confirm the API Railway volume is attached at:

```text
/data/uploads
```

and the API variable is:

```env
UPLOAD_ROOT=/data/uploads
```

Files uploaded before a persistent volume was attached may have been
deleted during an earlier deployment. Those specific files must be
uploaded again by the Driver.

## Preview returns 403

Confirm the signed-in account has one of these roles:

- Admin
- Operations
- VerificationOfficer

## Metadata appears but image does not

Confirm `ALLOWED_ORIGINS` contains the exact Admin domain and deploy the
API after changing it.
