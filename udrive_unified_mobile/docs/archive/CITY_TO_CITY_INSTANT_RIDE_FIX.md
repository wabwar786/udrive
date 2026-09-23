# City-to-City Instant Ride

City-to-City is now a true **book-now / instant ride** flow.

- No 10-minute buffer.
- No 30-minute buffer.
- No pickup-time selector for City-to-City.
- On **Confirm Ride**, the mobile app sends `pickupAt` as the current time and `instantRide: true`.
- Backend accepts immediate pickup requests when `instantRide` is true (with only a small negative clock-skew tolerance).
- The 30-minute minimum remains only for scheduled/advance bookings such as Tours.

Customer flow: Destination → Choose ride → Confirm Ride → Finding Driver → Driver Found.
