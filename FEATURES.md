# Changes

- Portal typography reduced to normal compact sizes.
- Driver verification review is more compact.
- Every Driver and vehicle attachment has a permanent Delete action.
- Deleting a required Driver attachment revokes Driver access and moves the application to Changes Required.
- Deleting a vehicle attachment moves the vehicle to Changes Required.
- Reject Driver is now Reject & delete files.
- Rejecting permanently removes all Driver identity files and all vehicle attachments from PostgreSQL metadata and Railway storage.
- Decisions and deletion actions remain in the audit log.
