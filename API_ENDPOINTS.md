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

## Trip chat and passenger standing — rev 64

Both parties to a booking:

- `GET /api/v1/trips/{bookingId}/messages?after=<iso>`
- `POST /api/v1/trips/{bookingId}/messages`

Driver only:

- `GET /api/v1/trips/{bookingId}/passenger`

Every route proves the caller is one of the two people on the booking before it
returns anything. There is no inbox and no way to message someone you are not
currently travelling with — a Driver must not be able to keep contacting a
Customer after the ride. Reading the thread is what marks the other side's
messages read; a separate call could fail on its own and leave a badge that
never clears.

## Raise fare — rev 67

- `POST /api/v1/bookings/ride-requests/{rideRequestId}/raise-fare`
  `{ "customerOffer": 1800 }`

  Upwards only, and only while the request is still open. Existing Driver offers
  are left untouched: a quote was a response to the old figure, and repricing it
  would put words in the Driver's mouth.

## Demo marketplace — rev 67

`ENABLE_DEMO_MARKETPLACE` now defaults to **off**. It previously ran unless the
variable was explicitly `"false"`, so any deployment that had never heard of the
flag fabricated a counter offer from a seeded demo driver on every ride request.
Set it to `"true"` only for demos.

## Driver reputation — rev 70

- `GET /api/v1/trips/{bookingId}/driver`

  Customer only. The Driver's average rating, how many ratings it is built from,
  completed trips, and their five most recent published Customer reviews.
  Reviewers appear by first name only — a review is about the Driver, and the
  reviewer did not agree to be identified to strangers. Driver-written reviews
  of Customers are excluded; that is a different conversation.

## Share a live trip — rev 72

- `POST /api/v1/tracking/{bookingId}/link` `{ "expiresInMinutes": 180 }`
- `DELETE /api/v1/tracking/{bookingId}/link`

`CreateLinkAsync` and `RevokeLinksAsync` have existed in `TrackingService` since
phase 12 and **no route ever called them**, so the feature was written and then
unreachable. The public viewer at `GET /api/v1/public/tracking/{token}` was
already live and had nothing to view.

The token is returned once; only its hash is stored, so a link cannot be
recovered from the database later. The public view stops working the moment the
trip reaches TripCompleted or Cancelled — which is what makes it safe to put in
a family group chat.

## Driver document preview — rev 73

- `GET /api/v1/driver/documents/{documentId}/file`
- `GET /api/v1/driver/vehicle-documents/{documentId}/file`

Until now only Admins could open these files, so a Driver could upload a
photograph of their licence and never see what had arrived — they learned it was
blurred or upside down when it came back rejected, days later.

The ownership check is inside the SQL, not a test afterwards: a document id in a
URL must never be enough to read another Driver's CNIC. A missing record and a
missing file return different errors, because one means the upload never
completed and the other means storage lost it, and the fixes are different.

## Driver dashboard — rev 75

- `GET /api/v1/driver/dashboard`

  The signed-in Driver's own figures in one call: name, verification status,
  rating and rating count, completed trips, earnings today, earnings this month,
  trips today, and their five most recent Customer reviews.

  Money is counted in Pakistan time. A Driver finishing at 2am wants that fare
  in "today", and a UTC day boundary would move it five hours early — which
  reads as earnings vanishing overnight. Earnings come from completed bookings,
  so the figure is what was driven, not what has been settled.

## Driver prepaid commission — rev 76

Driver:

- `GET /api/v1/driver/wallet` — balance, minimum, commission %, whether requests
  are flowing, recent top-ups and recent charges.
- `POST /api/v1/driver/wallet/topups` (multipart) — amount, `senderReference`,
  optional screenshot. **Credits nothing.** A screenshot is a claim, not a
  receipt; crediting on upload would make the balance forgeable with an image
  editor.

Admin (`SuperAdmin,Admin,FinanceOfficer`):

- `GET /api/v1/admin/wallet-topups/pending`
- `POST /api/v1/admin/wallet-topups/{id}/review` `{ approve, notes }`

Approving credits `driver_wallets.commission_balance` and writes a ledger entry
in the same transaction, keyed `topup:{id}` so a retried approval cannot credit
twice. The update requires `status = 'Pending'`, so two admins pressing approve
at once credit once.

## Ask a driver to re-upload — rev 84

- `POST /api/v1/admin/verification/drivers/{driverProfileId}/documents/{documentId}/request-reupload`
- `POST /api/v1/admin/verification/vehicles/{vehicleId}/documents/{documentId}/request-reupload`

`{ "reason": "This file could not be opened. Please upload it again." }`

Marks that one document rejected with the reason, which is the state the Driver
app already unlocks for replacing. A Driver cannot replace a submitted document
on their own — deliberately, so a file cannot be swapped while it is under
review — so without this they are locked out of fixing the only thing standing
between them and approval.

Touches nothing else. Asking for a new licence does not make someone photograph
their CNIC again.

## Documents awaiting re-upload — rev 90

- `GET /api/v1/driver/pending-documents`

Documents an Admin has rejected or asked for again, each with how many rides the
Driver has completed since the oldest such request and how many remain before
requests stop.

**Two rides of grace.** A Driver mid-shift, possibly far from home, cannot
always photograph a licence there and then, and cutting their income off the
instant an Admin clicks a button turns an administrative request into a
punishment. Two is enough to finish what they are doing and not enough to ignore.

The limit is enforced in `GetEligibleRideRequestsAsync`, so a Driver who has run
out simply stops seeing requests rather than being refused after answering one.

## Service availability — rev 102

- `GET /api/v1/services` — anonymous. The customer app reads this before anyone
  signs in, and it is the same information the tiles display.
- `GET /api/v1/admin/services`
- `PUT /api/v1/admin/services/{serviceKey}` `{ isOpen, badgeLabel, closedMessage }`

Update only, never insert: each key maps to a screen in the app, so a key an
admin invented would render a tile that opens nothing.

**Customer-side only.** A closed service does not touch the Driver app at all —
drivers keep registering vehicles and admins keep verifying them, so the service
has a fleet on the day it opens. Without that the platform deadlocks: closed
because there are no vehicles, no vehicles because it is closed.

## Tile style versioning — rev 106

`GET /api/v1/places/tiles/v{v}/{z}/{x}/{y}` alongside the unversioned route.

The style was changed from dark to light and customers kept seeing dark tiles:
the URL had not changed, tiles are cached for a week, so browsers never asked
again — one phone showed light and another dark, same account, same moment.

Bump `PlacesController.TileStyleVersion` and `ApiConfig.tileStyleVersion`
together whenever the basemap style changes. Every tile becomes a new URL and
nothing stale can be served.

## One live ride per customer — rev 106

`POST /api/v1/bookings/ride-requests` now refuses while the customer already has
a request searching (`request_already_open`) or a booking under way
(`ride_in_progress`).

Without it a customer could put three requests out, take offers on all three,
and leave two drivers holding a booking for someone already in another car — and
those drivers had turned down other work for it.

## Driver location interval — rev 109

- `GET /api/v1/settings/tracking` — anonymous, `{ pingSeconds }`
- `PUT /api/v1/admin/settings/tracking` `{ pingSeconds }` (SuperAdmin, Admin)

Read by both apps: the Driver app to know how often to publish, the Customer app
to know how often to poll. They must agree — polling slower than the driver
reports throws away fixes already paid for in battery, and polling faster
returns the same point twice.

Stored in `system_settings` under `tracking.ping.seconds`, clamped 1–60. Below a
second the fixes arrive faster than GPS produces them; above a minute the map is
not live in any useful sense, and a value that breaks the product should not be
reachable by a typo.

## Operational radii — rev 111

- `GET /api/v1/settings/operations` — anonymous. Returns `pingSeconds`,
  `requestRadiusKm`, `nearbyRadiusKm`. `/api/v1/settings/tracking` is kept as an
  alias because the app already calls it.
- `PUT /api/v1/admin/settings/radius` `{ requestRadiusKm, nearbyRadiusKm }`

**Two radii, not one.** The request radius is reach — how far a driver may be
and still be offered the job, previously hard-coded at 5 km in the eligibility
SQL. The nearby radius is honesty — how far around themselves a customer is
shown vehicles, previously 5 km in the app and showing cars nobody was going to
wait for.

Clamped 0.5–50 and 0.2–25. A value that makes the platform stop working should
not be reachable by a typo in a text field.

## Commission — rev 116

- `GET /api/v1/driver/wallet/commission?take=50` — the driver's own ledger: one
  line per ride with the fare, the rate applied and the amount taken.
- `PUT /api/v1/admin/settings/commission` `{ percentage }` (0–40)
- `commissionPercentage` is returned by `GET /api/v1/settings/operations`.

**Charged at trip start, not completion.** A driver who finishes a ride and then
loses signal, closes the app or runs out of battery never sends the completion —
so the commission was never taken and the platform carried rides it was not paid
for. The trip start is the moment both sides have agreed: the passenger is in
the vehicle and has read out the code.

The rate on each ledger line is derived from what was actually taken against the
fare, not read from settings at display time. A driver looking back at last
month sees the rate they were charged, not today's.

## Driver wallet settings — rev 117

- `GET /api/v1/driver/wallet/topup-account` — the EasyPaisa number and account
  name a driver should send to.
- `GET|PUT /api/v1/admin/settings/wallet`
  `{ welcomeBonus, easypaisaNumber, accountName }`
- `welcomeBonus` also appears on `GET /api/v1/settings/operations`.

The welcome credit is paid inside the approval transaction and keyed on the
driver profile, so re-approving after a suspension pays nothing further.

The EasyPaisa number is a setting rather than app text: accounts get closed and
ownership moves, and a number baked into a release means money sent somewhere
nobody is watching until the next deploy.

## Vehicle picture upload — rev 121

`POST /api/v1/admin/vehicle-images/{category}` (multipart, `file`) —
categories: `bike`, `car`, `ac_car`, `hiace`, `coaster`.

Stores the file on the platform's volume and points the
`vehicle.image.<category>` setting at it. Pasting a URL still works.

A pasted URL puts the picture on somebody else's server, and those links rot — a
host changes a path, a search thumbnail expires, a site blocks hotlinking — and
the app quietly shows nothing. The admin preview still looks fine, because the
browser fetches it and the phone does not.

## Public vehicle pictures — rev 122

`GET /api/v1/vehicle-images/{owner}/{file}` — anonymous.

The upload endpoint returned a path under
`/api/v1/admin/verification/files/...`, which is **admin-only**. An `img` tag
cannot send a bearer token, so the portal's own preview could not load it and
the customer app certainly could not: the upload worked, the file was on disk,
and nothing could read it.

Deliberately narrow — one folder, `vehicle-images`, and nothing else. Driver
documents stay behind the authenticated route.

## Offer card — rev 124

- `GET /api/v1/offers/{offerId}/driver-photo` — the approved selfie of a driver
  who has offered on **your** ride request. A second route because the
  booking-scoped one cannot help: at offer time there is no booking yet.
- `offerCard` is returned by `GET /api/v1/settings/operations`.
- `PUT /api/v1/admin/settings/offer-card` `{ vehiclePhoto, driverPhoto, rating, rides, plate }`

`DriverOfferDto` gains `vehicleImageUrl` (the driver's own photograph of that
vehicle) and `driverHasPhoto`.

Rating and rides default to **false**, including when the setting is absent.
A missing answer should leave a rating hidden rather than show a zero nobody
asked for.

## Offer vehicle photograph — rev 126

`GET /api/v1/offers/{offerId}/vehicle-photo` — the `VEHICLE_FRONT` document for
the vehicle offered on **your** ride request.

`vehicles.image_url` is only ever set by the demo seed. A driver registering
through the app uploads their vehicle photograph as a *document*, which is why
the offer card fell through to a stock picture while the real one sat approved
in the admin portal.

`DriverOfferDto` gains `VehicleHasPhoto` alongside `DriverHasPhoto`.
