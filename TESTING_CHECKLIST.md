# Test checklist

- Log in as a Customer.
- Leave the form open long enough for the access token to approach expiry, then submit.
- Confirm the request is created instead of showing a false session-expired error.
- Confirm `GET /api/v1/bookings/ride-requests/my` contains the new request.
- Log in as an approved Driver with a verified vehicle.
- Open Driver mode > Live requests.
- Confirm the customer request appears automatically within 20 seconds.
- Submit a Driver offer.
- Confirm the Customer offers screen receives the offer.
- Verify an unapproved Driver receives HTTP 403 and cannot view live requests.
