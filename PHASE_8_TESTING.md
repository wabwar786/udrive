# Phase 8 test guide

## Test accounts

### New Customer

- Phone: any valid unused Pakistani mobile number
- OTP: `1234`

Expected: account is created as Customer and stays logged in after restart.

### Existing approved Driver

- Phone: `03000000001`
- OTP: `1234`

Expected: Customer and Driver modes are both available.

### Admin

- Phone: `03000000099`
- OTP: `1234`
- Page: `/verification`

Expected: Admin and Operations roles are returned and verification queues open.

## New Driver end-to-end test

1. Log in with a new Customer phone.
2. Switch to Driver mode.
3. Complete Driver profile.
4. Upload:
   - CNIC front
   - CNIC back
   - Driving licence
   - Selfie
5. Register a vehicle.
6. Upload:
   - Registration book
   - Vehicle front photo
   - Vehicle rear photo
   - Vehicle interior photo
7. Submit the vehicle.
8. Log in to `/verification` as Admin.
9. Open the vehicle and Verify it.
10. Return to mobile and submit the Driver application.
11. Open the Driver application in Admin and Approve it.
12. In mobile, press Refresh status or sign in again.
13. Confirm Driver mode opens.

## API smoke tests

```text
GET  /health/live
GET  /health/ready
POST /api/v1/auth/otp/request
POST /api/v1/auth/otp/verify
GET  /api/v1/auth/me
GET  /api/v1/driver/onboarding
GET  /api/v1/admin/verification/drivers
```

Protected endpoints must return `401` without a token and Admin endpoints must return `403` for a Customer token.
