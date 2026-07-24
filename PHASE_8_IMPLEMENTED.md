# uDrive Phase 8 implemented

## Authentication

- Server-side OTP challenges with expiry, attempt limit and retry throttling
- Pakistani phone-number normalization
- JWT access tokens
- Rotating hashed refresh tokens
- Persistent sessions
- Logout from current device or all devices
- Token-version invalidation after verification/security changes
- Customer, Driver, Admin and Operations roles
- Same account can hold Customer and Driver roles

## Driver onboarding

- Live Driver profile stored in PostgreSQL
- CNIC and licence values stored as keyed hashes plus masked display values
- Emergency contact, address, languages, service areas and payout details
- Real multipart uploads for CNIC front/back, driving licence and selfie
- JPG, PNG, WebP and PDF validation
- MIME/signature, size, filename and path validation
- Protected files available only to authorized Admin/Operations users
- Approved and suspended profiles are locked until an Admin requests changes

## Vehicle registration

- Live vehicle database APIs
- Category, make, model, year, registration, colour and capacity
- Air conditioning, heating, 4x4 and tourism safety equipment
- Mountain-readiness score
- Real registration/photo/document uploads
- Required registration book, front, rear and interior evidence
- Optional insurance and fitness certificate
- Verified and suspended vehicles are locked until an Admin requests changes

## Admin verification

- Live `/verification` Admin screen
- Admin OTP login
- Automatic access-token refresh
- Driver queue, details, masked identity data and protected evidence
- Vehicle queue, evidence and mountain-readiness display
- Vehicle Verify / Changes Required / Suspend actions
- Driver Approve / Changes Required / Reject actions
- Driver approval requires all identity evidence and at least one verified vehicle
- Approval grants Driver role; rejection/suspension revokes it
- Audit log records

## Mobile integration

- Dummy login replaced by live API OTP
- Access/refresh tokens stored through secure storage
- Session restored on app launch
- Automatic token refresh on HTTP 401
- New accounts start in Customer mode
- Driver mode is gated by live approval status
- Real Driver onboarding and vehicle-registration screens
- Existing tourism UI and dummy booking/package/safety workflows remain available

## Database migration

```text
004_phase8_authentication_and_verification.sql
```

It adds user roles, OTP challenges, refresh sessions, token versioning, Driver review fields and the seeded Admin account.
