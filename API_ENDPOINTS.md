# Phase 13 API Endpoints

## Admin Finance
- `GET /api/v1/admin/finance/dashboard`
- `GET /api/v1/admin/finance/transactions?search=&status=&page=1&pageSize=25`
- `GET /api/v1/admin/finance/earnings`
- `GET /api/v1/admin/finance/wallets`
- `GET /api/v1/admin/finance/payouts`
- `PUT /api/v1/admin/finance/payouts/{id}`
- `GET /api/v1/admin/finance/refunds`
- `POST /api/v1/admin/finance/refunds`
- `PUT /api/v1/admin/finance/refunds/{id}`
- `GET /api/v1/admin/finance/commission-rules`
- `POST /api/v1/admin/finance/commission-rules` (SuperAdmin)
- `POST /api/v1/admin/finance/adjustments` (SuperAdmin)
- `POST /api/v1/admin/finance/reconcile-completed-trips` (SuperAdmin)

## Driver Finance
- `GET /api/v1/driver/finance`
- `POST /api/v1/driver/finance/payouts`

## Bookings — added in rev 51

- `POST /api/v1/bookings/ride-requests/{rideRequestId}/cancel`

  Cancels an open ride request and expires its pending Driver offers in the
  same transaction. Only valid while the request is `Open`,
  `SearchingDrivers` or `ReceivingOffers`; once an offer has been selected
  there is a booking, and `POST /api/v1/bookings/{bookingId}/cancel` applies
  instead. Returns `404 ride_request_not_cancellable` otherwise.

## Pricing rules — added in rev 56

Admin (`SuperAdmin,Admin,Manager,Operations,FinanceOfficer` read;
`SuperAdmin,Admin,FinanceOfficer` write; `SuperAdmin,Admin` delete):

- `GET /api/v1/admin/pricing-rules`
- `GET /api/v1/admin/pricing-rules/preview?serviceType=&distanceKm=&minutes=&lat=&lng=`
- `POST /api/v1/admin/pricing-rules`
- `PUT /api/v1/admin/pricing-rules/{id}`
- `DELETE /api/v1/admin/pricing-rules/{id}`

Customer:

- `GET /api/v1/catalog/service-rates?serviceType=City&lat=&lng=`

  `lat`/`lng` are the pickup and are optional. With them, any active pricing
  rule covering that point today overrides the flat `service_vehicle_rates`
  figures. Without them the flat rates are returned unchanged, so an older app
  build prices exactly as it did before.

## Tour rates — added in rev 57

Driver (sets their own price; works on a verified vehicle, unlike the vehicle
record itself, because a price is commercial rather than compliance):

- `GET /api/v1/driver/marketplace/tour-rates`
- `PUT /api/v1/driver/marketplace/tour-rates/{vehicleId}`

Customer:

- `GET /api/v1/catalog/tour-rates?lat=&lng=&radiusKm=150`

  Per category: how many tour-ready vehicles have published a price, and the
  lowest, median and highest per-day figure among them. A range, not a
  recommendation — the admin's per-kilometre rules do not apply to Tour.

## Fixed per-seat route fares — added in rev 58

Admin:

- `GET /api/v1/admin/seat-fares`
- `POST /api/v1/admin/seat-fares`
- `PUT /api/v1/admin/seat-fares/{id}`
- `DELETE /api/v1/admin/seat-fares/{id}`

Customer:

- `GET /api/v1/catalog/seat-fare?category=Coster&fromLat=&fromLng=&toLat=&toLng=`

  Returns the listed per-seat fare when both ends of the trip fall inside a
  route's circles, or no data when the route is not listed — in which case the
  app prices per kilometre as before. A route marked both-ways also matches
  travelled in reverse, and the labels come back the way the customer is
  actually travelling.

## Driver presence — rev 62

- `POST /api/v1/driver/marketplace/presence` now also sets
  `driver_profiles.is_online = true`. Publishing a position is what going online
  means; nothing in the system had ever set that column true, so the
  nearby-vehicles query — which requires it — excluded every driver.
- `POST /api/v1/driver/marketplace/presence/offline` clears it, for when the
  Driver app gets an online switch wired to the server. The ninety-second
  presence freshness window still hides a driver whose app has stopped.
