# Approved → Completed Ride Flow

## Customer
1. Approves one Driver fare.
2. Booking is created immediately and Driver Confirmed details are shown.
3. Customer can open live tracking, call the Driver, see agreed fare/vehicle/ETA and cancel before the trip starts.
4. Trip OTP is shown until the ride starts.
5. Driver arrival is reflected live.
6. Customer gives the 4-digit OTP only after boarding.
7. Live tracking switches from pickup to destination after OTP verification / TripStarted.
8. Completed status is shown after Driver completes the trip.

## Driver
1. Approved offer becomes an Active Ride on Driver Home.
2. Opening it automatically marks Driver En Route and starts GPS tracking.
3. Driver sees pickup navigation, Customer details, ETA and distance.
4. Driver marks Arrived.
5. Start Ride requires the Customer's 4-digit Trip OTP; backend validates the OTP hash.
6. After TripStarted navigation targets the destination.
7. Existing marketplace rule unlocks next 5 KM requests when the active Driver is within 1 KM of the current destination.
8. Driver completes the trip at destination.
