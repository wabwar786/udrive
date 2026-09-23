# UDrive Professional Tourism Flow V8

## Customer home
- Replaced static recent searches with live recent bookings from `AppController.liveBookings`.
- Tourism is now the primary large service card.
- Kept Travel within city, Private Vehicle, and Explore Kashmir as direct booking choices.
- Dark map-first layout and compact typography retained.

## Pricing
- Removed all hard-coded city and private-vehicle prices.
- Local/private rides now ask the customer to enter a fare offer.
- The offer is sent to verified drivers, who can accept it or send a counter-offer.
- Tours use real `pricePerSeat` and `wholeVehiclePrice` values from matching live marketplace packages when available.
- Every vehicle card shows both Per Seat and Full Vehicle pricing states.
- Added Per Seat / Whole Vehicle booking selector and seat quantity control.

## Find driver
- Added login validation and fare validation before submission.
- Correct booking type, seat count, customer offer, coordinates, date, and vehicle category are sent to the existing ride-request API.
- Successful requests open the existing Driver Offers screen.
- API errors now display a readable message.
