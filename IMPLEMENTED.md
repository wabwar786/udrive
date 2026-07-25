# Implemented

## Verification workspace

- Drivers display in a compact table instead of large cards.
- Vehicles display in a compact table instead of large cards.
- 25, 50 or 100 rows per page.
- Previous/Next pagination.
- Search and status filtering retained.
- Keyboard-accessible rows.
- Clicking any row or Review opens the complete approval panel.
- SuperAdmin delete controls remain unchanged.

## Attachment preview compatibility

Each attachment now tries:

1. Its original stored `fileUrl`, which worked in the earlier portal.
2. The newer document-ID endpoint as a fallback.

The Admin token is sent only to the configured API origin.
