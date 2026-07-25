# Implemented

## Roles

- SuperAdmin
- Admin
- Manager

The existing development account `03000000099` is promoted to SuperAdmin by
migration 007.

## SuperAdmin-only controls

- Create portal users.
- Assign/remove SuperAdmin, Admin and Manager portal roles.
- Delete a Driver from operations.
- Delete a vehicle from operations.
- Permanently delete individual Driver/vehicle attachments.
- Reject a Driver and delete all uploaded attachments.

Driver and vehicle deletion is operationally permanent while historical
booking references are retained for audit and reporting. Uploaded files are
physically removed from the Railway volume.

## Attachment preview fix

- Preview uses document-ID endpoints instead of trusting old stored URLs.
- Absolute and relative legacy URLs are normalized.
- Storage lookup checks `/data/uploads`, the configured `UPLOAD_ROOT`, and
  legacy application upload folders.
- Missing metadata and missing physical files return separate clear errors.
- Images and PDFs are returned inline with authenticated Admin access.
- A SuperAdmin storage diagnostic endpoint is available at:
  `/api/v1/admin/verification/files/storage-status`.
