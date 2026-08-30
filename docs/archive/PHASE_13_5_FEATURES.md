# Phase 13.5 Features

## Customer mode
- Logged-in customer name and phone from the authenticated session.
- Live counts for active bookings, upcoming bookings and Driver offers.
- Current booking card using booking reference, route, schedule, Driver, vehicle, seats, fare and status returned by the API.
- Admin-approved live tourism packages with genuine seat availability and pricing.
- Pull-to-refresh, loading, API error and honest empty states.

## Driver mode
- Logged-in Driver name, phone-derived session identity and verification status.
- Live ride-request, verified-vehicle, active-booking and completed-booking counts.
- Latest real assignment from Driver package bookings.
- Live registered vehicles with verification status, capacity, readiness score and document count.
- Vehicle registration now opens the live API-backed onboarding flow.
- Documents menu now opens the live Driver verification/document flow.
- Payout menu now uses the live Finance screen rather than the legacy dummy wallet screen.

## Data integrity
- No fabricated customer, Driver, vehicle, fare, rating or booking values on the updated dashboards.
- Missing records display zero values or clear empty states.
- Existing authentication, mode switching, booking, operations, tracking and finance repositories remain unchanged.
