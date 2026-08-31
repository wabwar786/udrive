# Revision 51 — movable Home card, one-tap destination, real pricing, driver offers

Three things were asked for. The third turned up two pricing bugs that had to be
fixed before the rest of it made any sense.

**Deploy both services.** This touches `Controllers/`, `Services/` and
`Migrations/`, so a mobile-only deploy leaves the cancel button and the Hiace
rate broken.

---

## 1. The booking card can be pulled over the map

`customer_home_screen.dart`

A grab handle sits directly above "Where to?" — outside the scroll view, so it
stays reachable however far down the card you have scrolled. Tapping it, or
flicking it up, lifts the card over the map; tapping again drops it back. The
map band is an `AnimatedContainer` that goes from 52% of the screen to about
20%.

The map is not hidden completely. Pickup is set by the centre pin, and a
customer cannot confirm a pickup they cannot see.

Resizing the map does not rewrite the pickup: the camera target does not change
when the viewport does, so the existing 40-metre guard in `_onMapSettled`
swallows the resulting idle event without spending a geocode.

## 2. Tapping a product goes straight to the destination field

`customer_home_screen.dart`, `place_search_screen.dart`

`_selectService` already opened the destination search — but only when the
destination was empty. The condition is gone: tapping Ride, Tour, Coster or Bike
now always opens it, and `PlaceSearchScreen` already focuses its field on the
first frame, so the keyboard comes up with it.

Any existing destination arrives selected rather than sitting behind the cursor.
Tapping a product means starting the trip again, and clearing an old address by
hand is exactly the step this was meant to remove.

Hotel is excluded. That flow asks for a city and dates, not a destination.

## 3. Vehicles, fares and the offers screen

### Two bugs in how the fare was calculated

Both were in `vehicle_options_repository.dart`.

**The admin's rates were never being read.** The app looked for
`row['vehicleType']` and `row['category']`. The API serialises
`ServiceVehicleRateDto` in camelCase, so the field is `vehicleCategory`. Neither
key ever matched, `firstWhere` fell through to its `orElse`, and every fare on
every trip came from the built-in fallback table. Changing a rate in the admin
portal did nothing at all.

**`wholeVehicleRate` was being treated as a rate per kilometre.** Car's figure
is 1,600 — a flat whole-vehicle price. The code computed
`1600 × distanceKm`, so a ten-kilometre town trip would have been quoted around
PKR 16,000. The only reason nobody saw it is the first bug: the rates never
loaded, so the multiplication never ran on a real figure. Fixing the lookup
without fixing this would have shipped the mispricing.

### What the fare is now

```
fare = max(perKmRate × roadKm + 2 × minutes,  wholeVehicleRate)
```

rounded to the nearest 5 rupees.

`per_km_rate` is what scales with the trip — it arrived with migration 025 and
the app had never used it. `whole_vehicle_rate` and `per_seat_rate` are flat
**minimums**: a short trip still costs the floor, because a driver does not
start the engine for less. The three columns now carry SQL comments saying so,
because the distinction is not guessable from the names.

Per seat is the whole-vehicle fare shared across the seats with a small margin,
never below the admin's own per-seat floor.

### The stepper floor

Was half the recommendation — a guess. It is now the admin's minimum for that
vehicle. The minus button disables at the floor and the caption says "Minimum
fare for this trip" rather than a percentage that implies there is further to
go. Typing a figure obeys the same floor; letting one route around it would only
mean waiting for offers that never come.

### Four vehicles

Car, Bike, Coster, Hiace. "AC Car" is gone.

"Coaster" is now **"Coster"**, because that is the spelling in
`udrive.service_vehicle_rates` and the two never matched. Driver eligibility does
not filter on category — `GetEligibleRideRequestsAsync` matches on distance and
presence only — so the rename affects pricing and labels, nothing else. Both
spellings still resolve to the `vehicle.image.coaster` setting, so an already
uploaded photograph was not orphaned.

Hiace had no row in the rate table at all. Migration `033_travel_vehicle_rates`
adds it for City and PrivateVehicle. Rickshaw is set `is_active = false` rather
than deleted, so an admin who wants it back flips one column.

### The offers screen

`driver_offers_screen.dart`, rebuilt to the design supplied.

The route sits behind the offers on a non-interactive map — non-interactive
because the customer is choosing a driver, and a map that pans under a list they
are scrolling fights them. The route points are passed down from
`VehicleChoiceScreen` rather than fetched again, so drawing the line costs no
Directions call.

The list is `Flexible` with `shrinkWrap`, so it takes only the height it needs
and the map stays visible while offers arrive.

Each card: fare large, arrival beside it in grey, then the driver's initials
avatar, name, rating, completed-trip count and vehicle, then Decline and Accept.
The ten-second decision window drains across the Accept button itself, so the
pressure is on the control rather than in a number off to one side. The two
halves are flexed rather than fractionally sized — a `FractionallySizedBox` with
no height factor collapses to nothing inside a `Stack`.

The offers endpoint exposes no driver photograph, so the avatar is initials. A
generic silhouette on every card would distinguish nothing.

**Cancel request** needed an endpoint. `POST
/api/v1/bookings/ride-requests/{id}/cancel` sets the request to `Cancelled` and
expires pending offers in the same transaction, so no driver is left holding an
offer against a request that no longer exists. It only works while the request
is open; once an offer is selected there is a booking, with its own cancellation
rules.

The client ignores the result. The request expires on its own, so a route an
older API does not have must never trap the customer on a screen they have asked
to leave.

## 4. Home laid out to the reference screenshot

`customer_home_screen.dart`

The sheet is now two rounded panels on a near-black page rather than one flat
surface: **what you are booking**, then **where you are going**. Two greys one
step apart is what gives the layout depth — a single surface ran every block
into the next, and the map fade now resolves to the page colour rather than to
the old panel colour.

**One question instead of two fields.** The pickup and destination rows are
replaced, before a trip exists, by a single large control reading **"Where to &
for how much?"**. Naming the price is the whole model; a customer who does not
learn that until the next screen is being asked to discover it. Pickup drops to
one quiet tappable line underneath, because the map already shows it on its own
pin — but it stays tappable, since a wrong pickup has to be fixable without
first choosing a destination.

**Product tiles read label-first.** Title and subtitle at the top, oversized
artwork bleeding off the bottom corner, no icon chip. The eye lands on the word
and the picture confirms it; the other way round, the tiles read as pictures
with captions.

**Three products, not eight.** The reference carries City Rides, City to City,
Couriers, Freight, Flights, Hotels, Car Rental, Events and Buses. UDrive has
Ride now, Tour and Hotel, and adding rows of tiles for things that do not exist
yet would be advertising them.

**Recents book in one tap.** Tapping a recent destination now goes straight to
the vehicle picker. It is a place the customer has already been to and has just
named again; a confirm button after that asks them to agree with themselves. The
rows lost their dividers and trailing chevrons — inside a panel they already
read as a list.

**Hotel works from the home screen.** It was gated behind a destination it never
used, so selecting it and then finding nothing happened was the only outcome
unless a destination happened to be set. Hotel now opens its own city/dates/
guests panel immediately, and the route rows stay hidden for it.

## 5. Drivers on the map, from the video

The reference app draws nearby drivers as **small top-down cars lying on the
road, rotated to the way they are facing** — no pin, no label, no price bubble.
UDrive was drawing them as Google's default azure teardrop pins with a
`"Car · 1.2 km"` info bubble on each. That is a different thing entirely: a pin
says something is here, a car pointing down a street says a driver is here and
which way they are going, which is the question the customer is actually asking.

### Heading, end to end

Rotation needs a bearing and presence was storing only position and accuracy.

- Migration `034_driver_presence_heading` adds a nullable `heading` column.
- `DriverPresenceUpdateRequest` and `NearbyVehicleDto` carry it.
- The presence upsert keeps the last known heading when a new reading has none
  (`COALESCE`), so a parked car stays pointing the way it was last driving
  instead of snapping to north.
- The Driver app sends `position.heading`, filtering the negative and non-finite
  values a stationary phone reports.
- Heading is **not** fuzzed the way the coordinates are. Which way a car points
  reveals nothing about where it is, and rounding it would only make the marker
  face wrong.

### The sprites are drawn, not shipped

`ud_vehicle_sprites.dart` paints car, bike and van shapes with `Canvas`. Two
reasons over shipping PNGs: they stay crisp at any device pixel ratio, where a
fixed asset either blurs on a dense screen or wastes bytes on a cheap one; and
they take their colours from the theme, so they cannot drift out of step the way
a hand-exported image quietly does.

Rasterised once per shape per pixel ratio and cached — Home rebuilds its markers
on every presence poll, and rasterising per vehicle per poll is the kind of work
that shows as stutter on the phones most of these customers have. Google gets a
bitmap with `flat: true`, `rotation`, and a centre anchor; `flutter_map` gets the
same shapes through a painter, so the online and offline maps cannot disagree
about what a car looks like.

A bike and a coach are unmistakably different objects from above, so `Bike` gets
two wheels and a crossbar and `Coster`/`Hiace` get a boxier van outline.

### Pickup pin

Now a white tile with a waiting passenger on it, a stem and a blue ground dot,
with the "Pickup point / <place> ›" chip above it. White because the map beneath
is dark and already carries a green route line and green vehicle lamps — a green
pin disappeared into its own app.

### While waiting for offers

Status, an elapsed clock and a working bar, over the vehicles the request went
out to and the area it covered.

The clock counts **up**. The reference shows a sixty-second countdown, but a
UDrive request stays open for an hour — a bar draining to zero would be telling
the customer their request is about to die when it is not. For the same reason
the search circle is static rather than a pulsing sweep: animating it would
rebuild the whole map every frame for an effect that costs more than it gives.

The driver count beside it is real, read once from the nearby-vehicles endpoint.
Waiting in front of an empty map gives no way to tell whether the request went
anywhere; seeing the cars it went to answers that without asking.

## 6. Splash, sign-in and the CTA

### Splash

One mark, centred, on the app's own dark background. It was carrying the
wordmark, a tagline and three photographs of vehicles stacked at angles — a lot
of screen to build and throw away in under a second, and the first impression
the app made.

### Sign-in

The car illustration sat in the upper third and the form sheet rode over the top
of it, so on most screen sizes the vehicle was cut in half by a panel edge. The
artwork and the form were each laid out as though the other were not there.

The photograph is gone. What replaces it is drawn rather than placed: a vertical
wash and two soft brand circles, all of them out past the edges. Shapes have no
proportions to protect, so nothing can be cropped through the middle however
tall the phone or however far the keyboard pushes the form up.

The layout is now logo centred, wordmark and one line under it, then the
"Continue with mobile" card directly beneath. The wordmark that used to sit in
the top-left corner is gone — two logos on one screen meant neither read as the
mark. Only the language switch stays up there.

`ServiceIllustration` now has no callers. Left in place rather than deleted; it
is a public widget and may be wanted again.

### The card stays up once a destination is chosen

Picking a destination lifts the booking card over the map and leaves it there.
From that point the card carries the route, the vehicle panel and the button,
and letting it settle back would drop the button under the fold — the customer
would choose a place and then have to scroll to act on it. Hotel lifts on
selection for the same reason, since it opens its panel immediately.

The handle still works, so anyone who wants the map back can have it. It just no
longer happens on its own.

### "Find Now"

The button read "Find a Car", "Find a Bike", "Find a Coster / Hiace" depending
on the product selected. The vehicle is actually chosen on the next screen, so
naming one here promised a decision that had not been made — and the label
changing under the customer's thumb made it look like a different button each
time. It is "Find Now" for every vehicle. Hotel and Tour keep their own words,
because they lead somewhere genuinely different.

---

## Not done

- **Per-vehicle ETAs.** Still a Distance Matrix call per category per search,
  still a billing decision rather than a code one.
- **Auto-accept.** The reference has an "Auto-accept an offer of PKR X up to
  5 min away" toggle. Not built: it needs a server rule, and a switch that
  silently does nothing is worse than no switch.
- **Raising your fare while waiting.** The reference keeps the stepper live on
  the searching screen. There is no endpoint to change `customer_offer` on an
  open request, so the fare is fixed once sent.
- **"Searching further — expanding search area."** Driver eligibility uses a
  fixed radius, so there is nothing to expand and saying otherwise would be a
  caption over a thing that is not happening.
- **A `Coster` row in the demo fleet.** The seeded coaches in migration 010 are
  category `Bus`. Pricing does not read that column, so nothing is broken, but
  the demo fleet and the rate table disagree and it is worth tidying.

## Before deploying

```bash
cd udrive_unified_mobile && python3 tool/audit_structure.py
```

Clean as of this ZIP. Push, wait for the Actions run to go green, then deploy
**both** `udrive-api` and `udrive Mobile`. Hard refresh afterwards and check the
build label reads `rev 54`.
