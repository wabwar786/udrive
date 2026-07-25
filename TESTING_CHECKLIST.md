# Testing Checklist

- [ ] Login as a Customer and confirm name/phone match `/api/v1/auth/me`.
- [ ] Pull-to-refresh Customer Home and confirm live bookings/packages update.
- [ ] Create a ride request and confirm offer count changes after Driver offers exist.
- [ ] Confirm an active booking displays its real reference, route, date, fare and assignment.
- [ ] Login/switch to Driver mode and confirm verification status matches the API.
- [ ] Confirm Driver request count matches `/api/v1/driver/marketplace/ride-requests`.
- [ ] Confirm registered vehicles match `/api/v1/driver/vehicles`.
- [ ] Open Vehicles and verify the live registration screen creates a database vehicle.
- [ ] Open Documents and verify live onboarding/document records are displayed.
- [ ] Open Earnings/Payouts and verify Finance API values are shown.
- [ ] Test empty account states with no bookings, packages or vehicles.
- [ ] Test API failure and retry behavior.
- [ ] Test English and Urdu modes.
- [ ] Run `flutter analyze` and `flutter build web --release`.
