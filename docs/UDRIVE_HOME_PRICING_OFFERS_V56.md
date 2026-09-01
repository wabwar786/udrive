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
