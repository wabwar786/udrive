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

## 7. The vehicle screen, rebuilt

### The photograph takes the screen

It was 132 px tall — a thumbnail with a label under it. It is now 38% of the
screen height (clamped 230–400), inside a rounded frame with `BoxFit.contain`,
so the whole vehicle is visible and never cropped. A bike with its front wheel
cut off by a frame edge reads as a mistake, and this picture is the main thing
the customer is judging.

### Swipe the photograph to change vehicle

The photograph is now a `PageView` over the four vehicles in order: Car, Bike,
Coster, Hiace. Swiping right-to-left moves forward through them, left-to-right
back — Car → Bike → Coster → Hiace and back again.

It is the biggest thing on the screen and therefore the most obvious thing to
swipe. Making that gesture do the work means four vehicles can be compared with
the thumb where it already is, instead of reaching up to the pill row every
time.

The pill row and the pager stay in step both ways: tapping a pill animates the
photograph across, swiping the photograph scrolls the matching pill into view.
Swiping to the fourth vehicle used to leave its pill off the right edge, which
made the row look like it had stopped responding.

Dots under the photograph show which of how many. Swiping is not visible the way
a button is, so something has to say the gesture exists.

### Name small, under the picture

Dropped from 22 px to 16, with seats and description on one line beneath. The
picture already says which vehicle this is; the words confirm it rather than
announce it.

### The fees note moved to the fare

`Tolls, parking and entry fees are not included` now sits directly above the
amount, because it is a caveat about the amount. At the bottom of a scrolling
list it was reached only by customers who happened to scroll — never by the ones
who went straight to the fare, who are exactly the ones it is for. Shortened to
one line to earn its place there.

### Hiace has no photograph

There is no bundled Hiace image. It was falling back to the coaster photo, which
was survivable at thumbnail size and is not at half a screen — a picture of the
wrong vehicle on the largest element of the screen. It now shows the Hiace icon
instead.

**Upload a real one** in the admin portal against `vehicle.image.hiace` and it
replaces the placeholder immediately. The same applies to any category whose
photo is unset.

## 8. Pricing you can set from the admin portal

Rates were only changeable by writing SQL against `service_vehicle_rates`, which
holds one flat figure per vehicle and nothing else. Charging more on a Sunday,
or more in Muzaffarabad than in Rawalakot, meant editing that single row each
time and losing whatever it said before.

### Admin → Pricing & fares

A new section in the portal. Each rule is:

- a **rate per kilometre**, a **minimum fare** and a **per-minute** figure
- optionally narrowed to **particular days** — seven toggles, none selected
  means every day
- optionally narrowed to an **area** — pick a town from the list or type a
  centre and radius

Above the table is a **fare preview**: enter a distance, a time and an area and
it shows what each vehicle would be quoted right now, with the rule that
produced it named. Without this the only way to test a rate change was to book a
ride, so a mistyped per-km figure reached customers before it reached anyone who
could see it was wrong. The preview rounds the same way the app does, so the two
agree to the rupee.

### How a rule is chosen

Exactly one rule applies to any trip. Most specific wins: highest `priority`
first, then an area rule over a global one, then a smaller area over a larger
one, then named days over every day. Blending several would make the resulting
fare impossible to trace back to anything the admin typed.

The day is read in Pakistan time inside the query, so it does not depend on the
server's clock settings.

### The area is a circle

A centre and a radius, not a polygon. Drawing and editing polygons is a mapping
tool in its own right; a circle is something an admin can set from a place name
in a few seconds, and it is easily accurate enough to tell one town from
another. The portal lists the obvious centres as a shortcut, and the
coordinates stay editable for anywhere not on that list.

### Nothing changed on the day it shipped

The migration seeds one global rule per existing rate row, so the portal opens
to a filled table and every fare stays exactly where it was until someone
narrows a rule.

The customer app now sends the pickup with its rates request
(`?lat=&lng=`). A rate set for one town on particular days only reaches the
customer if the server knows where they are standing. Both parameters are
optional, so an older app build keeps pricing as before.

## 9. Rates per category, and tourism priced by the driver

### Each vehicle already had its own rate — now it is one screen

Pricing rules were always per category, so a bike could cost less per kilometre
than a car and a Coster more than both. But reading the four figures meant
opening four rules, which is a poor way to see a set of numbers whose whole
point is how they compare.

**Admin → Pricing** now opens on a four-row grid: Car, Bike, Coster, Hiace, each
with its rate per kilometre and its minimum fare, editable in place and saved
together. Only the rows actually changed are sent — rewriting all four would
bump `updated_at` on rules nobody touched, and that timestamp breaks ties
between equally specific rules.

Anything more specific — a weekend rate, a rate for one town — still goes in the
rules table below it.

### Tourism is priced by the driver

The admin's per-kilometre rules cover City and PrivateVehicle and stop there.

A multi-day trip through the mountains is not a metered ride. The driver is away
from home, feeding and housing themselves, on roads that punish a vehicle. What
that is worth is a judgement only the person driving can make, and one central
per-km figure cannot express it. So the platform does not try.

**Driver app → Vehicles → "Set your tour rate"**: per day, a floor, an optional
per-km figure for long transfers, a note on what the price includes, and a
switch for whether the vehicle is offered for tours at all. Editable on a
verified vehicle, unlike the rest of the vehicle record — verification approves
what the vehicle *is*, and a driver should not need an admin before changing
what they charge.

**Customer side**, the tour panel now shows what drivers around them are
actually asking, by category, as a range for the trip length they picked. Before
this the fare field's only guidance was a placeholder, so the customer was
typing a number into silence.

It is deliberately a range and not an average. A single figure would read as an
official rate and hide that a car and a Coster are different propositions. The
middle figure is the median, so one operator asking 200,000 for a luxury coach
does not drag it away from what most drivers charge.

None of it is enforced. The customer still names their offer, the driver still
answers with theirs. These numbers only mean both sides start from something
real. The admin Pricing page says so in as many words, so nobody goes looking
there for a tour rate.

## 10. Coster per seat is a fixed route fare

A Coster running per seat in Kashmir is not a metered vehicle. It runs a known
route and every passenger pays the same known fare — Muzaffarabad to Rawalakot
is a price people already carry in their heads, not a number multiplied out of a
distance.

Pricing it per kilometre produced a different figure for every pickup pin, which
is neither how the route works nor what anyone expects to pay.

### Admin → Pricing → Fixed per-seat routes

Each route is: a vehicle, two ends, and one fare per passenger.

Both ends are a **labelled circle** — a town name, a centre and a radius —
because passengers board somewhere in Muzaffarabad, not at one coordinate. The
radius is what makes the name mean the whole town. Towns can be picked from a
list to fill the coordinates, and the label shown to customers stays editable.

**Applies in reverse** defaults on. Making an admin enter every route twice
would guarantee the two halves drift apart, and the return leg is quoted with
the labels the right way round for the direction actually travelled.

Where two routes both match, the tighter pair of circles wins: a fare written
for one town should beat one written for a whole valley that happens to contain
it.

### What the customer sees

On a listed route the fare panel shows the listed fare, captioned with the route
name, and the plus and minus buttons are **gone**. Buttons that refuse to move
are worse than buttons that are not there — the customer presses them, nothing
happens, and they are left wondering whether the app is broken. Typing a figure
is blocked in the state as well, not only in the widget tree, because a pricing
rule should not depend on which control happens to be rendered.

Changing the seat count still recalculates: the listed fare times the number of
seats.

### What is unaffected

**Hiring the whole vehicle.** A Coster booked outright is still priced per
kilometre and still negotiable, because that genuinely is a negotiation.

**Any route not listed.** Per-seat trips fall back to per-kilometre pricing
exactly as before, so nothing changed until the first route was entered. The
lookup runs after the vehicle options are already on screen and returns null on
failure — a customer should not wait on a request that usually comes back empty,
and a lookup that fails must never block a booking.

## 11. Rate shown, drivers on a map, driver card rebuilt

### The customer can see the admin's rate

Under the vehicle, in the admin's own numbers: `PKR 65 / km · × 28 km · min PKR
1,600`. A price with nothing behind it is something a customer can only accept
or reject, never check. With the rate and the distance in front of them they can
do the multiplication themselves — and so can whoever set the rate, which is how
a mistyped figure gets caught before it reaches anyone else. Hidden on a fixed
route fare, which has no per-kilometre basis to show.

While adding it I found a related fault: `perKmRate` of **zero** was being taken
literally. An API that has not run the per-km migration returns 0 for that
column, and the app was pricing every trip at its bare minimum rather than
falling back to the built-in rate. Zero now means missing.

### Drivers within 3 km, on a map you can move

The vehicle screen has a two-way switch above the photograph: **Vehicle** or
**Drivers nearby · N**. The map takes the same space rather than being bolted
underneath, so neither view is squeezed and the swipe gesture on the photographs
never fights a map pan.

The map is interactive — zoom and pan — because the entire point is that the
customer can zoom out and see how far the nearest driver actually is. The 3 km
circle is drawn, and drivers appear as the same top-down cars Home uses. Read
once, not polled: this screen is a decision about price, and vehicles sliding
around underneath while someone sets a fare is motion without information.

### The driver's request card

The old card led with the customer's name and initials — the one thing that does
not affect the decision. It is now, in order:

- **the money**, at 26pt, because that is what is being decided
- whole vehicle or seats, and **how long the trip runs**
- **pickup, and how far it is from where the driver is standing** — a label
  alone does not say whether answering means a two minute drive or twenty, and
  that is most of the judgement
- destination and the pickup time
- **Route**, opening the existing map

Trip and pickup distances are straight-line with a road factor rather than a
Directions call. One call per card per five-second refresh would be an expensive
way to fill in a subtitle, and the number only has to answer "near me or not".
The distance from the driver is omitted entirely until presence has reported —
a guessed figure would send someone towards a pickup they cannot reach.

### One decision window, both sides

`AppConfig.decisionSeconds` is 15 and both sides read it. A driver seeing a
request and a customer seeing that driver's offer are two halves of the same
decision; separate windows meant one side was always waiting on someone the
other had already timed out.

The driver's card shows the time draining across its top edge and turns red
under five seconds. A request past its window disappears from the list — a
customer should not receive an offer from a driver who saw the request four
minutes ago and has since driven away. The deadline starts when *this* driver
first sees the request, not from a server timestamp.

## 12. After the accept: tracking, road routes, real ETAs

### The straight line was the bug behind both screens

Both live screens drew a straight line from the Driver to their target and
estimated arrival from that distance over an assumed speed.

In Azad Kashmir that is not an approximation, it is a different number. A road
through the mountains is routinely two or three times the crow-flight distance,
so a Customer told "4 minutes" waited twenty, and a Driver planning their next
hour planned it wrong.

`LiveLeg` now asks the routing service for the actual road and re-asks only when
the Driver has moved more than 150 metres — roughly a street. Below that the
road ahead is unchanged and the redraw would be invisible, so it would be
spending a paid request to move a line by a few pixels. A failed lookup keeps
the previous route rather than blanking the map over one bad request.

Distances are labelled **"by road"** or **"direct"**, so the fallback is never
passed off as something it is not.

### The camera stopped fighting the user

Both maps recentred on every poll — the Customer's every five seconds. Zooming
out to see the whole approach was impossible; the map snapped back before you
finished looking. Once either side pans or zooms, the camera is theirs and
auto-follow stops.

The Customer's map also frames the **whole route** rather than centring on the
car. "Where is it and how far off" is the question, and a close-up of the car
answers neither half.

### Accepting a driver goes straight to the map

The confirmation sheet is gone from the normal path. The moment a driver is
confirmed the only question left is where the car is and when it arrives — and
that is a screen, not a summary. Driver, vehicle, fare and OTP are all on the
tracking screen anyway, so the sheet was a list of things to dismiss before
seeing the one thing wanted. It still appears if the trip cannot be opened,
because a summary beats nothing.

### Turn-by-turn is handed to the phone

The Driver screen shows the route, the road distance and the arrival time, and a
**Directions** button that opens their own navigation app at the pickup — `geo:`
first so Android uses whatever they actually run, the Maps web URL as fallback
for iOS and browsers.

Not built in. Doing it here would mean re-implementing lane guidance, rerouting
and voice for roads Google already covers, and doing it worse — on mountain
roads where being wrong costs a driver an hour.

## 13. Why no vehicle has ever appeared on a customer's map

`driver_profiles.is_online` was **never set true by anything**. The only write
to that column in the entire codebase set it to `false`, in the admin suspension
path. The nearby-vehicles query requires `dp.is_online = true`, so it filtered
out every driver, always — no icon has ever been missing from the map, because
no vehicle was ever returned to draw.

Publishing a position now sets it. That is what going online means, and the
Driver app posts presence every fifteen seconds while its switch is on. The
ninety-second freshness window still hides a driver whose app has died.

A `presence/offline` endpoint clears the flag for when the Driver app's online
switch is wired to the server. Right now `_DriverCommandHeader` — which owns
that switch — is defined but never rendered, so the flag is only ever raised by
presence and lowered by suspension.

## 14. "This offer is no longer available"

An instant-ride offer expired **35 seconds** after the Driver sent it, plus a
12-second grace on select.

That was shorter than the round trip the offer has to survive: the Driver's own
decision window, the poll that carries the offer to the Customer, the Customer
reading it, and the tap. The offer could be dead before it ever reached the
screen — so the Customer pressed Accept on something that had looked live a
second earlier and was told it no longer existed.

Now two minutes, still bounded by the request's own expiry so an offer can never
outlive the request it answers.

The client also caps its own decision window at the server's expiry for that
offer. The local window starts when the Customer *sees* the offer, which is
already later than when it was sent, so left alone it could keep the Accept
button alive past the point the server would honour it. A button that fails when
pressed is worse than one that has gone.

## 15. The Accept button

It was draining from full brand colour to 38% opacity as the window ran down,
which left the main action on the screen washed out for most of its life — and a
half-faded button reads as disabled, which is the opposite of what it is.

Solid green now, full width. The countdown moved to a 3px bar along the bottom
edge: still visible, no longer taking the colour out of the thing the Customer
is meant to press.

## 16. "This offer is no longer available" — the real cause

The expiry theory in rev 62 was not it. A Driver accepted, sent a fare, and the
Customer pressed Accept five seconds later and still got the message. Five
seconds is nowhere near any expiry window.

**The transaction was losing a race with its own screen's polling.**

`SelectDriverOfferAsync` ran at `IsolationLevel.Serializable`. Meanwhile
`ExpireRideRequestsAsync` — three UPDATE statements over `ride_requests` — ran
at the top of *every* list call: the Customer's ride-request poll, the Driver's
marketplace poll, the offers screen's own refresh. All of those fire every few
seconds while the offers screen is open.

Those UPDATEs took row locks on the exact rows the Serializable transaction was
reading with `SELECT ... FOR UPDATE`, and Postgres resolved the conflict by
aborting one side. The abort surfaced in the app as a generic failure, and the
Customer was told to go and find another Driver — for an offer that was
completely fine.

Three changes:

**The sweep is throttled to once every thirty seconds per process.** It is
housekeeping, not a read. Nothing expires late as a result: every read path
already filters on `expires_at` in its own WHERE clause, and a request that ages
out between sweeps is caught by the next one.

**The select dropped to `ReadCommitted`.** The `FOR UPDATE` on the request row
is what actually stops two Customers taking the same offer. Serializable added
nothing on top of that except a much wider surface for 40001 aborts against
unrelated writes.

**The client stopped throwing the reason away.** `_approveOffer` refreshed state
first and *then* read `controller.marketplaceError` — but a successful refresh
clears that field, so the real message was destroyed and every failure became
"this offer is no longer available". The error is now captured before anything
else runs and shown as the server wrote it. "Choose another driver" is the wrong
advice for most of what can actually go wrong here.

## 17. What each side sees once the ride is on

The Customer's tracking screen already carries the driver's name, vehicle,
registration, fare, booking type, OTP, a call button and the live road ETA.

The Driver's panel now shows who they are collecting: **passenger count,
booking type and payment status** on one line under the name, and any
**instructions the Customer left** in a highlighted box. Buried anywhere else,
a note the Customer took the trouble to write may as well not have been written.

## 18. The accept bug, actually found

It was never a timing problem, and the two previous theories — expiry, then
transaction contention — were both wrong. It failed on the first attempt, the
fastest attempt and every attempt, because the statement could not commit at
all.

At the end of a successful selection, `SelectDriverOfferAsync` records the
outcome against the Driver's decision on that request:

```sql
INSERT INTO udrive.driver_ride_request_decisions (..., decision, ...)
VALUES (..., 'Accepted', ...)
```

Migration 012 constrained that column:

```sql
CONSTRAINT ck_driver_request_decision CHECK (decision IN ('Rejected', 'Offered'))
```

`'Accepted'` was never allowed. Postgres raised 23514, the whole transaction
rolled back, and the customer got a generic failure — which the app rendered as
"this offer is no longer available. Please choose another driver."

Everything before it was correct. The booking, the trip operation, the
assignment and the notification were all written and then thrown away four
statements later.

Migration 039 widens the constraint. The code has written `'Accepted'` since the
marketplace flow was built, so the constraint is what was wrong, not the value.

**Why it hid for so long:** `GlobalExceptionHandler` mapped CHECK violations
into the catch-all 500, "This service is temporarily unavailable." A schema
disagreement was being reported as a server hiccup. Check and foreign-key
violations now return 409 and name the constraint and table, so the next one
takes a minute rather than three rounds of guessing.

The two earlier changes were still worth making — the expiry sweep really was
firing on every list call, and Serializable really was over-strict — but neither
was this bug.

## 19. New palette: deep teal and amber

Lime on black had two problems. Lime is what every ride-hailing app in the
region already uses, so nothing on screen said which app you were in. And a
green action colour sat one hue away from the green success states and the green
route line, which left the button competing with the map underneath it.

| Role | Hex |
|---|---|
| Background | `#0A1614` |
| Surface | `#102422` |
| Surface alt | `#1A3330` |
| Border | `#24423E` |
| Primary (structure) | `#0E4F4F` |
| Secondary (action) | `#F5A524` |
| Ink on action | `#1A1200` |
| Text / secondary / disabled | `#F2F7F5` / `#9BB3AE` / `#5F7A75` |
| Success / danger / warning / info | `#2FB27C` / `#E5484D` / `#E8A33D` / `#4C9AFF` |

Ink on the action colour is near-black, not white: amber is a light colour and
white on it fails contrast at button sizes.

The Ride product tile moved from the action colour to teal. A product tile and
the button that acts on it should not be the same hue, or the tile starts
reading as something already pressed.

The live trip screens sit on white cards over a map and keep light-surface
colours, but their brand-carrying values — the route line, the ETA green, the
pickup and destination pins — now come from the new palette. The last
hard-coded lime, in `udrive_route_flow_screen.dart`, is gone.

## 20. The build break, and the check that would have caught it

`rev 65` did not compile. `live_trip_navigation_screen.dart` called
`AppControllerScope.of(context)` — added for the passenger-standing lookup —
without importing `app_controller.dart`. One missing line.

Import added. But the more useful outcome is `tool/check_imports.py`.

`audit_structure.py` checks shape and brace balance, and this passed it cleanly.
The failure only surfaced after dart2js had been running for twenty seconds in
CI, which is a slow and expensive way to learn about a missing import.

The new check builds the set of every top-level declaration under `lib/`, walks
each file's transitive project imports, and flags any name a file uses that is
declared in the project but not reachable from that file. It is deliberately
narrow: because it only considers project symbols, it needs no list of Flutter
or package names and produces almost no noise.

Run it before packaging:

```bash
cd udrive_unified_mobile
python3 tool/audit_structure.py
python3 tool/check_imports.py
```

Both are clean on this ZIP. The single remaining line — `'S'` in
`driver_home_screen.dart` — is a false positive: the letter appears inside a
nested string in an interpolation that the crude stripper does not fully clear.

It is not a typechecker and not a substitute for `flutter analyze`. It catches
one common, expensive mistake early.

## 21. The chat composer was never rendering

The message screen showed the empty state and, at the bottom, a bare strip with
a stray line in the corner. No field, no send button.

The app's `filledButtonTheme` sets `minimumSize: const Size.fromHeight(54)`,
which is `Size(double.infinity, 54)`. Inside a `Row`, that button demands
infinite width — so the `Expanded` text field beside it collapsed to a few
pixels, and the button itself was pushed off the right edge of the screen. The
line visible in the corner was the collapsed field.

The composer now uses a plain `Material` + `InkWell` circle with a fixed 46×46
box, and styles its own field rather than inheriting. Anywhere else a
`FilledButton` sits in a `Row` it is already wrapped in `Expanded`, which clamps
the infinite minimum — this was the one place it was not.

## 22. The tracking panel

**White card on a dark teal map.** It read as a different application pasted
over this one, and its greys were mixed for a light background, so the driver's
name was barely legible against it. Now the app's own surface, with the palette's
inks.

**The status pill was white text on a white pill** — the words were there and
invisible. It also announced "LIVE · Online Map", which is not the customer's
problem. It is now a dark pill with the trip status and a single dot: green when
the driver's position is live, amber when the signal has gone.

**"0.0 km by road to pickup" while the driver's location was unknown.** Zero
kilometres reads as "outside your door". The panel now says *Locating driver…*,
*Signal lost*, or the real road distance — never a number it does not have.

**Arrival moved to the top right** at 26pt: it is the one thing a waiting
customer is looking at the screen for.

**Message and Call are full-width halves** instead of two small circles
competing with the fare chip. On a phone held one-handed at a roadside,
"message the driver" should not be a fingernail-sized target.

**The car has a heading.** It was a circular icon, which carries no direction, so
a car approaching and a car driving away looked identical. It is now the same
top-down sprite Home draws, rotated to the driver's reported heading.

## 23. The tracking panel, again

**The driver and the vehicle, at a size you can recognise them by.** A 54px
avatar and a 96px-tall vehicle photograph. A customer on a roadside is matching
what is in front of them against what the app says is coming, and a registration
plate in 12pt type is a poor way to do that.

The photograph is the admin's own upload for that vehicle category, which meant
`TripTrackingDto` had to start carrying `VehicleCategory` — the tracking query
joined the vehicle already and simply was not selecting it.

**The avatar is initials, not a photograph.** There is no driver photo column
anywhere in the schema. A stock silhouette on every driver would tell the
customer less than a letter does. Adding real photos means a document upload,
storage, and a moderation question about what gets published to strangers — a
feature, not a styling change.

**Call and message are small round buttons at the top right**, beside the name,
rather than two full-width bars in the middle of the card.

**The driver's messages float over the map.** Translucent, just above the panel,
last two only. A driver who writes "I am at the blue gate" needs that read now,
not after the customer thinks to open a screen — and a customer standing on a
roadside is looking at the map, not at an icon. Tapping any of them opens the
thread: the message being read *is* the way in.

They sit in the same column as the panel rather than positioned over it, so they
cannot end up hidden behind it when the panel grows — an OTP box or a completion
banner changes its height a lot.

**"0.0 km by road" is gone.** Under a hundred metres it now says *Arriving now*.
Zero kilometres is a number pretending to be information.

## 24. A second build break, and a second check

`rev 69` did not compile: `repository.cached()` returns a `Future`, and it was
used without `await`. dart2js said so after twenty seconds in CI; nothing local
had.

`tool/check_imports.py` now also flags project `Future`-returning methods whose
result is consumed as a value without `await` — either `x.foo().bar` or the
shape that actually broke this build, `final y = x.foo();`.

Writing it exposed a second bug in the check itself: the first version matched
`Future<[^>]*>`, which cannot match `Future<Map<String, String>>` because of the
nested angle brackets. It passed silently over the very call it was written for.
Fixed to allow one level of nesting, and verified by reintroducing the bug and
confirming the check fails.

Both checks now run before every ZIP:

```bash
python3 tool/audit_structure.py
python3 tool/check_imports.py
```

Still not a typechecker. Two classes of mistake, caught in a second instead of
twenty.

## 25. Driver reputation on the tracking screen

`GET /api/v1/trips/{bookingId}/driver` returns the Driver's rating, the number
of ratings behind it, completed trips, and their **five most recent Customer
reviews**. All of it from `trip_ratings`, which has held this data since phase
14 with nothing reading it.

On the panel: **stars beside the name** with the rating and the review count —
an average over three ratings and one over three hundred are different claims,
and printing both as "4.7" would flatten that. Below the vehicle, a horizontal
row of **review cards**: stars, reviewer's first name, and what they wrote. A
star average is a number; a sentence from someone who rode with this driver last
week is what tells a customer whether to get in.

Reviewers appear by first name only. A review is about the Driver, and the
reviewer never agreed to be identified to strangers. Driver-written reviews of
Customers are excluded — that is a different conversation and does not belong in
front of the person waiting at the kerb.

A Driver nobody has rated shows "New driver" or "New to ratings · N trips",
never "5.0". A score nobody gave is worse than an honest blank, and a new driver
is not a bad one.

**The artwork is larger**: 62px driver avatar, 132px vehicle strip.

## 26. The admin guide

**A Guide button in the top right of every admin screen.** It opens a
slide-over, not another page — the guide is read *while* doing the thing it
describes, and navigating away loses the half-filled form someone was stuck on,
which is exactly when they went looking for help. Escape closes it.

It is searchable, and the search covers the steps and cautions, not only the
headings. Someone looking for help types the problem — "refund", "per km" — not
the heading it happens to sit under. Results open expanded, because a list of
collapsed headings is a poor answer to a search when the matched words are
inside them.

**28 sections across 7 groups**, one per screen, each with what the screen is
for, the steps in order, what is easy to get wrong, and which roles may act.

The content lives in `admin_portal/app/lib/guide-content.ts` and is read by
three things: the Guide panel, the `/help` page, and `docs/ADMIN_GUIDE.md`. One
source. Two copies of a guide disagree within a month, and the one someone
happens to open is then the wrong one.

`/help` shows everything expanded — it is for learning the portal or checking a
procedure, and making someone click twenty times to read a manual is the
opposite of what a manual is for.

### What the guide actually says

It opens with **how a ride flows end to end**, because most confusion in this
portal is not knowing which screen owns which stage — a ride request is not a
booking, and cancelling them costs very different things.

It states the unflattering parts plainly:

- Verification "puts a stranger in a car with a Customer". Rejecting a good
  application costs a Driver a day; approving a bad one costs someone more.
- Rate per km and minimum fare are different numbers, and putting 1,600 into the
  per-km field prices a 12 km trip at nineteen thousand rupees — the exact bug
  that shipped once already.
- Suspension "is not a warning, it removes someone's income that day".
- A notification cannot be recalled.
- A button that does nothing usually means your role cannot do it, not that the
  portal is broken.

A guide that only lists happy paths teaches people to be surprised.

## 27. Rating when the trip ends

The moment tracking reports `TripCompleted`, the map is replaced by the rating
screen. Not covered — replaced. A finished trip's map has nothing left to say,
and leaving it up makes rating look optional, which is how a platform ends up
with no ratings at all.

Stars, then quick reasons, then an optional sentence. The reason chips differ by
score: "clean vehicle" is not a useful prompt for someone who just gave two
stars, and asking a happy customer what went wrong invites a complaint that was
not there.

The screen says where the rating goes — onto the driver's profile, where the
next customer sees it before they get in. A review that visibly goes somewhere
gets written more often than one that disappears into a form. This closes the
loop with §25: the stars collected here are the stars shown there.

**Skipping is allowed and says so.** A rating screen with no way out is one
people learn to close by killing the app.

The chips are folded into the review text rather than stored separately. The
ratings table has no tag column, and a migration for five fixed phrases would be
adding schema for something a sentence already carries.

## 28. Sharing a live ride

`CreateLinkAsync` and `RevokeLinksAsync` have been in `TrackingService` since
phase 12 with **no route calling them**. The public viewer was live and had
nothing to view. Two routes now expose them, and the tracking panel has a share
button beside call and message.

The token is returned once and only its hash is stored, so nobody reading the
database later can recover a link and re-send it. The public view stops the
moment the trip completes or cancels — which is what makes it safe to put in a
family group rather than a permanent window into where someone is.

## 29. Driver documents

**A Driver could not see what they had uploaded.** The files were readable only
by Admins, so someone photographed their licence, sent it, and found out days
later — via a rejection — that it was blurred or upside down. Two new routes
serve a Driver their own documents, with the ownership check inside the SQL
rather than after it.

**One screen, four documents.** CNIC front, CNIC back, licence, photograph. Each
row shows what it is, why it is being asked for, what state it is in, and gives
two buttons: **View** and **Upload/Replace**. View opens the file full screen and
zoomable, with the bearer token on the request — without that header it is a
broken-image icon, from which a Driver reasonably concludes the upload failed.

Deliberately four. Every extra document is a Driver who gives up halfway, and
these establish that a person may drive and that the vehicle is theirs. Anything
else can be asked for later by an Admin with a reason.

**A rejection carries the reviewer's own words.** A rejected row turns red, keeps
the note, and says "replace this one". A rejection with no reason is a wall, and
the Driver simply uploads the same photograph again.

**Submit is off until everything is present**, and the button says why. Sending
an incomplete set costs a review cycle and a day of the Driver's time.

**The dashboard card leads somewhere.** It used to read "Driver approval
required — nearby rides start automatically after approval", which tells a
stuck Driver nothing about which of the three states they are in and offers no
way forward. It now names the next action and opens the documents screen.

## 30. Three type errors, and the check that already exists

`rev 73` did not compile. Three mistakes in one new file:

- `AuthRepository` takes a `SessionStore`, not an `ApiClient`.
- `DriverProfileLive` has no `documents` list — only `LiveVehicle` does. The
  driver's documents come from `GET /api/v1/driver/documents`, which had no
  repository method at all.
- `FilePicker.pickFiles`, not `FilePicker.platform.pickFiles`. Both existing
  upload screens use the static form.

All three fixed: a `getDriverDocuments()` repository call, `driverDocuments()`
and `refreshDriverProfile()` on the controller, and `accessTokenForMedia()` for
the one place that has to attach a bearer header to an `Image.network`.

**None of these are catchable by `tool/check_imports.py`, and no amount of
extending it will be.** They are type errors — wrong argument type, missing
member, missing static — and finding them needs a type checker, not pattern
matching over source text.

**The type checker is already wired up.** `.github/workflows/build-android-apk.yml`
runs `flutter analyze` as its first job, before the web and APK builds, and its
own comment says it exists to fail in a minute rather than after a full build.
It would have caught all three.

It runs on push to `main`. If Railway is deployed from the same commit without
waiting for that job, the analyzer's answer arrives after the deploy has already
failed — which is what has happened three times now. Waiting for the Actions
tick, or running `flutter analyze` locally before pushing, removes this entire
class of round trip.

## 31. Driver mode: the dashboard is now about the driver

**It said nothing about them at all.** No earnings, no rating, no trip count. A
first screen that only lists other people's requests is a queue, not a
dashboard.

`GET /api/v1/driver/dashboard` returns it all in one call — four round trips for
four numbers on the first screen someone opens is four chances to show a
half-loaded dashboard. Earnings today (large, green), earnings this month, trips
today, star rating with its count, completed rides, and the last five customer
reviews in a scrollable row.

**Typography.** One bold number per card: the money. Everything else dropped to
ordinary weight — the request card's "13 km trip", the addresses, the Route
button. When every figure is bold, nothing is read first, which is what made the
screen look busy rather than considered.

The countdown pill only goes heavy under five seconds, where the weight actually
means something.

**No default rating.** A driver nobody has rated shows "No ratings yet", never
"5.0".

## 32. Documents: sent means sent

Upload when nothing is there, **replace only when the reviewer has rejected it**,
view-only in between.

A document that has been sent is evidence. Letting a Driver swap it while it
sits in a queue means a reviewer can approve one file and a different one ends
up on the record — and it gives anyone rejected an easy way to keep resubmitting
until a tired reviewer says yes.

Where there is no button, the row says why rather than leaving a greyed one the
Driver presses and presses: *"Approved — locked"* or *"Sent. You can view it,
but not change it while it is being reviewed."*

**My documents** is now in the driver's left menu, so it is reachable without
going through Vehicles.

## 33. Duplicate class names, and a third check

`rev 76` did not compile. `driver_pages.dart` already contained mock
`DriverWalletScreen` and `DriverDocumentsScreen` classes — hard-coded payout
history, a "Dummy document selected for upload" snackbar — and the moment
`main_shell.dart` imported both those and the real screens, every reference
became an ambiguous import.

The mocks are deleted, with a note in their place saying why.

`tool/check_imports.py` now also reports **ambiguous names**: a name declared in
more than one file under `lib/`, where some file's imports reach more than one
declaration. Getting it usable took three corrections, each worth recording:

- **Eighteen names are duplicated across the project** and nearly all are
  harmless, because no single file sees both. Listing all eighteen every run
  would train everyone to ignore the output, so only genuine clashes are
  reported.
- **`hide` clauses count.** `main_shell.dart` already resolves one legacy clash
  with `import 'driver_pages.dart' hide DriverEarningsScreen;`. Ignoring that
  would have flagged it forever.
- **Imports are not transitive in Dart.** The reachability walk was following
  imports through imports, which is not how the language works — a file
  importing B does not inherit what B imports. Only `export` propagates. Fixing
  this removed two phantom clashes and made the missing-import check honest.

It also now separates **orphaned files** — seventeen of them, which nothing
imports and which are therefore never compiled. A missing import inside dead
code says nothing about the build, and mixing the two produced permanent noise.

Three checks now run clean apart from two known items: `'S'` in
`driver_home_screen.dart` (a letter inside a nested string the crude stripper
does not clear) and `UserMode` in `mode_switch_card.dart`, which is real but
only reachable from orphaned files.

**This is still not a substitute for `flutter analyze`**, which is already the
first job in `.github/workflows/build-android-apk.yml` and would have caught
this in about a minute.

## 34. I switched off the marketplace

Requests stopped reaching drivers, and it was migration 040.

It added `commission_balance` defaulting to 0, and a rule that a Driver sees
requests only while their balance is **above** the minimum — which also defaults
to 0. `0 > 0` is false. Every Driver already on the platform went from working
to receiving nothing, with no error and no notice.

That is the wrong way to introduce a charge. Someone driving yesterday should
not be cut off by a rule they were never told about, and the first they knew of
it was an empty screen.

Migration 041 credits every approved Driver an opening 1,000, with a ledger
entry saying where it came from. `GREATEST` means a Driver who had already paid
keeps what they paid. New Drivers still start at zero and top up before their
first ride.

## 35. The driver dashboard, cut back

The previous version put earnings, month totals, rating, trip count and five
review cards **above** the requests. The thing a Driver opens the app for — the
next ride — started below the fold.

The top is now one line: **rides today, earned today**. One bold number, the
money.

Everything else moved to **Earnings** in the menu: month total, lifetime rides,
star rating with its count, and the recent reviews in full. It is worth reading,
but not while a request is coming in.

**The title bar** said "Good evening, Waseem" in 900-weight, which ran out of
room on a phone and truncated to "Good evening, Was…" — a greeting that has
stopped greeting anybody. It is now just the first name at ordinary weight. The
time of day was not information.

## 36. Documents never reached the reviewers

Every driver document upload was being rejected with a 400, and nothing ever
arrived in the admin queue.

`DriverVerificationService.NormalizeDocumentType` uppercases the type and
replaces non-alphanumerics with underscores, then checks the result against
`CNIC_FRONT, CNIC_BACK, DRIVING_LICENCE, SELFIE`. The screen was sending
`CnicFront`, which normalises to `CNICFRONT` — there is no separator to convert —
so it matched nothing. `ProfilePhoto` had the same problem against `SELFIE`.

The screen now sends the exact strings the server accepts.

## 37. The documents screen shows the documents

It listed four rows with a status icon each. A green tick beside "CNIC — front"
says a file exists; it does not say whether it is the right one or readable,
which is the only thing a driver checking their paperwork wants to know.

Each row now leads with a **62px thumbnail of the file itself**, tappable for a
full-screen zoomable view. The bearer token is read once and shared, rather than
fetched per row.

Still no delete. Once sent, a document is view-only to the driver — replaceable
only when a reviewer has rejected it. Deletion stays with admins, where the
portal already has it (SuperAdmin).

## 38. Driver menu: thirteen to eight

**Dashboard · Wallet · Earnings & reviews · Vehicles · My documents · My routes
& tours · Settings · Help & support**

Removed: Ride requests and Active trip, both already on the dashboard. Reviews,
now inside Earnings. Create route folded into My routes & tours, and Help into
Support — a driver with a problem opens one of those, not both, and having to
choose between them is itself a small obstacle.

A menu is a list of places you cannot already see. Everything else on it is
noise to read past.

## 39. The API would not start

Migration 041 used `ON CONFLICT (idempotency_key)`. The index behind it,
`ux_wallet_entries_idempotency`, is **partial** — `WHERE idempotency_key IS NOT
NULL`. Postgres accepts a partial index as an ON CONFLICT arbiter only when the
statement repeats its predicate; otherwise it raises 42P10, the migration runner
aborts, and the service fails to boot. One missing `WHERE` cost a deployment.

Fixed in three places, because the same fault was in two others:

- `041_opening_commission_balance.sql`
- `DriverWalletService.ChargeCommissionAsync` — would have failed on **every
  trip completion**, rolling back the completion it runs inside
- `PaymentService.CreateAsync` against `payments`, which has the same partial
  index. Pre-existing, and it would have failed on every card payment

### A checker for it

`udrive_api/tool/check_on_conflict.py` reads every unique index and constraint
out of the migrations, then checks each `ON CONFLICT` in the migrations and the
services against the one it needs.

It is **table-aware**, and that took a second attempt. The first version matched
on column names alone and reported three healthy statements —
`driver_ride_request_decisions` has `(ride_request_id, driver_profile_id)` as its
primary key, while a different table has a partial index on the same pair. A
check that cries wolf gets switched off, so it is better to miss a case than to
invent three.

Verified by putting the bug back and confirming the check fails, then removing
it again.

```bash
cd udrive_api && python3 tool/check_on_conflict.py
```

## 40. `_token` was never declared

The documents screen referenced `_token` in three places and the field
declaration was never there. A batch edit had asserted its way out halfway
through, applying the later replacements and silently skipping the two that
created the field and loaded it. The file balanced, the audit passed, and
dart2js found it twenty seconds into CI.

Field added, loaded alongside the profile and documents, and the full-screen
preview now reads it instead of fetching the token again.

### A fourth check

`check_imports.py` now flags **private members used but never declared in the
file that uses them**. `_foo` is file-scoped by definition, so if no declaration
of it appears anywhere in that file, the reference cannot resolve — which makes
this one of the few type errors that is genuinely findable with text.

Only private names, and only within one file. Public members would need to know
about every superclass and mixin, which is a type checker's job and not
something worth half-doing.

One correction while writing it: the first version reported `_pendingCamera` in
`ud_map.dart`, whose declared type is a record — `({LatLng target, double zoom})?
_pendingCamera;` — a shape none of the declaration patterns matched. Added.

Verified by removing the `_token` declaration again and confirming the check
fails.

The four Flutter checks and the SQL one now stand at:

```bash
cd udrive_unified_mobile && python3 tool/audit_structure.py && python3 tool/check_imports.py
cd udrive_api && python3 tool/check_on_conflict.py
```

## 41. Once a ride is accepted, the dashboard is that ride

Today's takings, the next-rides heading and the "locked for now" notice all
describe work that is not happening. A Driver who has just accepted is driving
to a pickup, and every other block is something to read past on the way to the
one button they need. With an active trip, the dashboard shows the ride card and
nothing else.

**The card was unreadable.** It had a hard-coded mint background (`#EAF7F2`)
from the old light scheme, and on the dark palette every line on it — the
addresses, the passenger name, the fare — was there and invisible. It now takes
its surface, border and ink from the theme, and `_RouteLine` states its colour
instead of inheriting one meant for a light card.

## 42. The driver's action row

Message, call, and the action that moves the trip on — **all three at the bottom
of the map**, where a Driver's thumb already is. The contact buttons used to sit
at the top of the panel beside the name, which is the furthest point from it,
and they were duplicated once I added them to the tracking screen.

Emergency and Cancel share a row beneath: two exceptional actions together,
neither of them competing with "I have arrived".

## 43. Cancellation

**Driver cancels before the trip starts: 2% of the fare**, taken from the
prepaid balance, keyed on the booking so a retry cannot charge twice.

A Customer who has been waiting has lost their place in the queue and has to
start again; that cost should not fall entirely on them. It is deliberately
small — enough that a casual cancellation is not free, not so much that a broken
fan belt becomes a fine.

Not charged once the trip has started. At that point the Customer is in the
vehicle and a cancellation is a different and more serious event, which belongs
with the disputes process rather than an automatic fee.

**Customer cancels more than five minutes in: a reason is required.** Changing
your mind straight after booking costs the Driver almost nothing; cancelling
once they have driven across town does, and at that point they are owed an
explanation. Five options plus free text, and "Something else" must actually say
something — an empty box selected and left blank tells the Driver exactly as
little as no reason at all.

## 44. The missing pictures are not a code bug

Every attachment in the admin portal showed "This section or record is not
available". The files are genuinely gone.

`LocalFileStorageService` writes to `UPLOAD_ROOT`, and **when that variable is
unset it falls back to a path inside the container image**. On Railway that
filesystem is rebuilt on every deploy. The database keeps the document rows, so
the portal shows a record that exists pointing at a file that no longer does.

Between the vehicle being verified and the screenshot, this project deployed
many times. Every uploaded document, vehicle photograph and payment screenshot
went with them.

**The fix is configuration, not code:**

1. Railway → the API service → Volumes → add one with mount path `/data`
2. Variables → `UPLOAD_ROOT=/data/uploads`
3. Redeploy

Anything uploaded before that is unrecoverable and has to be sent again.

Three changes so this cannot hide again:

- The API **prints a warning at boot** when `UPLOAD_ROOT` is unset or points
  inside the container image.
- The admin portal **shows the API's own 404 message** instead of a generic
  one. The API already distinguishes "the record is missing" from "the record
  exists and its file has gone from storage" — two faults with completely
  different fixes — and the portal was collapsing both into one sentence. That
  collapse is what turned a five-minute configuration problem into a hunt for a
  code bug.
- `PHASE_20_ENVIRONMENT.example` documents the variable.

## 45. Deleting documents

`canDelete` was SuperAdmin-only, in the portal and on the route. But the people
reviewing verification all day are Admins, and a reviewer who can see that a
file is corrupt or is the wrong document, yet cannot remove it, has to find a
SuperAdmin to press one button. That queue is where applications sit for days.

Both now allow SuperAdmin **and** Admin. Nobody below that.

## 46. Photographs are shrunk before upload

A phone camera produces four to eight megabytes a shot. On a mobile connection
in Azad Kashmir that is a minute of waiting per document, four documents to
send, and an upload that fails halfway leaves the driver with nothing. The
server also refuses anything over ten megabytes, so a good camera could stop
someone registering at all.

`ImageCompressor` resizes to 1600px on the long edge before upload — more detail
than a reviewer looks at on a CNIC or a number plate. Applied at all three
upload points: driver documents, driver verification, vehicle photographs.

It is dependency-free, using the codec Flutter already has rather than adding an
image library on every platform for one resize. And it is careful in three ways:
files under 900 KB and PDFs are passed through untouched; an image already under
1600px is not re-encoded, since that would only lose quality; and if the result
comes out **larger** than the original — which a lossless PNG copy of a JPEG
often does — the original is kept. A slow upload is a far smaller problem than a
document that will not send.

## 47. "Ask driver to re-upload"

The message now reads *"The attachment record exists, but its file is missing
from API storage"* — which is the API being precise, and confirms the files are
gone from disk. The volume still has to be mounted; that part is unchanged and
is not something code can fix.

But the report exposed a real hole I had made. A Driver cannot replace a
submitted document — that is deliberate, so a file cannot be swapped while a
reviewer is looking at it — and it means that when a file goes missing, or
arrives unreadable, **the Driver is locked out of fixing the one thing standing
between them and approval**. Neither side could act.

Two changes close it:

**The admin action row always renders.** It was inside `{objectUrl && (…)}`, so
a document whose file had vanished showed a red error and *nothing else* — no
delete, no way to ask for it again. The one case that most needed an action was
the one case with none.

**A new "Ask driver to re-upload" button**, on every document card. It marks
that one document rejected with a reason the admin types, which is exactly the
state the Driver app already unlocks for replacing — so the driver opens My
documents, sees that row in red with the reason, and gets a Replace button.
Nothing else is touched: asking for a new licence should not make someone
photograph their CNIC again.

Available to SuperAdmin, Admin and VerificationOfficer. It is not destructive —
it asks for a file rather than removing one — so it does not need the narrower
role that delete does.

## 48. The volume is on the wrong service

The screenshot shows `postgis-volume` attached to the **PostGIS** service. That
is the database's own storage — where Postgres keeps its data files — and it
does nothing for files the API writes.

`udrive-api` and `PostGIS` are separate containers with separate filesystems. A
volume on one is invisible to the other. `udrive-api` currently has no volume at
all, so it is still writing uploads inside its own image, and they still go on
every deploy.

**What is needed:** a second volume, on `udrive-api`, mount path `/data`, plus
`UPLOAD_ROOT=/data/uploads`.

### Making this visible in the portal

Rather than leaving the answer in a container log, **Diagnostics now has a File
storage panel**: the upload root, whether it survives a deploy, whether the
folder exists, and how many files are in it. When storage is ephemeral it shows
a red box naming the fix, including the part that caused this — that a volume on
the database service does not help.

`StorageDiagnostics` gained an `Ephemeral` flag for it. The panel is SuperAdmin
only, like the endpoint behind it, and its absence is not treated as an error
for anyone else.

## 49. "Session has expired" with nothing to click

A 401 on the verification page showed *"The session has expired. Sign in
again."* and then did nothing. The portal still believed it was signed in, so
there was no sign-in screen to reach and no button to press. A dead end.

The retry only ran when a refresh token happened to be present:

```ts
if (isApiRequest && response.status === 401 && session?.refreshToken) { … }
```

A session saved without one, or one whose refresh had itself expired, fell
through to the friendly message and stopped there.

A 401 is always an authentication problem, so it now always ends in one of two
places: a refreshed token, or the sign-in page. Failure to refresh clears the
session and redirects, carrying `?next=` so the person returns to the screen
they were on rather than being dropped at the dashboard — being bounced to the
top of the portal after every token expiry is its own small punishment.

Access tokens last fifteen minutes, so this path runs several times a day.

## 50. The C# is now actually compiled

The repeated build failures were the fair complaint behind this round, so I went
looking for a real compiler rather than another regex.

The .NET SDK installs from the Ubuntu archive, which is reachable here. A full
`dotnet build` still is not possible — NuGet is blocked by the network policy,
so Npgsql, JwtBearer and Swashbuckle cannot be restored, and the project targets
.NET 10 while only the 8 SDK is available.

What *is* possible is running Roslyn with no references at all and keeping the
errors that survive. Anything about a missing type is an artefact of having no
references; a missing brace, a stray semicolon or a malformed expression is real
and would fail the deploy.

`udrive_api/tool/check_syntax.sh` does that. Verified by appending
`public class Broken { void X( }` and confirming it reports CS1026 and CS1002,
then removing it.

This is the first check here that uses the actual language grammar rather than
guessing at it. It is still not `dotnet build` — it cannot see a wrong argument
type or a missing member, which is what broke three of the six deploys. Those
need `flutter analyze` on the mobile side and a real `dotnet build` on the API
side, both of which exist in CI.

### Everything that now runs before a ZIP

```bash
cd udrive_unified_mobile && python3 tool/audit_structure.py && python3 tool/check_imports.py
cd udrive_api && python3 tool/check_on_conflict.py && bash tool/check_syntax.sh
cd admin_portal && npx tsc --noEmit && npx next build
```

The admin portal is the only one of the three that is genuinely compiled here,
and it has not broken a deploy once.

## 51. "Load failed" on upload

Every server-side error on the web app was arriving at the browser as a network
failure rather than as the error it actually was.

`UseExceptionHandler` sits outside `UseCors` in the pipeline and **clears the
response** before writing an error, which strips the
`Access-Control-Allow-Origin` header the CORS middleware had already set. The
browser then refuses to read the response at all. Safari's wording for that is
`Load failed` — which is what reached the driver, on an endpoint whose real
answer might have been "that file is 14 MB" or "storage is not writable".

The handler now puts the origin header back before writing. Fixed there rather
than by reordering middleware, because the handler is the thing that clears them
and the only place that knows they need restoring.

Three supporting changes:

- **The client names the failure.** `ClientException` and `TimeoutException` are
  caught separately and turned into sentences a driver can act on, instead of
  passing Safari's wording straight through.
- **The upload timeout went from 40 to 90 seconds.** Forty is short for a
  photograph on a mobile connection in the mountains, and a timeout there looked
  identical to a server fault.
- **The size error states the actual size.** "Must be under 10 MB" leaves
  someone guessing whether their file is 11 MB or 40, and therefore whether
  cropping will help. It now says which.

I cannot confirm from here which of these was the specific failure — that
needs the API's own logs. But the missing CORS header made *every* error on this
endpoint indistinguishable from a dead connection, so whatever the underlying
cause, this is why nothing useful reached the screen.

## 52. "The current session is not authorized" — it was a directory

Opening My documents returned 401 with that message. The session was fine.

Two of my own changes combined into it:

**One.** `LocalFileStorageService`'s constructor calls
`Directory.CreateDirectory(_uploadRoot)`. With the volume now mounted but not
writable by the container user, that throws — and .NET's exception for a denied
path is `UnauthorizedAccessException`.

**Two.** `GetRequiredUserId` also threw `UnauthorizedAccessException`, and the
exception handler mapped that type to 401 *"The current session is not
authorized for this action."* Two completely different faults, one exception
type, and the response depended on telling them apart.

So a permission problem on a disk was reported to every Driver as an invalid
session. They would sign out, sign in, and be told the same thing.

**Three.** It only started now because rev 73 added `VerificationFileLookupService`
to `DriverVerificationController`'s constructor — so listing documents began
constructing the storage service, and a throwing constructor takes the request
down before any code runs.

### Fixed

- **`ApiAuthenticationException`** is its own type for "the token does not
  identify a user". `UnauthorizedAccessException` now maps to a 500 that names
  the real problem: the API cannot write to its uploads directory.
- **The storage constructor never throws.** A broken upload directory should
  break uploads; it should not break reading a list. The failure is recorded and
  logged at boot instead.
- **Saving reports it plainly** — a 503 saying the server cannot store files and
  naming the directory — rather than letting a raw IO error become "an
  unexpected error occurred", which sends a Driver back to retry an upload that
  will fail identically every time.
- **Diagnostics shows it.** The File storage panel now has a **Writable** row
  and a red box with the exact fault when the directory cannot be written to.

### What to check after deploying

Open **Diagnostics → File storage**. Three rows have to be right:

| Row | Needs to say |
|---|---|
| Upload root | `/data/uploads` |
| Survives a deploy | Yes |
| Writable | Yes |

If **Writable** is No, the red box gives the operating system's own reason. That
is almost always the volume's mount path or its permissions, and it is fixed in
Railway rather than in code.

## 53. Why the volume was still not writable

`/data` as the mount path with `UPLOAD_ROOT=/data/uploads` is correct. The
Dockerfile was not.

**The container runs as `udrive`, uid 10001.** Railway mounts a volume owned by
root. A non-root process cannot create a directory inside it — which is the
`UnauthorizedAccessException` behind everything in §52.

The image could not fix this ahead of time either: `RUN mkdir -p /app/uploads &&
chown …` runs at build time, and anything chowned then is hidden the moment the
volume is mounted over it.

**A start-up entrypoint does it instead.** The container now starts as root just
long enough to create the directory and hand it to uid 10001, then `exec
setpriv` drops privileges before the API starts. `exec` matters: it replaces the
shell rather than spawning a child, so the API keeps PID 1 and still receives the
signals Railway sends to stop it.

Neither preparation step is fatal on its own. Some mounts arrive owned
correctly, and others ignore `chown` while still being perfectly writable —
refusing to start in those cases would trade a fixable warning for an outage.

**`ENV UPLOAD_ROOT` also pointed at `/app/uploads`**, inside the image. Railway's
service variable overrides it, so this was not the active fault, but a default
that silently discards every upload is a trap for the next person. It now
defaults to `/data/uploads`.

While writing the Dockerfile I put the `util-linux` install *after*
`rm -rf /var/lib/apt/lists/*`, which would have failed the build with nothing
left to resolve against. Both packages now install before the lists are deleted.

`RAILWAY_CHECKLIST.md` carries the full setup and the three rows to check
afterwards.

## 54. Asking for a document again now has teeth

`GET /api/v1/driver/pending-documents` returns everything an Admin has rejected
or asked back, driver documents and vehicle documents together.

**On the dashboard, above everything — including an active ride.** It is the
only block on that screen with a consequence attached to ignoring it.

Not a dialog. A popup is dismissed once and then gone; this has to stay in front
of the Driver until the file is sent, so it sits at the top and does not leave on
its own.

It **names the documents** rather than counting them. "A document needs
attention" sends someone into the documents screen to work out which one; the
name saves that trip. The Admin's reason is shown with each.

**Two rides of grace**, then requests stop. A Driver mid-shift cannot always
photograph a licence there and then, and cutting their income off the instant an
Admin clicks a button turns an administrative request into a punishment. Two is
enough to finish what they are doing and not enough to ignore.

Where several documents were asked for at different times, the banner shows the
**smallest** remaining allowance — two requests must not read as four rides of
grace.

Enforced in `GetEligibleRideRequestsAsync`, so a Driver who has run out stops
seeing requests rather than answering one and being refused.

## 55. A verified vehicle can be edited once its papers are gone

Deleting a vehicle's photographs, or asking for one back, is an Admin saying the
record is no longer trusted. But the edit guard only looked at
`status = 'Verified'`, so the Driver was left holding a vehicle they could
neither correct nor resubmit — the same trap the documents screen had.

The lock now also requires at least one document that has not been deleted or
rejected. A vehicle whose papers are all refused is no more trusted than one
with none.

## 56. Driver verification screen

`#F5F8F7` and `#FFF8E7` were mixed for the old light scheme and read as grey
slabs on the teal palette, with text in ink chosen for a different background.
Both blocks now use the theme's surfaces and tints, and the vehicle row states
its ink instead of inheriting one.

## 57. Why approval refused, and never said so

The rules themselves are right, and both are deliberate:

- A **vehicle** can be Verified only once all four of its documents exist.
- A **driver** can be Approved only once all four of *their* documents exist
  **and at least one of their vehicles is already Verified**.

That second clause is the one nobody guesses. The order is vehicle first, then
driver — and nothing in the portal said so.

What the API returned was *"Verify all four required driver documents and at
least one vehicle before approving the driver"*, which is useless to a reviewer
looking at four documents on screen. It does not say which document, or whether
the documents were even the problem.

**The API now names it.** Missing driver documents are listed by type. If the
vehicle is the blocker it says so, and distinguishes "no vehicle registered"
from "none of their 2 vehicles is Verified yet — open the vehicle and set it to
Verified first". Same for vehicle verification: the missing photographs are
listed.

**The portal says it before the button is pressed.** An amber note above the
decision buttons lists exactly what is outstanding, and Approve is disabled
while anything is. The check mirrors the server's rule rather than guessing at
it, so the two cannot disagree.

A refusal that arrives only after you act, and then does not say what to do, is
the worst of both.

## 58. Deleting a vehicle left it half-deleted

Deleting from the portal is a **soft** delete: the row stays with
`status = 'Deleted'` so bookings, earnings and audit history that point at it do
not break. That part is right. Two things were not.

**The driver's app still listed it**, with "Deleted" quietly at the end of its
details. They were left looking at a vehicle they could not use, could not
remove, and could not replace.

**And the plate stayed taken.** `registration_number` had a plain `UNIQUE`
constraint across every row, deleted ones included. So the driver re-registered
the same vehicle and was told the number was already registered — by a record
neither of them could see.

- The driver's vehicle list now excludes deleted rows.
- The constraint is now a partial unique index that ignores them, and is
  case-insensitive: "ADL-955" and "adl-955" are the same plate.
- The duplicate message says the number belongs to **another active vehicle on
  the platform**, and to ask support if it is theirs — because that is now the
  only case in which it can happen.

Everything customer-facing was already safe: nearby vehicles, ride eligibility
and offer submission all require `status = 'Verified'`, which a deleted vehicle
can never be. Only the driver's own list was wrong.

## 59. Customer mode

Driver mode untouched, as asked.

**The map is light.** It was dark on the argument that it should match the app.
That was the wrong trade: the map is the one part of the screen a person is
*reading* rather than looking at — street names, junctions, which side of the
road a pin is on — and a tint costs legibility on a phone held at arm's length
in daylight. The panels around it carry the theme instead. `UdMap` takes a
`darkStyle` flag, off by default, so the driver screens can keep the dark
palette if they ever need it.

**The booking card starts open.** It used to start low with the card cut off and
a handle to pull it up, which put the ordinary path — pick a product, name a
destination — behind a gesture.

**The handle only closes.** One direction on purpose: it exists so someone can
get a longer look at the map, and raising the card back is what tapping anything
on it already does. A control that means two opposite things depending on hidden
state is one people stop trusting. It reads "Show map" rather than "More" —
"More" on a card that is already fully open promises something underneath.

**A steering wheel for Driver mode.** Material has no such glyph; `drive_eta` is
a car seen from the side, which reads as "a vehicle" rather than "you are
driving it", and that distinction is the entire point of the control. Drawn in
`SteeringWheelIcon` — rim, hub, three spokes, stroke scaled to the icon size.

**Three accent colours, on the home card.** Not a colour wheel: a free picker
lets someone land on a colour that fails contrast against the dark surfaces, or
one that collides with the red used for danger and the green used for success —
and then every warning in the app quietly stops reading as a warning. Amber,
Sky and Lime were each checked against those and against the ink placed on top.
Saved locally, restored before the first frame so the app never paints in one
colour and flips to another.

**Clear cached data**, in the menu. It removes cached copies and pulls
everything down again. It does **not** sign anyone out — losing a session
because you wanted a fresh photograph is a poor trade, and on a weak signal
signing back in is not small. Any key containing "token" or "session" is skipped
whatever it is called, so a key list that drifts out of date costs a stale cache
rather than someone signed out mid-trip.

**A sound when an offer arrives.** `SystemSound` and a haptic, not a bundled
clip: the phone's own notification tone already respects silent mode and the
volume the person set, where an audio file would ignore both and play at full
volume in a mosque. Fired once per offer id — an alert tied to "offers exist"
rather than "a new offer arrived" would chime continuously while someone read
the first one.

## 60. I cannot run the app

Asked to run the whole thing and check it works. I cannot, and it is worth being
exact about why rather than implying otherwise.

There is no Flutter or Dart SDK available here, and the network policy blocks
the installers — `apt-get install dart` finds no package, and dot.net and
pub.dev are not on the allowlist. The .NET SDK installed from the Ubuntu archive
this week, which is how `check_syntax.sh` became possible, but there is no
equivalent for Dart.

What runs against this ZIP:

| Check | Result |
|---|---|
| `audit_structure.py` | clean |
| `check_imports.py` (4 checks) | clean |
| `check_on_conflict.py` | clean |
| `check_syntax.sh` — real Roslyn parse | clean |
| admin portal `tsc` + `next build` | compiled |

The admin portal is the only part genuinely compiled here, and it has not broken
a deploy once. The Flutter side has four text-level checks and no compiler,
which is exactly why `flutter analyze` in CI matters more than anything I can
add.

## 61. The colour picker did nothing

Two faults, and the second is the one that mattered.

**The picker did not redraw itself.** Nothing in that subtree was subscribed to
the store, so selecting a colour notified listeners and the ring never moved.

**And almost nothing else would have changed anyway.** `AppColors.secondary` was
a compile-time constant used in 101 places. Only the handful of widgets driven
by `ThemeData` would have repainted — the rest would have stayed amber, which
looks broken rather than customised.

The accent tokens — `AppColors.secondary`, `AppColors.accent`, `AppTint.brand`,
`AppText.onBrand` — are now runtime getters reading the store. The cost is that
Dart rejects them inside `const` expressions: there were seventeen such places,
all fixed, and **`check_imports.py` now fails if a new one appears**. With no
Flutter compiler here that guard is the only thing standing between this and
another failed deploy.

## 62. Sound on both sides

Neither side was told anything had happened.

A Driver waiting for work is not staring at the screen, and a request lives
fifteen seconds — arriving silently means it is usually gone before it is
noticed, which looks to them like the platform has no work. Same for a Customer
waiting on offers.

`SystemSound` and a haptic on both, not a bundled clip: the phone's own
notification tone already respects silent mode and the volume the person set,
where an audio file ignores both and plays at full volume in a mosque. The
haptic covers a silenced phone, which on a driver's handset is the usual state.

Fired once per request or offer id. An alert tied to "requests exist" rather
than "a new request arrived" would chime continuously while someone read the
first one. The driver's alert is also skipped while they are offline — someone
who has switched off should not be buzzed by work they declined to receive.

## 63. A raised fare goes back to everyone

Drivers who had already declined or quoted were excluded from seeing the request
again. So the Customer raised their fare and it reached a **smaller** pool than
before — the opposite of what raising it is for. The Driver who quoted 2,000 and
was passed over never learned the Customer had come up to 1,900.

Decisions older than the fare change are now ignored.

This needed its own column. `updated_at` moves whenever anything about the
request changes — including the status flipping to ReceivingOffers the moment
the first offer lands — so reusing it would have cleared every Driver's decision
on every offer and re-alerted the whole area each time.

## 64. Messages, arrival, and the trip code

**A message now sounds.** The bubbles float over the map, but a customer
standing at a kerb is usually not looking at the screen — a message arriving
silently is read minutes later, by which time the driver has given up asking.
Once per message id, and never on the first load: everything is unseen then, and
chiming through a conversation somebody has already read is noise.

**"I have arrived" reaches the customer.** Sound, a heavy buzz, and a snackbar
that stays eight seconds. It is the one status change a waiting customer must
not miss — they may be indoors while the driver is already outside.

**The trip code explains itself.** The driver's dialog said "Enter Trip OTP",
which is mechanics and no purpose — and a step whose purpose is unclear is one
people work around, asking for the code through a car window or starting a trip
with the wrong passenger aboard. Both sides now say what it is for: it confirms
the right person is in the vehicle and it starts the fare, so nobody is charged
for a trip they did not take and no driver is blamed for one they did not carry.

## 65. The driver's live ride screen

It was still white cards on light greys while the rest of the app moved to the
dark teal palette, so opening a live ride looked like leaving the app. Surfaces,
borders, ink, the ETA chip and the action buttons all come from the theme now.
The map pin stays white — it sits on a map, where white is the right contrast.

**A proper passenger record**, in place of the one-line chip: how many rides
they have taken on UDrive, how drivers have rated them and how many did the
rating, and any cancellations. The same information the customer already gets
about the driver, pointed the other way — a driver pulling up to a stranger is
entitled to know something about them, and the app told them a name and nothing
else.

No default rating here either. "No driver ratings yet" rather than a five
nobody gave.

## 66. A steering wheel on the top button

The customer header's mode button showed `swap_horiz` — two arrows, which say
"change something" without saying into what. It now carries the drawn steering
wheel.

## 67. The audit caught me removing four widgets

Replacing `_PassengerChip` with the larger record, I sliced from its doc comment
to the next class and took `_FloatingMessage`, `_RoundAction`, `_DriverAction`,
`_DriverStars`, `_ReviewCard` and `_VehicleFallback` with it — six widgets, all
still referenced.

`audit_structure.py` reported every one as an undeclared widget, and I restored
them. This is the second time an index-based slice has eaten code in this file;
the lesson is that `s[start:end]` between two class names is only safe when
nothing lives between them, and in a 2,000-line file something usually does.

## 68. The const conversion broke the build, and my check said it was fine

`rev 94` turned the accent tokens into runtime getters and removed `const` from
the places that used them. The check I wrote to guard that looked **one line at
a time** — and `const` is not line-based. An outer `const TextStyle(` four lines
up makes everything inside it constant too, so:

```dart
style: const TextStyle(        // line 130 — no token here
  fontSize: 15,
  fontWeight: FontWeight.w900,
  color: AppColors.secondary,  // line 133 — fails
),
```

My check passed clean on thirty-six such sites. `rev 95` shipped on top of the
same fault.

### Fixed

All thirty-six, plus two more the compiler surfaced:

- **`DriverReviewsScreen`'s constructor lost its `const`.** In
  `driver_pages.dart` each class sits on one line, so a blunt line edit hit the
  *declaration*, and every `const DriverReviewsScreen()` call site then failed.
- **Two top-level declarations lost their keyword entirely** — `const services =
  [` became `services = [`, which is not valid Dart at all. They are `final` now.

### `tool/check_const_colours.py`

The replacement walks the balanced bracket group each `const` opens and checks
the whole body, not the line. It also carries two guards for the damage the
first pass did:

- a class invoked as `const X(` must declare a const constructor
- a top-level assignment must have `final`, `const`, `var` or a type

Verified by running it against the v99 tree, where it reports **38 problems**,
and against this one, where it reports **0**.

The narrow scope is deliberate. The keyword-less check first matched class
fields and method bodies too — a hundred harmless lines — and a check that cries
wolf is one people switch off. Column zero only.

### The honest part

This is the second time a guard I wrote reported clean while the build was
broken, and both times for the same reason: I approximated a language rule with
a regex instead of using the language. `flutter analyze` would have caught all
thirty-eight in one pass. It is already the first job in
`.github/workflows/build-android-apk.yml`.

## 69. A third shape: default parameter values

`UdCircle` declares its colours as defaults:

```dart
UdCircle({
  this.fill = AppColors.secondary,
  this.stroke = AppColors.secondary,
});
```

**Every default parameter value in Dart must be a compile-time constant** —
const constructor or not. The accent is a runtime getter now, so both are
illegal, and neither of the two checks written yesterday sees them: there is no
`const` keyword anywhere near.

`fill` and `stroke` are nullable, with `fillColour` and `strokeColour` getters
that fill in the accent when the circle is drawn. Callers pass neither, so
nothing else changed.

The check now also scans parameter lists. Verified against the v101 tree, where
it reports both lines, and against this one, where it reports zero.

### Counting honestly

That is three distinct shapes the same conversion broke, across three builds:

1. `const` on the line with the token — caught by the first check
2. `const` several lines above it — missed; the check was line-based
3. A default parameter value, with no `const` anywhere — missed by both

Each time I extended the check after the compiler found the case, which means
the check has only ever been as good as the failures already seen. A fourth
shape may exist; I cannot rule it out by looking, because I am matching text
against a language rule instead of asking the language.

`flutter analyze` finds all three in one run, and every one of these three
builds would have been stopped by the job that already sits first in
`.github/workflows/build-android-apk.yml`.

## 70. Vehicle choice screen, rebuilt as "prices on the pills"

Same bones as before — photograph, category pills, nearby drivers — with the
four things that were wrong taken out.

**Every vehicle's fare sits on its own pill.** The comparison is the decision,
and it used to be four swipes deep: to find out what a Coster cost you paged
through the photographs one at a time. Four numbers side by side answer it at a
glance. The pills are equal width now, so all four fit without scrolling.

The pill fare is always the **whole-vehicle** price, even when the selected
vehicle is set to per-seat. Comparing a Coster priced for two seats against a
whole Car is not a comparison — it is two different questions with one number
each.

**The per-kilometre line is gone.** It was also the line being cut in half by
the bottom bar in the screenshot.

**Seats and the driver count moved onto the photograph.** The line of grey text
under it — `4 seats · Saloon car…` — was the kind nobody reads, and the driver
count was hidden behind a second row of controls. Both are now badges on the
picture, costing no height at all. The nearby badge is tappable: it swaps the
photograph for the map, with a plain way back, because a view you can enter and
not leave is a trap.

**The route is one line.** Two stacked From/To blocks spent about ninety pixels
saying what an arrow says. The destination keeps its weight; the pickup is where
the customer is standing and they know that already.

`_HeroToggle`, `_Half` and `_RateBasis` are deleted — all three existed to
support what was removed.

### Still needed from you

The photographs. The one in the screenshot is Toyota's five-car marketing shot
— not your vehicle, not the one arriving. Upload one clear picture per category
in the admin portal, single vehicle, plain background, side on, and all four at
the same aspect ratio. No layout looks good around a lineup photo letterboxed
into a card.

## 71. Photographs, the trip code, arrival, and messages

### The vehicle picture was looking in the wrong place

It was resolved from the **category** — and categories are free text. A driver
registering types whatever the form offered, and the seeded fleet uses `SUV` and
`Bus`. Matching only `Car`, `Bike`, `Coster`, `Hiace` meant most real vehicles
fell through to the fallback icon, which is exactly what the screenshot shows.

Two fixes. `vehicles.image_url` — **the vehicle's own photograph** — now comes
through tracking and is used first; a driver who uploaded pictures of their
actual car should not have a stock image of a different one in their place. And
the category mapping accepts the names people actually use: SUV, sedan, saloon,
hatchback, motorcycle, scooter, bus, minibus, van, high roof.

### The driver photograph exists after all

There is still no profile-photo column, and I said twice that meant no picture.
That was incomplete: **the approved SELFIE document is a photograph of the
driver**, already uploaded and already reviewed. Asking for a second one would
be asking for a picture the platform holds.

`GET /api/v1/trips/{bookingId}/driver-photo` serves it, scoped to the booking —
a Customer sees the Driver coming for them and nobody else. Driver photographs
are not browsable. Initials remain the fallback, because a broken-image glyph
where a face should be is worse than a letter.

### The trip code could not survive a restart

`trip_otp_hash` is a hash by design. But the Customer has to *read* the code
out, and a hash cannot be read back — so it existed only in the response that
created the booking. Reopen the app, go in through "Track ride", and the panel
was simply gone. The trip could not be started at all.

`bookings.trip_otp` stores it readable, returned only to the Customer who owns
the booking. Not to the Driver — who would not need to ask for it, and the whole
point is that they must. Not on a share link. Verification still compares
against the hash.

### Arrival stays on screen

A snackbar lasts eight seconds and vanishes, and the person who most needs this
is the one who put the phone down. A green block now replaces the ETA — "1 min
away" is wrong once they are outside — and names the registration to look for.
It stays until the trip starts.

### The driver was never told about messages

The Driver screen had **no message polling at all**. A Customer could write "I am
at the blue gate" and the Driver would never know, because messages were only
read inside the chat screen. Both sides now poll, sound once per message, and
show the newest one inline — tappable straight into the thread.

## 72. Light theme, and the home screen rebuilt

### The whole app is light now, not just home

Changing one screen to white would have left the app half dark — one screen
white, the next black. The palette tokens moved instead, so every screen that
reads them came along.

Background `#FFFFFF`, surfaces `#F5F8F6` and `#ECF1EE`, text `#0F1512`, border
`#E3EAE6`. Status colours all darkened: the dark theme's mint, coral and sky
disappear on a white page.

**Two greens, not one.** The logo's green is light, and white text on a light
green fails contrast at button sizes — unreadable in daylight, which is where a
ride app is used. So the action colour is a deep `#178B55`, and the light green
lives in `AppTint.brand` as a wash behind selected tiles and badges, where it
carries colour and no text.

The three accents became Green, Blue and Amber, all dark enough to carry white.
Green is the default.

`brightness: Brightness.light` is set on `ThemeData` as well as the scheme,
because without it Material picks dark defaults for everything the scheme does
not cover — scrims, ripples, switch tracks.

### Home, as H8

Map on top with the pickup pill, then the service card, then search and recents.

**Two ranks of service.** Cards for the two that start a booking — City rides
and City to city — and an icon row beneath for the rest. A card carries a title,
a subtitle and a picture; four of them side by side is four things competing. An
icon and one word is enough for somewhere you already know you want to go.

Hotels moved down into that row, which freed the second card for **City to
city** — the other kind of ride, out of town rather than across it.

**Car rental is there with a SOON badge**, and tapping says so plainly. Shown
rather than hidden because "can I rent a car myself" is a question customers ask
and the app gave no answer to at all — not even "no". It does nothing else on
purpose: a form that collects interest and posts it nowhere would be worse.

**City rides says the driver count** when there is one. "3 nearby now" is the
most useful thing that tile can say, and the vehicle list is on the next screen
anyway.

**The colour picker moved to Settings**, beside Clear cached data. It is a
personalisation someone sets once, and it was sitting above the thing they open
the app to do.

### The sweep, and what it did not reach

`Colors.white70` and `Colors.black` were light-on-dark choices that invert on a
white page. Seventeen files swept across the customer side.

**Driver mode and the live trip screens were deliberately left out.** They were
already built on light surfaces with their own hard-coded inks, so they are not
broken — but they are not on the tokens either, and they will need their own
pass when we get to the driver home. Not touching them was the point: you said
driver mode comes after.

## 73. The map was dark on the server, not in the app

The basemap stayed dark after the theme flipped, because it is not styled in the
app at all — `PlacesController` styles it when it creates the Google tile
session, and that payload was still painting geometry `#16232D` with pale grey
labels.

Restyled light, close to Google's own default. Points of interest and transit
stay off: the map exists to show a route and nearby vehicles, and every extra
label competes with the markers that matter.

**This is an API change.** The tiles will keep arriving dark until the API is
deployed, whatever the app does.

### The shade over the map

A gradient from transparent to the page colour, softening the join with the
sheet. It made sense on a dark page. On white it is a grey wash over the bottom
of the map — a smudge rather than a transition — and the sheet's own rounded top
already does the softening. Removed.

### The shadows

`AppShadows` were black at 35–50% opacity, which is what a dark theme needs to
lift a panel off a near-black page. On white the same values print as grey
smudges under every card, and as the haloes visible around the header icons.

Reduced to 6–8% for cards and panels. `floating` — the controls that sit on the
map — is now **empty**: on a light map they had nothing to lift off, and the
shadow read as a ring of dirt around each icon. A white button on a light map is
already distinct.

### Panels are white, the page is grey

The other way round from before. A grey panel on a white page is inverted: the
content should be the bright part and the page the quiet one. Panels are white
with a hairline border, on a `#F5F8F6` page.

### Type is two points larger

The old sizes were set for a dark page, where light text on dark reads slightly
larger than it measures. On white the same numbers look thin. Every step of the
text theme went up two points, and the home screen's own sizes by 1.5.

### The language pill is gone

Language is set once and then never again, and it was taking a permanent seat in
the header beside the two controls people use daily. It belongs in Settings.

## 74. Transparent header, and services the admin can close

### The header floats on the map

A white bar across the top spent about fifty pixels on a logo and two buttons —
the same fifty the map wanted. The controls sit on the map now, which is where
every other map app puts them, and the map reaches the top of the screen.

The buttons became solid white with a hairline and no shadow. On a light map a
shadow is a ring of grey around the icon rather than depth, and the old 94%
translucency let street names show through them.

### Coming soon is an admin switch, not a code change

`udrive.service_availability` holds one row per service: open or not, the badge
to show, and the sentence a customer is told on tapping. The admin portal has a
**Services** page to edit them.

Whether Coster is ready is an operational fact that changes without a release —
it needs vehicles registered first, car rental needs a fleet, city-to-city needs
drivers willing to leave town. Hard-coding that meant a deploy each time one
became ready.

**Closing a service is customer-side only, and that is the important part.**
Drivers keep registering vehicles for a closed service and admins keep verifying
them, so on the day the switch flips there is already a fleet. Without it the
platform deadlocks: closed because there are no vehicles, and no vehicles
because it is closed. This is exactly what you asked for — *"driver ko option
hoga ke wo apni vehicles add kar sake"*.

Three decisions inside it:

- **Closed tiles are shown, not hidden.** Dimmed to 55% with a grey badge. "Can
  I do this yet" is a question customers ask, and a missing tile answers it with
  silence.
- **A closed tile still responds** — it shows the admin's sentence. A dead tap
  leaves someone wondering whether the app is broken.
- **Missing means open.** A failed call or an unknown key leaves the service
  working. Closing on absence would let one bad response take the whole home
  screen down.

The badge is grey rather than the action colour: a badge in the colour of
buttons reads as something to press.

Everything is seeded open except `carRental`, which has no screen behind it yet.

## 75. The home screen I broke

Fair report. The screenshot shows the header, the pickup pill and the nearby
chip stacked on top of each other, the attribution bar still black across the
map, "Show map" still there, and the artwork printing through the card text.

Three separate failures, and the first is the one worth naming.

### I implemented half of an approved design

The cleanup mockup removed the attribution bar and the "Show map" row. That
mockup was approved. I then implemented the transparent header and the service
switches — and **left both of those untouched**, because they were described in
the reply rather than written down as work.

They are done now: a plain `Google` label in the corner instead of the bar, and
the handle row deleted along with `_SheetHandle` and `_lowerSheet`.

On the attribution: Google's terms do require it on Map Tiles imagery, so it
cannot go entirely. But two thirds of that bar was required by nobody —
`flutter_map` is the name of a library, and OpenStreetMap is only the fallback
source. What is left is what Google's own SDK shows.

### The transparent header collided with everything

Moving the header into the map was right; leaving the map at 22% of the screen
was not. That is about 170 pixels holding a header, a centred pickup pill, a
nearby chip and a locate button — so they sat on each other.

The map is one fixed height now (30%, 230–330px). The two-height lifted/lowered
state went with the handle: with the sheet fixed open there was no second state
to reach. The centre pin is offset below the header rather than centred in a
stack that now starts at the top of the screen, and the bottom overlays moved
from 60px up to 14px, since the fade they were clearing is gone.

### The type change broke the cards

The artwork was oversized and bleeding off the bottom corner, behind the words.
That worked at 15pt titles and stopped working at 17 — the car icon prints
straight through "Car · Bike · Coster · Hiace" in the screenshot. The icons are
smaller and inset now, and the card block went from 148 to 172 to fit the larger
subtitles.

A type change is never only a type change. I raised every size in the theme and
checked nothing that had been laid out around the old ones.

## 76. Alignment, structurally

The last round moved offsets around. That was the wrong fix — fixed offsets in a
stack collide again at the next height. This one changes the structure.

### The map overlays are a column

They were four separate `Positioned` widgets: a header pinned to the top, a
locate button at bottom 60, a nearby chip at bottom 62. At a tall map they
looked right; when the map shrank they landed on each other, which is what every
screenshot has shown.

One `Column` inside the map now: header row, `Spacer`, bottom row. **A column
cannot overlap itself.** The header takes the height it needs, the spacer
absorbs the rest, and the bottom row sits above the map's edge at any map height
at all.

The nearby chip and the locate button share that bottom row rather than being
positioned near each other and hoping. Where the chip is not shown, a `Spacer`
holds its place so the button does not jump.

### One spacing scale in the sheet

The sheet used 12 for panel padding, 12 or 14 inside panels, 10 between blocks,
7 between tiles. Values close enough to look accidental rather than chosen —
which is most of what "not aligned" means when you look at a screen and
something feels off without being able to name it.

It is 14 for gutters, 12 between blocks, 8 between tiles, everywhere.

### The two tags

`flutter_map | © Google · © OpenStreetMap` and the "Show map" row were both
removed in **rev 103**, which the screenshot predates — it still shows the SOON
badge from rev 102 alongside both tags. They are gone in this build, along with
the quick tiles growing to 52px so the icon is not crowded by a label that is
now 12pt.

## 77. Why the boxes were different heights

A real bug, and one I introduced.

`_ProductCard` was wrapped in a `Stack` when the SOON badge was added. **A Stack
passes loose constraints to its non-positioned children by default.** So the
Stack filled its 172px slot while the card inside shrank to fit its own text —
leaving City rides short, Tour and City to city uneven, and a gap under each.

That is exactly what the screenshot shows, and no amount of adjusting heights
would have fixed it: the slot was always the right size, the card just was not
filling it.

`fit: StackFit.expand` on that Stack. It was only ever there to hold a badge; it
had no business changing how the card sizes.

The quick tiles' Stack is deliberately left loose — there it *should* size to
the icon box, and the badge is Positioned so it does not count.

### Text clear of the artwork

The subtitle ran the card's full width and "Hiace" printed over the car. The
text column now has 56px of right padding on the large card, 34 on the small
ones, so the words stop before the icon rather than crossing it.

### Header on one line

The logo was 38 and the buttons 40, in a row sizing itself to whichever was
tallest — so the mark sat a pixel or two low against the circles beside it.
All three are 42 now, inside a fixed-height row that centres them. Small, and
exactly the kind of thing that reads as "not aligned" without being nameable.

### And the header's vertical position

Worth recording because it explains the screenshot before last. The header was a
`SizedBox(height: 40)` directly inside a `StackFit.expand` stack, which forces
tight constraints on it — so the SizedBox could not shrink and the Row centred
its contents down the middle of the map. That is why the logo and icons appeared
level with the pickup pill instead of at the top. The column-and-spacer layout
in rev 104 removed it.

## 78. Black map on one phone, white on another

Both screenshots are the same build. The Android one shows a light map, the iOS
web one a dark map, same account, same minute.

That is the browser cache, and it is the answer I gave before without fixing the
cause. Tiles are served with a seven-day cache and the URL never changed when
the style did, so the browser had no reason to ask again.

The tile URL now carries a style version. Bump it on both sides and every tile
becomes a new URL — nothing stale can be served, and nobody waits a week.

## 79. One ride at a time

A customer could open three requests at once, accept offers on all three, and
leave two drivers holding a booking for someone already sitting in another car.
The drivers pay for that: they turned down other work for it.

`CreateRideRequestAsync` now refuses while a request is still searching or a
booking is under way, with a different message for each — "cancel that request"
and "finish or cancel it" are different instructions.

Scheduled trips are unaffected: only live requests and running bookings count.

## 80. The live sheets start collapsed

Both live screens opened with the panel at full height, covering most of the map
— the one thing both people are watching. Where the other person is, and how far
off.

`CollapsibleMapSheet` shows a single line and **bounces gently** until it has
been opened once, which is the only reliable way to say "there is more here"
without a label explaining itself. Six pixels: enough to catch the eye at the
edge of vision, small enough not to look like a fault.

The bounce stops permanently after the first tap. An invitation that keeps
arriving after it has been accepted is nagging.

Open, it has a close control in the corner where one is expected. Without that
the sheet can be opened and not shut, and the map stays covered for the rest of
the trip.

The collapsed line carries what matters at a glance — the other person's name,
the distance, the minutes — so the sheet does not have to be opened to answer
the ordinary question.

## 81. Route choice, and the fare that follows it

The alternatives were already being fetched — `computeAlternativeRoutes` is on,
and the home screen has held `_routeResult.routes` all along. They were simply
never passed on. Now they are, so the choice costs nothing extra: a second
Directions call would be money spent to return the same answer.

**Shortest first, and selected by default.** Google returns its own order, which
favours time. The customer is being charged by distance, so distance is the
order that matches what they are about to pay.

**The fare follows the route.** A longer way round costs more because it *is*
more — more kilometres for the driver, more fuel, more time. One price for two
different journeys would make the shorter one subsidise the longer.

Choosing a route resets the fare to the recommendation for the new distance. An
amount someone set for a 24 km trip is not an amount they set for a 31 km one,
and carrying it over silently would send out an offer they never made.

### Chips, not only the map

A route drawn on a phone is a few pixels wide, and two alternatives run together
for most of their length — a target nobody hits reliably. The chips say how far
and how long for each; the map shows which is chosen, and its lines are still
tappable for anyone who prefers that.

The lines are drawn in reverse order so the selected one paints last. Otherwise
it disappears under an alternative wherever they overlap, which is most of the
way for most pairs.

## 82. Location, properly

### Every two seconds, not every ten

`TripLocationService` published the driver's position on a ten-second timer. At
40 km/h a car covers over a hundred metres between fixes — so the customer
watched it jump a block at a time, and the arrival estimate was stale before it
finished drawing.

Two seconds now, and the customer's tracking screen polls at two seconds to
match. Polling slower than the driver reports throws away fixes already paid for
in battery; polling faster returns the same point twice. They should be the same
number, and they were not.

It costs battery and data, and that is the right trade while somebody is
standing at a kerb. It stops the moment the trip ends.

### Accuracy raised on both sides

`bestForNavigation` for the driver's live stream. `high` is roughly ten metres
and lets the platform smooth and batch readings, which on a moving vehicle
produces a position a second or two behind the car and a heading that lags
corners — exactly the wobble that makes a live map look broken.

`best` for both one-off fixes: the customer's pickup and the driver's own
position. The pickup decides where a driver is *sent*, and a hundred metres of
error is the difference between the right gate and the wrong street. These are
taken once rather than continuously, so the battery cost is a rounding error.

The driver's fix also has a shorter time limit. A fix arriving after the next
one was due is worse than no fix — it publishes a stale position as current.

## 83. The second booking, stopped earlier

The server already refused it (rev 106). But only at the end: after the customer
had picked a destination, chosen a vehicle, named a fare and pressed Find
offers. Being told "no" after all that is worse than never being offered the
path — they have to work out what they did wrong, and the answer is a ride they
may have forgotten was running.

Two changes:

**`_activeTripStatuses` was missing `Confirmed` and `DriverAssigned`.** That is
why a second booking could still be started while a car was on its way: the
banner showed, but nothing else treated it as a ride in progress.

**The flow stops at the start and opens the running ride instead.** That is what
they would have to do next anyway, and it answers the question rather than
blocking it.

Tour and package bookings are deliberately **not** covered. A tour booked for
next Tuesday is not a live ride, and two tours on different dates is a
reasonable thing to want.

## 84. A check that has not earned its place

I said an inline `//` comment had commented out the rest of a dense line, and
wrote a check for it. It had not: `return;// note` followed by a newline is
valid, and the code after it was on the following line.

The check is corrected — its first version flagged a perfectly good trailing
comment — and kept, because it is cheap. But it has caught nothing real, and I
should not have announced a bug I had not verified.

## 85. The build break, and a check that would have caught it

`VehicleChoiceScreen` used `widget.routes` and never declared it. The edit
script that added the field asserted its way out partway through, so the code
*using* the field landed and the declaration did not — the same shape of failure
as §40, and the second time it has shipped.

### A seventh check

Within one file this is decidable. A `State` reaches its widget through
`widget.<name>`, and a `widget.foo` with no `foo` declared anywhere in the file
cannot resolve. `check_imports.py` now reports it.

Verified by removing the `routes` field again and confirming the check fails.

Its first version matched the class body with a regex needing a newline before
the closing brace — and several of these files write a whole class on one line,
so it matched nothing and reported two perfectly good widgets as broken. Looser
is right here: the question is whether the name exists at all.

## 86. The location interval is an admin dial

Hard-coding two seconds was replacing one wrong constant with another. Fast
makes the map smooth and costs the driver battery and data; slow makes the car
jump a block at a time. **Which trade is right depends on how many drivers are
online, what a megabyte costs them, and how much of the fleet is on an old
handset** — none of which is a reason to cut a release.

`system_settings.tracking.ping.seconds`, with buttons for 1, 2, 3, 5, 10, 15 and
30 seconds on the admin Services page.

Both apps read the same number, which is the point: the driver publishes at it
and the customer polls at it. They were 10 and 5 before — the customer asking
twice for every fix, and still seeing a car that jumped.

Clamped 1–60 on the server. Below a second the fixes arrive faster than GPS
produces them and the extra calls are pure cost; above a minute the map is not
live in any useful sense. A value that makes the product stop working should not
be reachable by a typo.

The tracking screen starts at the default and re-times itself once the server
answers, rather than showing nothing while it asks how often to show things.

## 87. The map follows the car now

Both live maps framed **both ends** of the journey — the car and where it was
going — and fitted the camera to hold them.

That reads well as an argument: "where is it and how far off" is the question.
It is wrong in practice. With the driver five kilometres out, both ends fit only
at a zoom where the car is a dot among streets nobody recognises. That is what
"it is showing some other location" means: the car was on screen, at a scale
where it could not be found.

**The car stays centred and the zoom carries the distance.** Under 400 m you see
the street it is turning into; at 8 km you see enough road to judge the wait.
Same on the driver's map, where fitting the leg put their own position at the
edge of the screen with the road ahead off-frame — the opposite of what a map is
for while driving.

Both maps also open at zoom 16 rather than 13. The first frame, before any
tracking has arrived, used to show a district; opening close and widening if the
car turns out to be far is the better way round.

### A way back to following

Panning stops the camera, which is right — a map that snaps back cannot be used
to look ahead. But there was no way to resume, so **one accidental swipe ended
live tracking for the rest of the trip**, with nothing on screen to say why the
car had stopped moving.

A recentre button now appears on both maps, and only once the camera has been
taken: a control that does nothing until it is needed does not need to be there
before.

## 88. Both radii are admin dials now

Yes — and it turned out to be two settings rather than one.

**Request radius.** How far from a pickup a driver may be and still be offered
the job. It was `ST_DWithin(..., 5000)` written into the eligibility SQL. Five
kilometres in a dense town is a lot of drivers and a lot of notifications nobody
acts on; in a valley where the next car is twenty minutes away it is nowhere
near enough. One number cannot serve both.

**Nearby radius.** How far around themselves a customer is shown vehicles on the
home map. This was 5 km in the app, which is why the map could show cars that
were never realistically going to come. The default is now 1 km.

They are deliberately separate. Reach and honesty are different questions, and
tying them together would mean widening the map every time you widened the
search. Keeping the map tighter than the search is usually right: an
empty-looking map is more honest than a busy one that produces no driver.

Both are on the admin Services page, alongside the location interval. Clamped on
the server — 0.5–50 km and 0.2–25 km — because a value that makes the platform
stop working should not be reachable by a typo.

The app reads them on the same call as the ping interval, so three settings cost
one round trip.

## 89. Driver sign-up, in four steps

The old flow was two long screens: every document on one, every vehicle field on
another. A form showing twenty questions at once reads as an hour of work
whether it is or not, and there is no way to tell how far through you are.

Same work, four subjects, a progress bar. **Choose your vehicle** first — on its
own, because it is the one decision somebody can make without looking anything
up, and it changes what the rest asks for. Then:

1. **Personal information** — photograph, first name, last name, date of birth
2. **Driver licence** — front, back, number, expiry
3. **CNIC** — front, back, selfie holding it, number
4. **Vehicle** — photograph, registration front and back, brand, model, colour,
   plate, year

### Decisions inside it

**Nothing is sent until the last step.** Photographs are held in memory and
uploaded together. Somebody who abandons at step three should not leave three
orphaned files and a half-made profile in the reviewers' queue.

**Next is disabled until the step is complete**, rather than allowing it and
complaining afterwards — what is missing is on the screen in front of them.

**The date pickers are bounded.** Date of birth opens twenty-five years ago and
will not accept anyone under eighteen; licence expiry will not accept a date in
the past, because an expired licence is not a date to record, it is a reason the
person cannot drive yet.

**Two vehicle fields are inferred rather than asked.** Seats follow the category
— 1 for a motorcycle, 3 for a rickshaw, 4 for a car — and luggage is left at
zero. Asking a motorcycle rider how many suitcases it takes is a question with
no useful answer, and five more fields is how a four-step form becomes six.

**Address and emergency contact are sent empty, not invented.** The endpoint
requires them and these four steps do not ask. A made-up address in a
verification record is worse than a blank one, because a reviewer would believe
it.

### Two new documents

`DRIVING_LICENCE_BACK` and `SELFIE_WITH_CNIC`. The licence back carries the
categories — which classes of vehicle the person may actually drive — and a
selfie held beside the card is what ties the person to it. Both were being asked
for by hand.

Vehicle approval now requires the registration front **and** back plus a vehicle
photograph, and no longer requires rear and interior shots — the new flow never
asks for them, and requiring them would block every driver who signs up through
it.

## 90. `FilePicker.platform`, again

The build failed on `FilePicker.platform.pickFiles`. This project's file_picker
exposes the **static** form.

It broke the build the same way in rev 73. After that I wrote a comment in
`driver_documents_screen.dart` explaining it — and then wrote a new screen
without reading my own note, because a comment in one file only helps somebody
who opens that file.

### A check instead of a comment

`check_imports.py` now carries a list of wrong API forms this codebase has
already used, and fails on any of them wherever they appear. One entry so far.
Each has to earn its place by breaking a build, which this one has done twice.

Verified by putting `FilePicker.platform` back and confirming the check fails.

That is the useful shape for this class of mistake: not a note asking the next
person to remember, but a check that does the remembering. The same reasoning
covers the const-colour check and the widget-field check — three of the last
five failures were repeats of an earlier one.

## 91. Why submit failed, and what the admin needed

### The submission

`DriverOnboardingRequest` had `Address`, `EmergencyContactName` and
`EmergencyContactPhone` as `[Required]`. The four-step sign-up does not ask for
any of them, so I sent empty strings — and **`[Required]` rejects `""` exactly
as it rejects null**. Every submission failed.

They are optional now, which is the honest fix rather than inventing values to
satisfy an attribute. The columns were always nullable; only the request
insisted. The client omits them entirely, and the service stores null rather
than an empty string — a blank column reads as "not collected yet", an empty
string reads as "collected, and empty", and those are different things to a
reviewer.

The emergency phone is validated **only when one is given**. An empty field is
not a wrong phone number, and refusing a submission over a question that was
never asked leaves someone rereading a form for a mistake that is not there.

### The admin side, which you were right to ask about

Three things were out of step:

**Document labels.** The portal ran the type through a prettifier, so
`SELFIE_WITH_CNIC` showed as "Selfie With Cnic" and `SELFIE` as "Selfie" when
what the driver was asked for was a personal picture. Proper names now, with the
prettifier as the fallback for anything not yet named.

**The counter said `/4`.** With six driver documents it would have read as
complete while two were missing.

**The approval blockers list was a separate copy** of the required types, and it
had not been updated — so the portal would have said a driver was ready and the
API would have refused to approve them. It reads from the same list as the
ordering now.

Reviewers see them in the order the driver sent them, and **an unknown type
sorts to the end rather than vanishing** — a type this page has not been taught
is still something the driver uploaded, and hiding it would mean approving
someone without seeing it.

## 92. Coster, Hotel, and the four things that were wrong

### The list is no longer only vehicles

**Coster** and **Hotel** added. A hotel is not a vehicle, and the screen said
"Choose your vehicle" — putting a hotel on that list would have been a small
lie, so the question widened to **"How do you want to earn?"** Everything on it
is a way to earn, and the form that follows depends on which is picked.

Hotel goes to the hotel owner shell rather than the driver steps. It has no
licence, no number plate and no selfie-with-CNIC; four screens of questions with
nothing to answer is not a form.

Coster takes the same four steps with 22 seats rather than 4.

### The text fields could be seen and not reached

The label and the input were stacked in a `Column` with the input's padding
zeroed, so the tappable area was one line near the bottom of a 60px box. The
`TextField` draws its own background and carries the label now, which makes the
whole control the target.

### The drawer was white on white

Every ink in it — the name, the menu rows, the dividers — was `Colors.white`,
chosen when the drawer was a dark teal panel. When the palette flipped, the
surface went white and the text stayed white. The menu was there and invisible.

### Nothing happened when you submitted

The screen closed and returned to a menu, which looks identical to having
crashed. There was nothing to tell a driver whether an hour of photographing
documents had worked.

A confirmation now says what happens next and **how long it takes** — "our team
checks new registrations within 24 hours" — and that the app can be closed.

### And nothing showed afterwards

This is the one you were right to press on. An unapproved driver was sent to the
chooser **every time**, whether they had submitted an hour ago or never started.
Submitting changed nothing on screen, so there was nothing to come back to and
people reopened the app to find out.

`DriverVerificationStatusScreen` covers four states, and each says what to do
next rather than only what has happened: with our team, something needs sending
again (with the reviewer's own note, when there is one), approved, or not
finished yet. Pull to refresh, and a **Check for an update** button — someone
waiting on a decision looks more often than any polling interval worth running,
and a button they pressed is more reassuring than a screen that might be
updating.

## 93. Commission: when it is taken, who decides, and what the driver sees

### It was charged at the wrong moment

`ChargeCommissionAsync` ran on `TripCompleted`. A driver who drops someone off
and then loses signal, closes the app or runs out of battery **never sends the
completion** — so the charge never happened and the platform carried rides it
was not paid for. That is most likely exactly what you were seeing.

It runs on `TripStarted` now: the moment the passenger is in the vehicle and has
read out the code, which is when both sides have agreed the ride is happening.
Still keyed on the booking, so a status set twice cannot charge twice.

### The rate is an admin setting

0, 5, 8, 10, 12, 15, 20 or 25 per cent, on the admin Services page. Clamped 0–40
on the server: zero is a legitimate choice while building a fleet, and a typo
that empties a driver's balance in three rides is not a setting.

### The driver sees the whole ledger

`GET /api/v1/driver/wallet/commission` returns one line per ride: when, which
booking, the fare, the rate and the amount taken — cancellation charges
included, marked as such.

A balance on its own invites the question a driver cannot answer: *where did it
go?*

The rate on each line is **derived from what was actually taken** against that
fare rather than read from settings when the screen draws. Someone looking back
at last month should see what they were charged, not what the rate happens to be
today.

## 94. Home screen

**The pickup pill said "MV62+682 Unity Plaza, Margalla View Block B D-17,
Islama…"** — a Plus Code and an ellipsis. It shows the first meaningful part of
the address now, with any leading Plus Code stripped: precise, machine-readable
and meaningless to the person standing there.

**"No cars nearby right now" is off the map.** A wide white bar saying something
the City rides tile already says, in the one place where the only thing worth
showing is the map. When there are cars the markers say so; when there are none,
an empty map says so.

**Titles are bigger and heavier** — 21pt on the large tile, 15.5 on the small
ones. They are the headings of the screen and were reading as captions.

**City rides shows a bike and a car.** The tile covers car, bike, Coster and
Hiace, and a single car made it look like the car option rather than the
category containing it.

## 95. Welcome credit, and where the money goes

### The credit is a setting because its usefulness expires

Early on it buys a fleet: a driver who has to top up before their first fare has
been asked to pay to find out whether the platform works. Once there are
drivers, that reason is gone and the figure comes down — which is exactly what
you said, and why it is a field rather than a constant.

Default 1,000, clamped 0–20,000. Zero turns it off, which is where it ends up.

Paid **inside the approval transaction**, so a driver cannot end up approved
without it or credited without being approved. Keyed on the driver profile, so
re-approving after a suspension — or an admin clicking twice — credits nothing
further. It is a welcome, not a monthly payment.

### The EasyPaisa number was nowhere

The Add funds sheet explained the process and asked for a transaction ID
**without ever saying which account to pay**. The number lived in a WhatsApp
message and every driver had to ask.

It is an admin setting now, shown at the top of Add funds with the account name
and a copy button — above the instructions, because "where do I send it" comes
before "how do I record it".

A setting rather than app text on purpose: accounts get closed and ownership
moves, and a number baked into a release means money sent somewhere nobody is
watching until the next deploy. If the call fails the block is not drawn at all
— no account on screen is better than a wrong one.

### Confirming payments

**Admin → Driver top-ups** already exists and is already in the nav: it lists
what drivers have submitted with their screenshot and transaction ID, and
confirming one credits the wallet. Nothing is credited on submission, because a
screenshot is a claim and not a receipt.

## 96. `decimal` into a `double`, and why Railway found it

`CommissionEntryDto.Percentage` was `double`, and the value handed to it comes
from `charged / fare * 100` — a `decimal` division. C# does not convert one to
the other implicitly, and it is right not to: mixing them for money is how a
percentage ends up as 9.999999999999998.

It is `decimal` now, like the money it is derived from.

### Why my checks did not see it

`check_syntax.sh` runs Roslyn **without references**, because NuGet is
unreachable from here. It parses the grammar and finds a missing brace; it
cannot know that `decimal` and `double` are different types, because it does not
know what `decimal` is.

I have said this before. What I had not done is the obvious thing about it.

### The API had no CI at all

The mobile repo has run `flutter analyze` on every push for months. The API had
nothing — so **every C# compile error was found by Railway, on a deploy that
then failed.**

`.github/workflows/build-api.yml` runs `dotnet restore` and
`dotnet build -c Release` on any push touching `udrive_api/`. It is the same
compiler Railway runs, pinned to the same major version as the Dockerfile, so
there is no class of error it can see that this cannot. About a minute, before
anything deploys.

Release rather than Debug, because the two differ on enough analysers that a
Debug-only check gives false confidence.

### A check I wrote and then deleted

I added a step failing the build on duplicate migration numbers. Then I ran it:
`024_hotels_and_stays.sql` and `024_offline_pmtiles_manifest.sql` share a
number, and **both run** — the runner orders by full resource name and records
each by name, so a shared prefix is untidy rather than broken.

It would have failed every build on a healthy repository. That is how a check
gets switched off, and then stops catching the thing it was written for. Removed,
with the reasoning left in the file.

## 97. Approval did not unlock anything until a restart

`refreshDriverProfile()` reloaded the profile. But `driverApproved` reads
`_currentUser.driverModeAvailable` — **the user record, not the profile** — so
the flag stayed stale no matter how often the driver pressed refresh. Killing
the app and reopening it was the only action that reloaded `me()`, which is why
that was the only thing that worked.

It reloads both now, and loads the driver marketplace when the answer is yes, so
the first dashboard a newly approved driver sees has something on it rather than
being empty for another round trip.

### The welcome credit

Paid inside the approval transaction — but that code shipped after some drivers
were already approved. Migration 047 credits anyone approved without it, keyed
the same way the runtime code is, so nobody is paid twice.

## 98. Speed

### After the code screen

`refreshAccount()` was the slowest possible arrangement: `me()`, then the driver
profile, then the vehicles, then seven more calls — **with nothing on screen
until the last one returned.** Ten calls, the first three strictly sequential.

`me()` is the only call the shell needs to choose a screen, so the app is drawn
the moment it lands and the rest arrives into a screen the person is already
looking at. The two groups behind it run together; and the vehicles call no
longer waits on the profile, which it was doing only to check whether a profile
exists — the server answers an empty list for somebody who has none, which is
the same information for one round trip less.

### Open live ride

Three calls ran one after another before anything was drawn: a status change, a
location service start that itself fetches the ping interval, then a refresh. A
driver pressing the button watched a blank screen through all of them.

The refresh goes first, because it is the only one that puts anything on screen,
and the spinner clears the moment it returns. The status change and the location
service follow — neither is something the driver is waiting to see.

## 99. The code screen

White, like the rest of the app. It was still painting a dark green gradient —
the first screen anyone sees, and the only one still wearing the old palette.

Left-aligned and much larger (32pt over two lines). Centred type reads as a
splash screen; this is a form, and a form's question belongs at the left margin
where the eye returns on every line. That matters more here than anywhere,
because the next thing the person does is copy four digits across from a text
message.

## 100. The sign-in screens

**White.** Both were still painting the old dark green gradient — the first two
screens anyone sees, and the last two wearing a palette the rest of the app no
longer uses. The green belongs on the button someone is about to press, not
behind the fields they are about to fill.

**The mark is small, top left.** It was 72px in the centre of the login screen
*and* in the header — two logos on one page, neither of which then reads as the
mark. One, at 44, where a logo goes.

**The language switch is gone.** It was the only thing in the header row, which
made a setting somebody changes once the most prominent control on a page whose
whole job is to collect a name and a number.

**Left-aligned, and larger.** Both screens open with their question — "Welcome",
"Enter your verification code" at 32pt — rather than with branding. Centred type
reads as a splash screen; a form's question belongs at the left margin where the
eye returns on every line.

**"Powered by Wabwar"** at the foot of both, quiet: a maker's mark is not a call
to action, and full contrast there would compete with the button directly above
it. Only on these two screens — once somebody is using the app, who built it is
not information they need on every page.

## 101. The home tiles were washes, not blocks

They were 4% tints. On a white page that is not a colour, it is a smudge — the
tiles read as empty space with words in it rather than as blocks you press.

Deepened to about 25%, with near-black ink on each, which is what makes that
depth safe.

**And the reason deepening alone would have changed nothing:** unselected tiles
dropped to the flat grey surface, so only the selected one ever used its colour
at all. That is why the row looked like one coloured box and three empty ones.
Every tile keeps its colour now, at 45% strength when unselected — selection
reads from depth rather than from colour-versus-no-colour.

The ink no longer switches on selection either. That existed to cope with the
grey unselected state; with every tile coloured, one ink reads on both.

Still short of full-strength brand colour. Four saturated blocks side by side
compete with each other and with the one button on the screen.

## 102. Why the pickup lands on the wrong street

Several causes, and one of them was a bug I left in.

**A stale fix was being accepted silently.** When the live reading timed out,
the code fell back to `getLastKnownPosition()` — wherever the phone was when it
last looked, which may be an hour ago and a street away. Nothing in that answer
says how old it is, so the customer saw a confident pickup on the wrong road.
It is only accepted now when it is under two minutes old; otherwise they are
asked to try again, which is honest about not knowing.

**A vague fix was being presented as a precise address.** `accuracy` is the
radius the phone believes it is within, and above about 60 metres that circle
covers more than one street — exactly the "it says Street 20 and I am on Street
19" case. The pickup row now reads **"Check this"** in amber rather than
"Change", because one is an option and the other is a request.

### The causes I cannot fix in code

**On the web build, geolocation is the browser's, not the phone's.** In a phone
browser that is usually GPS, but often a cached reading; on a laptop it is WiFi
and IP triangulation, which is accurate to a block at best. The installed
Android app gets a genuinely better fix than the Railway web app, for the same
person standing in the same place.

**Reverse geocoding snaps to the nearest named road.** Google is given a point
and returns a street; between two parallel streets 20 metres apart it picks one.
Nothing about the fix is wrong — the naming is a guess, and the pin is the truth.

**GPS between buildings is 20–50 metres.** Narrow streets with walls on both
sides are the worst case for it, and no setting changes that.

Which is why the draggable pin matters more than any accuracy setting: the
customer standing there knows where they are, and moving the pin is the one
correction that is always right.

## 103. Finding the coming-soon switches

They are on **Admin → Control Centre → Services**, which is where I put them and
not where anybody would look. Renamed to **"Services & coming soon"**, because a
page should be named for what somebody is trying to do rather than for the table
behind it.

The page has existed since rev 102. If it is not in the sidebar, the admin
portal has not been deployed since then — that is the thing to check first.

## 104. The pin was pointing at the wrong place

You spotted the right thing: the blue dot was correct and the pin was not. So
the location was never the problem — the drawing was.

Two faults, both mine.

**The pin was anchored on its middle.** It is a label, a head, a stem and then a
dot, and the dot is the point being chosen. Centring the whole column put its
*middle* on the map centre, leaving the dot roughly half a pin below where the
map said it was. `FractionalTranslation(-0.5)` lifts it by half its own height
so the bottom lands on the centre — fractional because the label's height
changes with the address in it, and a fixed offset would only be right for one
of them.

**And I had pushed it further down.** In rev 104 I offset the pin below the
header so its label would not ride under the logo. That moved it off the centre
it represents — clearing the header is the header's problem, not the pin's.

Between them, that is a pin drawn most of a street away from the point it marks.

## 105. Uploading vehicle pictures

The portal only accepted a URL. That puts the picture on somebody else's
server, and those links rot: a host changes a path, a search thumbnail expires,
a site blocks hotlinking. The app then shows nothing — and the admin preview
still looks fine, because **the browser fetches it and the phone does not.**
Which is exactly the "the picture I set is not the picture I see" you described.

There is an upload button on each row now. The file goes to the platform's own
volume and the setting points at a path rather than an external URL, so the
picture chosen is the picture shown.

Pasting a URL still works — somebody with a good permanent link should not have
to download and re-upload it.

The preview resolves stored paths against the API, so what the admin sees is
fetched the same way the phone fetches it.

## 106. The upload worked; nothing could read it

`SaveAsync` returns a path under `/api/v1/admin/verification/files/...`, which
is right for a CNIC and wrong for this. An `img` tag cannot send a bearer token,
so **the portal's own preview could not load the file it had just uploaded** —
and the customer app, which is not an admin at all, had no chance.

The file was on disk the whole time.

A public route now serves exactly one folder, `vehicle-images`. Driver documents
stay where they are; nothing here opens them.

## 107. Why 6 km cost 1,600

The pricing is not broken. The **minimum fare** is.

A fare is `distance x rate + 2 PKR a minute`, floored at the minimum. At 30/km,
6 km comes to about 210 — so a minimum of 1,600 means every short trip is 1,600
and **the per-km rate does nothing at all**. Which is a reasonable choice for a
platform that will not send a car across town for 210 rupees, but it should be a
choice, not something discovered from a customer.

The admin page could not show it. Two number fields and no sense of what they
produce.

There are now two worked-example columns beside them — a 6 km trip and a 25 km
trip — recalculating as you type, each showing the fare and which of the two
numbers decided it. When the minimum is binding it says so, in amber, with the
metered figure beside it so the gap is visible.

The per-minute component is stated in the copy too. It was 2 PKR a minute,
hard-coded, appearing in no field and no explanation — so a fare could not be
reconciled with the settings even by someone doing the arithmetic.

### Not done, and worth saying

The per-minute rate is still hard-coded rather than a field. Making it settable
is a small change, but it belongs with a decision about whether it should vary
by vehicle — a Coster idling in traffic costs its driver more per minute than a
bike does — and that is a pricing question rather than a code one.

## 108. Why the admin's rates never reached the app

Your screenshots settled it. The app showed Car 1,600, Bike 250, Coster 7,500,
Hiace 4,500 — **exactly the built-in fallback figures**, for every vehicle. So
the rates were not being applied wrongly; they were not arriving at all.

`GetServiceRatesAsync` seeds its list from `service_vehicle_rates` and then
**overlays** the admin's pricing rules onto it. A category with no row in that
seeded table was dropped before any rule could touch it — so a rate set in the
portal reached nothing, and the client fell back to its own numbers.

A pricing rule is a statement that this vehicle is priced. That is enough to
include it, and the seeded table is no longer a gate on the portal: categories
with a rule and no base row are added from the rule itself.

Per-seat is left at zero for those rather than invented, so the client's own
share-out applies — the same thing it does for every other vehicle without a
seat price. Putting a number in front of a customer that no admin chose would be
worse than having none.

### A correction

Last round I said the per-minute rate was hard-coded. That is true of the
*client*, but `pricing_rules.per_minute_rate` exists and defaults to 2 — so it
is settable per rule in the database and simply not surfaced in the portal or
read by the app. The fix is smaller than I implied, and still not done.

## 109. The pickup address, again

The destination screen showed "MV62+76W, Rd B, Margalla View Block B D-17,
Islama…" — a Plus Code, three qualifiers and an ellipsis, in a row whose only
job is to confirm where the customer is standing.

The home screen already shortened it. The destination screen did not, because
the shortening was a private method on the home screen rather than a shared one.
One screen said "Unity Plaza" and the other said a Plus Code, for the same
point.

`shortPlaceName` is now shared, and the home screen's copy calls it.

## 110. The offer card, rebuilt

Layout A, as chosen: vehicle 104x104 on the left, the driver's face top right,
the fare large in the middle.

The fare is the biggest thing on the card because it is what the customer is
choosing between. The two photographs are how they recognise the car and the
person at the kerb — and the number plate sits **on** the vehicle photograph
rather than under it, because it is the one thing read off the car itself.

### Ratings and ride counts are off

You were right, and it is worth stating why plainly: **"★ 0.00" and "0 rides"
are worse than showing nothing.** They do not read as "we have no data yet",
they read as *a bad driver* — and on a new platform every driver carries them.

Five admin toggles: vehicle photograph, driver photograph, number plate, star
rating, rides completed. The last two start off and go on when the numbers mean
something, without a release.

They default to false even when the setting is missing, unlike the other three.
A missing answer should leave a rating hidden rather than show a zero nobody
asked for.

### Two photographs, two sources

**The vehicle** is the driver's own picture first, the category picture second,
an icon last. A customer at a kerb is looking for a particular car; a stock
photograph of a different car in the same class helps less than it appears to,
but it still beats a grey box.

**The driver** needed a new route. The one built earlier is scoped to a booking,
and at offer time there is no booking — so `GET /api/v1/offers/{id}/driver-photo`
is scoped to the offer instead: a customer may see the face of somebody who has
offered to drive *them*, and nobody else.

Initials when there is no photograph. A broken-image glyph where a face should
be is worse than a letter.

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
build label reads `rev 59`.
