# Test

1. Sign out and sign in once after deploying this hotfix.
2. Fill the complete Customer advance-booking form.
3. Wait several minutes if desired, then press **Find verified Drivers**.
4. Confirm POST `/api/v1/bookings/ride-requests` returns 200/201.
5. Confirm the request appears in Customer requests.
6. Login with a verified Driver and confirm it appears in Driver Live Requests.
7. Let the access token expire and repeat; the request should refresh/retry automatically.
8. Open two app tabs and trigger authenticated calls simultaneously; only one refresh should rotate the token.
