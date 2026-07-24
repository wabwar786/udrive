# Live Database/API Integration — Recommended Next Milestone

The UI currently runs from local dummy models through `AppController`.

Replace modules incrementally in this order:

1. Customer/Driver authentication and OTP
2. Driver identity and vehicle verification
3. Destinations, routes and road advisories
4. Driver packages and admin approval
5. Advance bookings
6. Tour-interest matching
7. Per-seat inventory and whole-vehicle locking
8. Customer/Driver fare offers
9. Package bookings and payments
10. Live location, chat and notifications
11. Trusted contacts, guardian links and safety incidents
12. Admin operations and reporting

All security-sensitive validation must be repeated on the server. Never trust prices, available seats, identity, approval status, location or payment state supplied by a mobile client.
