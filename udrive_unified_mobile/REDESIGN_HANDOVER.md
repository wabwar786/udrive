# UDrive Redesign — Delivery 1 & 2 (revision 42) · build label `rev 42`

Implements the Home & Tour Booking redesign handoff against the existing
`udrive_unified_mobile` app. Presentation layer only — no repository, model or
API contract was changed except where a new module required new endpoints
(Near Me, listed at the end).

**This code has not been compiled.** Run `flutter pub get` then
`flutter analyze` before building. Fix anything that surfaces and tell me — I'd
rather correct it than have you work around it.

## Revision 42 — choose a vehicle, name a price

Tapping the button on Home now opens `VehicleChoiceScreen`: route on the map,
the chosen vehicle with a fare stepper, the other vehicles priced below it, and
**Find offers**.

### Pricing

Fares come from the admin's own `service-rates`, applied to the **real road
distance** from the route already computed on Home — no second Directions call
for a line we already have. A time component is included so a short trip through
heavy traffic is not priced as though it were quick.

Rounded to the nearest 5 rupees. "PKR 1,217" implies a precision the estimate
does not have, and nobody negotiates in single rupees.

If the rates endpoint cannot be reached, built-in per-kilometre figures apply.
A customer with no prices cannot book at all, and a rough number they can adjust
beats an empty screen.

### The stepper

Steps scale with the fare: 50 rupees below PKR 3,000, 100 below 10,000, 500
above. A fixed step is a meaningful nudge on a city ride and meaningless on a
tour.

The caption states the trade-off rather than just the number — "12% below
recommended · may take longer" — because in a bidding model the customer is
choosing between price and waiting, and should be able to see which way they are
leaning. Tapping the figure allows typing it directly.

The floor is half the recommendation. An offer below that will not be answered,
and letting it be made only wastes the customer's time.

### Two things I did not build

**The auto-accept toggle** from the app you showed me. The API has no such flag,
and a switch that silently did nothing would be worse than its absence — the
customer would believe a ride had been agreed when it had not. Doing it properly
means a server-side rule (accept the first offer at or below this fare), which
is a real feature rather than a checkbox. Say the word and I will build it.

**Per-vehicle ETAs.** The screenshots show "3 min" per vehicle type. That needs
a Distance Matrix call per category per search, which is billed each time.
Worth doing, but it should be a deliberate cost decision rather than something
that appears on the bill unannounced.

### One bug avoided

The ride request needs `instantRide: true`. Without it the API rejects a pickup
set to now, because advance bookings must be at least 30 minutes ahead. I
checked the contract before shipping rather than after.

## Revision 41 — build fix, and the check that would have caught it

Removing the diagnostics overlay took the constructor parameter but left the
field:

```dart
final bool showDiagnostics;   // no initialiser, no constructor entry
```

A `final` field with no initialiser must be set by every constructor, so the
class stopped compiling.

The audit missed it because it looked at duplicate declarations and undeclared
calls, not at fields the constructor no longer sets. That check now exists, and
is narrow enough to be trustworthy: it flags `final X name;` with no `=` whose
name appears in no constructor. **I verified it by putting the exact bug back
and confirming it was caught**, then removing it again — rather than assuming a
new check works.

### Docker warning resolved

The build log carried:

```
SecretsUsedInArgOrEnv: Do not use ARG or ENV for sensitive data (ARG "MAPS_WEB_KEY")
```

Fair warning: `ARG` values are recorded in the image history, so a key passed
that way is readable by anyone who pulls the image. The declaration is gone —
the web build no longer uses a Google key at all. Tiles come from the API, which
holds the key server-side.

The `MAPS_WEB_KEY` variable can be deleted from the Railway service.

### Worth doing before the next deploy

The repository's GitHub Actions workflow runs `flutter analyze` as its first
job. Every build failure today — the duplicate class, the missing import, the
missing fields, this one — would have surfaced there in about a minute, instead
of after a Railway build. Push, let Actions run, deploy once it is green.

## Revision 40 — admin-managed map places

Your idea, and it is better than the hard-coded list it replaces: you can add
places yourself, without waiting on a build.

**Admin portal → Map places.** Add a name, coordinates, district, alternative
spellings and an optional note. It is searchable on the next search — no cache,
no redeploy.

Paste a Google Maps link or a coordinate pair and the two fields fill
themselves. Four link formats are handled, plus a plain `34.5822, 73.8992`.
Asking someone to pull two numbers out of a URL by hand is how transposed
coordinates happen. Short `maps.app.goo.gl` links cannot be resolved in the
browser, so those say so rather than failing quietly.

Coordinates are checked against Pakistan's bounds on save. Wide enough that a
legitimate pin just outside AJK is accepted, tight enough that swapped latitude
and longitude are caught before a driver is sent to the wrong continent.

Migration 031 creates the table and seeds it with the 25 places that were
hard-coded, so nothing is lost. `KashmirGazetteer.cs` is deleted — the list
lives in the database now.

### The limit worth being clear about

A pin makes a place **findable**. The route to it still comes from Google.

Where the last stretch is an unpaved track Google has never mapped, the route
will stop at the nearest mapped road. The customer and driver both see the right
destination and the right name; they agree the last part between themselves.

This is stated on the admin page too, so whoever adds places knows what a pin
does and does not do. Building around it — driver-drawn tracks, or offline
route hints — is possible, but it is a separate piece of work and should be
decided on its own merits rather than assumed.

## Revision 39 — polish, and Kashmir in search

The map works. This round is what you asked for on top of it.

### Dark map, styled at the source

The Map Tiles session now carries a style array, so Google returns dark tiles.
Darkening them in the client would have dimmed the route and markers along with
the basemap; styling at the session affects only the map itself.

Points of interest and transit labels are off — the map exists to show a route
and nearby vehicles, and every extra label competes with the markers that
matter.

### Layout

- Map grown to 52% of screen height, 320–560px.
- The bottom 56px fades into the sheet colour, and the sheet lost its rounded
  top and shadow. A corner radius there would have drawn the seam the fade
  exists to hide.
- The locate button floats on the map, bottom right. The strip it used to sit
  in is gone.
- The vehicle count chip moved onto the map beside it.
- The diagnostics overlay is removed, along with the state that fed it.

### Locate behaves as you expect

Tapping it zooms to your current location, full stop. It used to re-frame the
route when one existed — defensible, but not what the button says it does.

### Kashmir places in search

`KashmirGazetteer` holds 25 towns and valleys across all eight districts, with
alternative spellings, and they are matched **ahead of** Google's results.
Someone typing "kel" in this app means the village in Neelum, not a business
elsewhere with those letters; making them scroll for it would be perverse in an
app built for Kashmir.

Google still answers for cities, street addresses and businesses — the list only
guarantees a floor of local coverage where a general geocoder is thin.

It is deliberately short. Every entry is a place whose position is well
established; an approximate pin on a known valley is useful, an invented one for
a hamlet sends a driver somewhere wrong. Extend it as real journeys show what is
missing — it is a plain list in one file.

## Revision 37 — the polyline decoder, and why this took so long

The on-map readout ended it in one screenshot:

```
cam 8353745.0653, 1245613.4962   z5.0
pts 772  ready true
```

Latitude 8,353,745. The camera was fine, the tiles were fine, the map was fine.
**The polyline decoder was producing values that are not coordinates**, and the
camera was dutifully flying to them.

### The mechanism

The textbook polyline decoder uses `<<`, `&` and `~`. On the web, Dart ints
compile to JavaScript numbers and those operators work on **32 bits**:

```
31 << 30  →  -1073741824      (should be 33285996544)
1  << 31  →  -2147483648      (should be 2147483648)
```

On Android, Dart ints are 64-bit and the same code is correct. So the decoder
worked on mobile and produced garbage on web — which is the surface I was
testing on.

The decoder is now written with multiplication and division only. No bitwise
operators, so both platforms carry full precision. It is verified against
Google's documented test vector.

A range guard was added alongside: a decoded point outside ±90/±180 means the
stream has lost alignment and everything after it is meaningless, so decoding
stops there rather than handing a corrupt tail to the map.

### Why I did not find this sooner

I verified the decoder in Python, which has arbitrary-precision integers. It
matched Google's test vector perfectly and I treated that as proof. It proved
the algorithm, not the implementation — and the bug lived entirely in the
difference between the two number systems.

That mistake cost several rounds. Each screenshot showed a different symptom of
this one fault, and I proposed a different cause for each: gesture recognisers,
platform view stacking, a zoom floor, a dynamic height, a camera constraint. Four
of those were problems I had introduced myself while chasing it.

The readout that solved it should have been the first thing I built.

## Revision 34 — the same camera bug, on the other renderer

flutter_map was rendering — the attribution proved it — but showing flat grey
and cyan, which is open ocean at a very low zoom.

`_moveTo` called `_offlineController.move()` directly. **flutter_map throws if
that is called before the map reports itself ready**, so the camera move was
lost and the map stayed at whatever it started with. Exactly the fault fixed for
Google in revision 28, on the path I had not touched.

Camera moves for flutter_map are now queued and applied in `onMapReady`, with a
try/catch that re-queues rather than dropping if the controller refuses.

### Guards, so this class of failure is visible instead of silent

- `_moveTo` rejects non-finite coordinates and anything within 0.01° of (0, 0).
  Null island is in the Atlantic; a NaN or an unset coordinate reaching the
  camera is a bug, and the map should not quietly fly there.
- Zoom is clamped to the configured floor and 21, and falls back to the default
  if it arrives as NaN.
- flutter_map gets an explicit `cameraConstraint` covering the usable latitude
  range, so a drag cannot fling the view past the tile coverage.

### On repeating myself

This is the third camera fix. The first two each covered one renderer; the paths
were never made to share the guarantee. They do now — both queue, both clamp,
both refuse impossible input.

## Revision 33 — Google's map, without the platform view

You were right to push back. Dropping Google because `google_maps_flutter_web`
was unreliable threw away the wrong thing — the plugin was the problem, not
Google.

Web now uses **Google's Map Tiles API**. It returns the same cartography the
Maps SDK draws, as plain raster tiles, which flutter_map renders on Flutter's
own canvas. Google's map, no DOM element, none of the failures of the last two
days.

### Enable it first

```
Console → APIs & Services → Library → Map Tiles API → Enable
```

Then add **Map Tiles API** to the `udrive-server` key's API restrictions,
alongside Places, Geocoding and Routes.

### How it works

```
GET /api/v1/places/tiles/{z}/{x}/{y}
```

The server creates a Map Tiles session (Google issues these for two weeks and
expects reuse — one is cached and refreshed a day before it lapses), fetches the
tile, and returns it. A semaphore stops a cold start creating a dozen sessions
at once.

Proxied rather than fetched directly so the key stays on the server; a tile URL
built in the browser would carry the key in plain sight.

Tiles are cached for a week at both the API and the browser, so after the first
visit to an area nothing is re-fetched.

### If the proxy cannot serve

OpenStreetMap is used as a fallback — no key configured, Map Tiles not enabled,
quota reached. A usable map beats a blank one, and the two look different enough
that a misconfiguration will be obvious rather than silent.

### A bug avoided

`ApiConfig.uri()` percent-encodes the path, which would have turned
`{z}/{x}/{y}` into `%7Bz%7D/%7Bx%7D/%7By%7D` and left flutter_map with no
placeholders — the same class of fault as the `%3F` 404s. The tile template is
built by concatenation instead. I checked this before shipping rather than
after.

### Android and iOS

Unchanged. They use the native Google Maps SDK, which has never been part of
this problem.

## Revision 32 — tiles that cannot start requiring a key

CARTO now requires an API key for their basemaps. I picked them in revision 30
for the dark styling without checking whether that was still free — that was
careless, and it cost another round.

Web tiles now come from **OpenStreetMap's own tile server**: the one source that
needs no key and cannot begin needing one, because there is no vendor to change
their mind.

### Making light tiles dark

OSM tiles are light, so they are darkened in the app rather than sourced from a
dark provider. The filter is an invert combined with a 180° hue rotation — the
same pair CSS dark-map filters use. Inverting alone turns land grey and water
white; rotating the hue afterwards brings the colours back at dark luminance, so
roads stay pale against dark land and water stays blue.

The matrix was computed rather than guessed, by multiplying the two standard
matrices together. It is applied through `tileBuilder`, per tile, so markers,
the route line and the pickup pin keep their true colours.

### Traffic

OSM's usage policy covers development and modest production traffic. If web
traffic ever outgrows it, a paid tile provider or Google's Map Tiles API drops
into this one widget without touching anything else.

## Revision 31 — removing what web no longer needs

The "API key required" overlay came from `web/index.html`, which was still
loading the Google Maps JavaScript API and still carrying the `gm_authFailure`
diagnostic I added while debugging. Web renders with flutter_map now, so that
script downloaded on every visit and did nothing except produce an error banner
over a map that was never Google's.

Removed from the web build:

- the Maps JS `<script>` tag
- the `gm_authFailure` handler and the console-error mirror
- the Dockerfile step that injected `MAPS_WEB_KEY` into `index.html`

The `MAPS_WEB_KEY` variable on Railway can be deleted; nothing reads it. The
`ARG` stays in the Dockerfile only so an existing build variable does not cause
an error.

Android and iOS are untouched — they use the native SDK and never read
`index.html`.

## Revision 30 — web stops using Google Maps

I have chased the map problem through seven explanations and each fix moved the
symptom rather than removing it: a zoom floor I added, PointerInterceptor
stacking I added, a dynamic height I added, a discarded camera move, a cache
pinning old builds. Three of those faults were mine. The rest were
`google_maps_flutter_web`.

That plugin renders the map as a DOM element composited beside Flutter's canvas.
Blank tiles, a tile grid showing through, a route drawn as straight segments,
styling that applied on one load and not the next — all of it lives in that
seam.

**Web now renders with `flutter_map` instead.** Everything is drawn on Flutter's
own canvas: no platform view, no separate compositing layer, and a polyline that
cannot do anything other than follow the points it is handed.

```dart
bool get _useGoogle => _online && !kIsWeb;
```

Android and iOS keep Google Maps. There the SDK is native and none of these
problems exist.

### What changes on web

- Tiles come from CARTO's dark basemap (OpenStreetMap data), which matches the
  app palette. Free for reasonable use.
- Attribution for OpenStreetMap and CARTO is now drawn — Google supplied its
  own, flutter_map does not, and both licences require it.
- The route keeps its dark border and round caps, so it reads the same.

### The trade-off, stated plainly

Web loses Google's cartography: less detail in Pakistan, and place labels that
are sometimes sparser. It gains a map that works.

Web is the testing surface. Customers will be on Android, where Google Maps is
still what they see. If web ever becomes a product surface, Google's Map Tiles
API can feed flutter_map raster tiles — same architecture, Google's imagery,
no platform view.

**No new Google API is needed for any of this.**

## Revision 29 — why a deployed build kept showing rev 28

`nginx.conf` cached every `.js` file for seven days as `immutable`:

```
location ~* \.(js|css|png|…)$ {
  expires 7d;
  add_header Cache-Control "public, max-age=604800, immutable";
}
```

Flutter emits the same filenames on every build — `main.dart.js` is always
`main.dart.js`. `immutable` tells the browser not to even ask whether it
changed. So a deploy replaced the file on the server and the browser carried on
running the old one. That is how a build labelled `rev 28` survived two
releases of `rev 29`, and it means some of today's testing was against code that
had already been replaced.

`main.dart.js`, `flutter.js`, `flutter_bootstrap.js` and `version.json` now use
`no-cache, must-revalidate`. Nginx still answers 304 when nothing changed, so
the cost is a conditional request, not a re-download. Content-hashed assets
(canvaskit, fonts, images) keep the seven-day immutable cache — their filenames
change when their contents do.

**For the deploy after this one**, force a refresh once so the browser drops the
pinned copy: Ctrl+Shift+R on Windows, Cmd+Shift+R on Mac. After that the header
handles it.

### Project cleanup

- 99 patch notes moved from the repository root into `docs/archive/`. Moved, not
  deleted — they are your history. Eleven durable documents stay at the root.
- `patch_payload/` removed: four files, all duplicates of live source.
- `tool/validate_project.py` removed, superseded by `tool/audit_structure.py`.

## Revision 28 — the camera move that was thrown away

The dark map in your screenshot confirmed a recent build was live, so the
straight line had to be something else. It was.

`_moveTo` began with:

```dart
if (!_googleController.isCompleted) return;
```

A camera move requested before the map finished creating was **silently
discarded**. A route arrives in a few hundred milliseconds; the map takes
longer. So `fitBounds` ran, found no controller, and gave up — leaving the
camera at its initial position, which is the pickup at zoom 16.2. Street level.

At street level a 21 km route shows one near-horizontal slice of an east–west
road. Nothing was wrong with the line: I decoded the polyline you sent and it
spans 8 km of latitude and 18 km of longitude across 538 points. It was never
straight; you were looking at 400 metres of it.

Pending camera moves are now stored and applied in `onMapCreated`.

A second cause, fixed alongside: **"Use my location" re-frames the route** when
one exists, instead of zooming to the customer at 16.2. Pressing it while
planning a trip should correct the pickup, not discard the view of the journey.

## Verifying which build is live

Open **Notifications** (the bell). The build label sits at the bottom of the
panel. If it does not say `rev 28`, the deployed app predates these fixes and
any conclusion drawn from testing it is about old code.

Two visual tells that give the same answer instantly:

- **A pale grey map** means the build is older than rev 27 — the dark style
  arrived with it.
- **Blank map tiles** mean older than rev 26.

### The API is confirmed correct

The `/places/directions` response you sent decodes to **538 points** with a path
length of 21.48 km against the 21.475 km the API reported — a winding ratio of
1.10 over the straight line. That is real road geometry. `HIGH_QUALITY` is
working and the backend is deployed.

So a straight-looking line on screen is now a client-side or deployment
question, not an API one.

## Revision 27 — the route line, and a dark map

### Why the line looked straight

Routes API returns an **OVERVIEW** polyline by default — heavily simplified, so
a road that winds through hills is drawn as a near-straight line. That is what
made it look like the route ignored the roads.

The request now asks for `polylineQuality: HIGH_QUALITY`, which follows the
actual carriageway.

This was not the decoder. I had verified that against Google's own documented
test vector and it matched exactly — the data arriving was simply low-detail.

### Dark map

A default Google map is pale grey, which against a near-black app looks like a
window into a different product, and makes a green route hard to pick out.

`MapStyles.dark` is built from the app's own surfaces. Points of interest and
transit labels are off: the map exists to show a route and nearby vehicles, and
every extra label competes with the markers that matter.

Applied through the `style` parameter on the widget rather than
`setMapStyle`, which is deprecated — and setting it at construction avoids the
default style flashing before the dark one applies.

### A route you can actually see

The chosen route is drawn twice: a dark casing at width 11 underneath, brand
green at width 7 on top. A single stroke disappears against roads of a similar
tone; the casing keeps it legible wherever it runs. Round caps and joints, so
bends do not show mitred corners.

Alternatives stay behind at width 5 in muted grey — options, not competitors.

## Revision 26 — the grey tiles

Routing is confirmed working: "40 min via GT Rd/Peshawar Rd … and Srinagar Hwy",
with an alternative offered. The horizontal route line is correct too —
Islamabad to Rawalpindi runs roughly east–west.

What remained was grey tiles, and the cause was a change I made in revision 24:
the map grew from 44% to 50% of screen height **when a route appeared**.

On web the map is a DOM element. Resizing it leaves Google holding tiles for the
old viewport and rendering nothing for the rest — grey, with the route drawn
over it, appearing at exactly the moment a route arrives.

Three changes:

- **The map height is now constant** (46%, clamped 280–520px). It never changes
  with content.
- **The active-trip banner moved into the sheet.** It used to sit between the
  map and the sheet, so it shifted the map every time a trip started or ended.
  Inside the scroll view its growth costs the map nothing.
- **`UdMap` detects a resize and recovers.** A `LayoutBuilder` compares the
  constraints between builds; on a change it nudges the camera by 0.0001 zoom
  and back after the frame commits, which forces a fresh tile fetch. Orientation
  changes and browser window drags are covered by the same path.

Also shortened the alternative-route chips: Google's summary can be a whole
chain of roads, and the full string is unreadable in a chip. The first road name
is enough to tell two routes apart.

## Revision 25 — the 404s were mine

The console log showed the cause plainly:

```
/api/v1/catalog/vehicles/nearby%3Flat=34.37&lng=73.4711&radiusKm=5   404
                             ^^^
```

`%3F` is an encoded question mark. The query string had been folded into the
**path**, so the server saw a route ending in `nearby?lat=…` and correctly said
it did not exist. The endpoint was deployed and fine the whole time.

`ApiConfig.uri()` builds its URL with `base.replace(path: …)`, which
percent-encodes everything it is handed. Passing `'/endpoint?a=1'` as the path
therefore produced `/endpoint%3Fa=1`.

Fixed in `ApiConfig.uri()` rather than at the call sites: it now splits any
inline query string off the path and merges it with the parameter map. That
repairs four callers at once, including `hotel_repository`, which had the same
bug before I started — I copied the pattern from it.

Verified against every affected URL; none now contain `%3F`.

### What this explains

- Nearby vehicles never appeared — the request never reached the endpoint
- `catalog/destinations` 404 — same encoding, not a broken controller
- Business search on Near Me — same
- Hotel search — same, and pre-existing

It does not explain the blank map, which was the zoom and camera work in
revisions 23 and 24. Two unrelated faults overlapping made both look worse than
they were.

### Also from the log

Location is now resolving: requests carry `lat=33.6605&lng=72.8509` rather than
the Muzaffarabad fallback. The browser permission is granted.

## Revision 24 — camera computed, bigger map, both ends editable

### The blank map, and the "wrong" route line

Both came from the same place.

`newLatLngBounds` was still being used. It has to be handed a viewport it can
satisfy; when it cannot — because of a zoom floor, padding larger than the map,
or web quirks — it leaves the camera in a state that renders no tiles. Lowering
the floor in revision 23 was not enough.

The camera is now computed directly from the span and the widget's own size:
find the largest zoom at which the route still fits both axes, with a cosine
correction for Mercator stretch, then move there. Deterministic, and identical
on both renderers.

Verified against real journeys, at a 392x340 map:

```
Islamabad → Murree    50 km    zoom 10.0
Islamabad → Dhirkot  145 km    zoom  9.1
Muzaffarabad → Kel   150 km    zoom  8.7
Two points 300 m apart         zoom 15.8
```

The route line looked like it ignored roads because the map was at street zoom
on a 50 km route — any route looks straight when you are that far in. The
polyline itself is fine: I ran the decoder against Google's own documented test
vector and it matched exactly. Framing the route makes the shape visible.

### Bigger map

44% of screen height when idle, 50% once a route is drawn, clamped 280–520px. A
route on the map is carrying the most information, so it gets the most room.

### Both ends editable from one screen

The search screen opened on one end and the other was dead text. Now either row
switches the editor, and `PlacePickResult` reports which end was actually
chosen — the caller can no longer assume it got back what it asked for.

## Revision 23 — the blank map, actually solved

The last screenshot told a different story from the earlier ones: Google's
branding, "Map data ©2026" and "Terms" were all visible. The map was mounted and
initialised — only the tiles were missing. That is not a detached platform view.

**The cause was my own zoom floor.** I set `minZoom: 11` in revision 17 to stop
the map opening at continent scale. At zoom 11 a 380px-tall map covers about
29 km. The Islamabad → Dhirkot route is 145 km, needing roughly zoom 8. Google
could not fit the bounds without breaking the floor, and the camera ended up in
a state that rendered no tiles.

That also explains the earlier "white after selecting a destination": it always
happened at the moment `fitBounds` ran on a route longer than 29 km.

The floor is now 5 — low enough for any journey in Kashmir, high enough to catch
something absurd. The opening-scale problem it was meant to solve is already
fixed properly, by centring on the GPS fix and by not fitting bounds for two
points a few metres apart.

Two guards added alongside:

- Fit padding is clamped to a fifth of the map's shorter side. Padding larger
  than the viewport leaves Google no room to place a camera.
- If `newLatLngBounds` fails for any reason, the camera falls back to centring
  at zoom 10 rather than being left wherever it broke.

Zoom coverage for reference, at a 380px map height:

```
zoom  8   232 km
zoom  9   116 km
zoom 10    58 km
zoom 11    29 km   ← the old floor
zoom 13     7 km
```

## Revision 22 — the map going white, properly

My previous explanation was wrong. The real cause is platform-view stacking on
web.

Every `PointerInterceptor` is itself a platform view. I had three of them
stacked over the Google Map, which is also a platform view. Picking a
destination changes the widget tree — the pin disappears, the chip changes, the
route summary appears — the platform view slots get reordered, and the map's DOM
element is detached. What is left is a blank white div.

That was also why the interceptors were there: on web, Flutter widgets drawn
over a platform view do not reliably receive taps, so the header buttons needed
them. Both problems come from the same root — putting things on top of the map.

**The map no longer has anything interactive on it.** The layout is a Column:

```
header      logo · language · driver mode · notifications
map         210–380px, only the pickup pin over it (IgnorePointer)
chip row    "6 cars within 5 km" + locate button
sheet       fills the rest, scrolls internally
```

Removed as a result: the `pointer_interceptor` dependency, all four
interceptors, and the `gestureRecognizers` set added in revision 21 — with
nothing overlapping, the map cannot steal a drag from anything.

The full-bleed look is gone. It could not be made reliable on web, and a map
that vanishes is worse than a map that does not bleed behind a panel.

**Run `flutter pub get`** — a dependency was removed.

## Revision 21 — the map going white

`gestureRecognizers` was built inline in `_buildGoogle()`, so every rebuild
allocated a new `Set` containing new `Factory` instances. `google_maps_flutter`
reads that as a configuration change and tears down the platform view. On web a
recreated view renders as a blank white div until it reinitialises — which is
why it went white exactly when a route arrived, since that is when rebuilds come
thick and fast.

The set is now a `static final` built once, with a `const` empty set for the
non-interactive case, and the map carries a stable `ValueKey`.

Two supporting changes:

- The sheet cap moved from 62% of screen height to 55%, clamped between 320 and
  560px. With a route, booking type and CTA all present the sheet was hitting
  its cap and leaving the map a sliver. The sheet scrolls internally, so capping
  it costs nothing.
- The dark backdrop is now painted inside the stack as well as behind it, so if
  the map area is ever slow or fails it reads as part of the app rather than a
  white hole.

Routing itself is confirmed working — "41 min · 34 km via Srinagar Hwy and
Islamabad Expy" came back from the Routes API.

## Revision 20 — duplicate class fix, and a real audit

`_LocationErrorBanner` was declared three times. My insert anchored on the
comment `/// A destination used before…`, which by then appeared three times in
the file, and a plain string replace hit all three.

This is the third build I have broken the same way: an anchored insert or an
index-based cut duplicating code. The audit I had been running only checked for
duplicate members *inside* a class, so a duplicated top-level class walked
straight past it.

The audit now lives in `tool/audit_structure.py` and checks:

- duplicate top-level declarations (class, enum, mixin, extension)
- duplicate members inside a class
- `if` / `for` / `while` with an emptied body
- private methods called but never declared
- theme token members that do not resolve (`AppProduct.rideFrom` after a rename)
- relative imports pointing at files that do not exist
- brace balance

Each of those checks exists because that exact mistake reached a build. I
verified the new one fires by deliberately duplicating a class and confirming it
was caught.

Run it yourself any time:

```bash
cd udrive_unified_mobile && python3 tool/audit_structure.py
```

It is not a substitute for `flutter analyze` — it catches structural damage from
editing, not type errors.

## Revision 19 — pickup fix and build fix

### Why pickup showed a Kashmir address

`_onMapSettled` ran on the **first** camera idle. That idle happens at the
fallback centre — Muzaffarabad — before GPS has resolved, so the pin
reverse-geocoded the fallback and wrote a Kashmir address into the pickup field.
The real location arrived a moment later, but the label was already written.

The pin now only claims the pickup after `_userMovedMap` is set, which happens
in the drag handler. Camera moves the app makes itself — opening, centring on
GPS, framing a route — never rewrite the pickup.

### Location failures are no longer silent

`_setPickupFailure` used to put its message *into* the pickup field, so "Allow
location to detect pickup" sat there looking like an address someone might
accept without reading.

Now the field is left genuinely empty with a placeholder, and the reason appears
as a banner with a **Retry** and a note that a pickup can be set by hand. A dead
end here blocks the entire booking, and location failures on the web are common
and often temporary.

Messages also say what to do: "Location permission is blocked. Allow it in your
browser or device settings." rather than "Allow location from app settings",
which is wrong on web.

### Build fix

`_CentrePin` still referenced `AppProduct.rideFrom` and `rideMid` — gradient
stops I removed when switching to the flat palette. My token audit only checked
that classes existed, not that every member did. It now resolves every
`AppProduct` / `AppTint` / `AppText` / `AppColors` reference against its
definition.

## Revision 18 — colour-coded cards, both ends editable

### Design A, not the gradient version

Swapped the gradients for flat tinted surfaces. Each product owns a hue:

```
Ride    #1F3A1B surface, #A6FF2E accent
Tour    #3A2A12 surface, #FFB84D accent
Hotel   #12293D surface, #5AA9FF accent
```

Unselected cards drop to the neutral surface with muted ink, so the chosen
product is unmistakable rather than one of three bright boxes competing with
each other and with the map behind.

Ride keeps the tall card on the left with its nearby count in the subtitle;
Tour and Hotel stack beside it. **Seats is not a card** — it is how you buy a
ride, not a separate product, so it stays in the booking-type row once a
destination is set.

### Both ends always editable

The route rows used to appear only after a destination was chosen, which meant
a wrong pickup could not be corrected — exactly when it matters most. From and
To are now always visible and always tappable.

The separate search bar is gone with them. It and the To row did the same job,
and two controls for one action is a decision the customer should not have to
make.

### Pickup defaults to the current location

Already the behaviour, but two things made it unreliable:

- The field read "Detecting current address…" and could sit there looking
  broken. It now says "Finding your location…", which describes what is
  happening.
- The opening camera move fires a map-idle event, and the centre pin would
  immediately reverse-geocode the same point it had just resolved — one wasted
  billed request, and a label that could differ from the GPS one. The pin's
  distance guard is now seeded with the fix, so the first settle is ignored.

## Revision 17 — centre pin, zoom fix, bold colour

### Why the map showed half of Central Asia

`_loadLocation` stopped moving the camera. I removed that line in an earlier
refactor and never put it back, so the map sat at its initial position and any
`fitBounds` fallback swung it out to continent scale. At that zoom Google draws
a terrain atlas rather than streets, which is why it looked like the wrong map
style — it was the right style at the wrong scale.

Three fixes:

- The camera moves to the customer on the first GPS fix, at zoom 16.2
- `UdMap` takes a `minZoom`; Home passes 11, so the map can never zoom out past
  street level again
- `fitBounds` centres instead of fitting when the two points are under ~400 m
  apart, because fitting a tiny bounds with padding produces absurd zooms

### Centre pickup pin

The pin is fixed at the centre of the map and the map moves beneath it. Lifting
your finger reverse-geocodes whatever is underneath and makes it the pickup,
then refreshes the nearby vehicles, which are measured from the pickup.

Details that matter:

- While dragging, the pin lifts and its label hides. The address underneath is
  unknown until the map settles, and showing a stale one would be a lie.
- A settle that moved less than about 40 m is ignored. Every lookup is billed,
  and a few metres is not a new pickup.
- The pin only works while no destination is set. Once a route is drawn, moving
  the map must not silently rewrite where the trip starts.
- `IgnorePointer` on the pin, so the drag underneath reaches the map.

### Colour

Each product owns a hue, in `AppProduct`:

```
Ride    lime → deep green    (brand)
Seats   violet
Tour    orange
Hotel   cyan
```

Full gradients, not tints, so four products read as four things. Ride keeps the
full-width hero with a live nearby count; the others sit in a scrolling rail, so
adding a service later is one more card rather than a redesign.

The brand green moved from `#8ED12B` to `#A6FF2E`. The old value was mixed for
light surfaces and sat flat against near-black. Backgrounds went a step deeper
to match.

**Worth checking on a real phone.** Four saturated gradients on one screen looks
striking on a monitor and may read as busy outdoors. Dialling back is one value
per card.

### Still your side: the 403

`"error": { "code": 403 }` is `PERMISSION_DENIED` — Routes API is enabled on the
project but not allowed on the key. Add it under the key's API restrictions.
Changing restrictions does not change the key's value, so nothing needs
re-entering in the admin portal.

## Revision 16 — search-first home, and two fixes

### Home is now search-first

The sheet asks one question instead of four. Before a destination exists it
shows: a large search button, three service cards, and recent destinations.
Once a destination is set it becomes the trip panel — route summary, booking
type, seats, and the action.

**Service cards are weighted, not equal.** Ride gets a 148px card with oversized
artwork bleeding off the corner; Tour and Hotel stack beside it at half height.
Equal tiles would make the common case as slow as the rare one — most customers
want a car, and they should not have to hunt for it.

Selection state is a filled icon chip, a green border and brighter artwork, so
which service is active is readable at a glance rather than from a subtle tint.

**Recent destinations** come from `RecentPlacesStore`, which deliberately shares
the storage key the route flow screen already writes to. Two separate histories
would look like the app had forgotten where the customer went. Only places with
coordinates are stored — a name that cannot be resolved again is no use as a
shortcut.

### Map moving behind the sheet — the real fix

Revision 13's `gestureRecognizers` only covers Android and iOS. On web the
Google Map is a DOM element in its own layer, so pointer events reach it
regardless of what Flutter draws on top.

Added the `pointer_interceptor` package, which exists for exactly this, and
wrapped the sheet, the header chrome and the status chips. **Run
`flutter pub get`** — this is a new dependency.

### Route errors now say what went wrong

"Could not work out the route. Check your connection." sent you to debug the
wrong thing. The proxy already captured Google's own message; it now travels
through to the UI in a `detail` line. `REQUEST_DENIED`, `Routes API has not been
used in project…` and referrer errors each point straight at the fix.

### Removed

`ServiceSelector` and `AppearanceRepository` are gone — the new cards replaced
one, and the hero-image settings the other reads have been unused since Home
became a map.

## Revision 15 — pickup is editable, Routes API

### Pickup was not blocked — the search screen was one-sided

Tapping the From row already opened the search screen. The screen itself was
hardcoded for destination editing: From was always rendered as static text and
the input was always labelled "To". So editing pickup put you in a field
labelled To, which looked like pickup could not be changed.

`PlaceSearchScreen` now takes `editingPickup`. Whichever end is being edited
becomes the live input; the other stays visible as read-only text so the route
being built is always readable. Both ends now also carry their current value
into the screen, and the input has a clear button.

Editing pickup additionally offers **"Use my current location"** as the first
option, which re-reads GPS rather than trusting a stored label, then refreshes
both the nearby vehicles and the route — nearby is measured from the pickup, so
moving it has to move both.

### Routes API, not Directions

Google moved Directions API and Distance Matrix API to legacy on 1 March 2025.
Projects that had not already enabled them cannot enable them at all, which is
why neither appeared in the console. The proxy now calls
`routes.googleapis.com/directions/v2:computeRoutes`.

Routes is a POST with a JSON body and a required `X-Goog-FieldMask`. The mask
is a billing control as much as a correctness one — Google charges by which
fields you request, so the proxy asks only for duration, distance, polyline and
description. Duration comes back as a protobuf string like `"1234s"` and is
parsed accordingly.

Errors now return Google's own message in a `detail` field, so a failure shows
its cause in the API log instead of a bare status code.

## Revision 14 — route, distance and travel time

### Enable Routes API first

This needs one more Google API: **Routes API**.

Not Directions — Google moved Directions API and Distance Matrix API to legacy
status on 1 March 2025. Projects that had already enabled them keep working, but
a project that had not cannot enable them at all. A new project has to use
Routes, which merges both.

(Your enabled list includes Distance Matrix API, which is also legacy. It may
not work either.)

Console → APIs & Services → enable **Routes API**, and add it to the
`udrive-server` key's API restrictions alongside Places and Geocoding.

Routes is a POST with a JSON body and a required `X-Goog-FieldMask`. The mask
matters for cost as well as correctness — Google bills by which fields you ask
for, so the proxy requests only duration, distance, polyline and description.

### What happens after picking a destination

1. `GET /api/v1/places/directions` through the same proxy (key stays server-side)
2. The route is drawn on the map in brand green; alternatives sit behind in grey
3. The camera zooms out to fit the whole trip with padding
4. A summary appears above the button: **"45 min · 23 km — via Neelum Road"**
5. If Google returned alternatives, one-line chips let the customer switch, each
   showing its road and how much slower it is

`departure_time=now` is sent, so `duration_in_traffic` comes back and the
estimate reflects current conditions.

### No straight-line fallback, deliberately

When Directions cannot answer, the summary says so — it does not fall back to
straight-line distance. The road from Muzaffarabad to Kel is roughly three times
the direct line. A straight-line figure would misprice the fare and mislead the
customer about when they would arrive, which is worse than showing nothing.

The three failure cases each get their own message: no key configured, no
drivable route, or a network problem.

### Cost

Fetched on destination change, not on a timer — a route between two fixed points
does not move. The response is cached for 120 seconds server-side.

### Also

`UdMapController.fitBounds()` added, working on both renderers. Polyline
decoding is implemented inline (about twenty lines) rather than adding a package.
The 5 km search ring now hides once a route is drawn, since it only clutters the
trip.

## Revision 13 — Tour as a service, seat rules, gesture fix

### Tour moved to the service row

`HomeService` gained `tour`, so the row is now Coaster/Bus · Car · Bike · Hotel
· Tour. The booking-type row below is just **Per seat | Whole vehicle** —
`TravelMode` is gone.

Tour is filtered on a vehicle property, not a category: migration 030 adds
`vehicles.available_for_tour`, defaulting to **false**. A driver opts in.
Defaulting everyone to true would put drivers on multi-day mountain trips they
never agreed to.

### Seat rules

Per seat is offered only when a nearby vehicle actually has seats to share —
more than 5, and a driver who allows per-seat. Otherwise the row collapses to a
single line explaining why.

Enforced again in `BookingService.SelectDriverOfferAsync`, which reads the
vehicle's own capacity and mode before writing the booking. A client can be out
of date or bypassed, so UI-only validation is not validation.

Migration 030 also resets `booking_mode` to `WholeVehicle` for any existing
vehicle seating 5 or fewer.

### Map moving behind the sheet

Two fixes, because the cause is two-sided:

1. `GoogleMap` now declares its `gestureRecognizers`. As a platform view it was
   winning the gesture arena for drags that began on Flutter widgets above it.
2. The sheet sits in an opaque `GestureDetector` with drag handlers attached, so
   it claims the pointer before the platform view sees it.

Map pan and zoom still work when the gesture starts on the visible map.

### Naming collision found

`data/models.dart` already declared `enum BookingType { perSeat, wholeVehicle }`
— identical to the one I was about to add. Two enums with the same name would
collide in any file importing both. The new file now re-exports the existing
enum and only adds presentation helpers. Renamed `travel_mode.dart` to
`booking_options.dart` to match what it holds.

### Also

The plain green square top-left is now the real `UDriveMark` logo.

## Revision 12 — layout now matches the mockup

The shipped screen did not match the design I showed, because I changed the
Home layout but never changed `ServiceSelector` — it was still drawing four
bordered blocks with illustrations. Four cards plus a mode row plus addresses
pushed everything apart and left the map as a strip.

Two changes:

**Service pills.** `ServiceSelector` is now a horizontal pill row. One control
instead of four cards, and the map stays visible behind the sheet.

**Full-bleed map.** Home is a `Stack`: the map fills the screen, the sheet rides
on top with a 26px rounded top and is capped at 62% of screen height so a slice
of map is always showing. Header chrome, the vehicle-count chip, the locate
button and the active-trip banner all float over the map. The CTA moved inside
the sheet rather than being a separate bar, and the "Invite a friend" row was
dropped from Home — it is in the drawer already and was only adding height.

### Search is working — it needs the Google key

The empty result for "Bank Colony Dhamial" is not a bug in the proxy. The
request went out, came back, and the fallback UI rendered. The proxy is
answering from OpenStreetMap, and OSM simply does not have most Pakistani
colony, sector and street names.

Google does. Set `places.google.apiKey` in the admin portal under **Maps and
artwork** and the same search starts resolving street addresses and house
numbers. Nothing else needs to change — no rebuild, no redeploy.

### Structural audit

The checks from revision 11 now run over every file: duplicate class members,
emptied control bodies, undeclared private calls, brace balance. All clean.
The two remaining flags are known false positives — a generic `_list<T>` the
regex cannot see, and a brace inside a string literal in
`customer_operations_screen.dart` that is present in the original upload.

## Revision 11 — duplicate code fix

My revision 10 edit script removed blocks by index in a loop, and the ranges
overlapped. Each pass re-cut an already-shifted file, which left four copies of
`_refreshNearby`, `_visibleVehicles`, `_showVehicleSheet` and
`_applyConnectivity`, plus one `if` statement whose body had been deleted.

Removed the three extra copies and repaired the statement.

To stop this recurring, I now run three structural checks after every edit
instead of only counting braces:

- class-scoped duplicate member declarations
- `if` / `for` / `while` with an emptied body, and dangling assignments
- every called private method resolves to a declaration

All three are clean, and the checks confirmed the one remaining brace mismatch
(`customer_operations_screen.dart`) is present in the original upload too — a
brace inside a string literal, not a real error.

Also confirmed from the build log: `Maps web key injected.` — the Railway
Dockerfile wiring works.

## Revision 10 — search fixed, three travel modes, blue dot

### Why address search never worked on the web

`place_search_service.dart` called Nominatim directly with a `User-Agent`
header. **Browsers forbid that header** — the request dies in CORS preflight, so
search silently returned nothing on every deployed build. It worked on mobile,
which is why it looked intermittent.

Fixed by moving all geocoding server-side:

```
POST-free GET /api/v1/places/autocomplete?q=&lat=&lng=
              /api/v1/places/reverse?lat=&lng=
```

`PlacesController` calls Google Places Text Search when a key is configured, and
OpenStreetMap when it is not. Three wins at once: the Google key never reaches
a client, an admin can rotate it without a rebuild, and the server *can* send
the `User-Agent` that Nominatim requires.

Text Search rather than Autocomplete is deliberate — it returns coordinates in
the same response, so one call replaces predict-then-fetch-details and costs
about half.

**Run migration 029.** It seeds `places.google.apiKey` with `is_public = false`.
That flag must stay false; making it public would expose the key through
`/api/v1/settings/public`, defeating the whole point.

Set the key in the admin portal under **Maps and artwork**.

### Three travel modes

`TravelMode { perSeat, wholeVehicle, tour }` now sits on one row above the
addresses, because these are three different products rather than three
settings:

| Mode | Panel | API |
| --- | --- | --- |
| Per seat | seat stepper | `bookingType: PerSeat`, city service |
| Whole vehicle | nothing extra | `bookingType: WholeVehicle`, private service |
| Tour | destination chips, days, passengers, whole-trip offer, advance | `WholeVehicle` + advance |

Tour is no longer a toggle. It has Kashmir destination chips (Neelum, Arang Kel,
Banjosa, Sharda, Pir Chinasi, Rawalakot, Toli Peer), a **day count** instead of a
single time, a whole-trip price, and the advance shown as a real figure —
"20% advance (PKR 4,800)" — rather than a percentage the customer has to work out.

The vehicle's own `bookingMode`, set by the driver, still narrows this on the
next screen: a whole-vehicle-only car never appears under per seat.

### Full-screen search

`place_search_screen.dart` replaces the inline dropdown. Both route ends stay
visible while typing, results get the whole screen, and two escape hatches sit
at the bottom: **Use "<what you typed>"** and **Choose on map** — plenty of
villages in Neelum and Bagh are in no geocoder, and those customers must still
be able to book.

### Blue dot

`myLocationEnabled` gives Google's own blue dot. The offline renderer had none,
so `UdMap` now draws a matching dot and accuracy halo for flutter_map. Both
paths look the same.

## Revision 9 — build fix

`customer_home_screen.dart` used `allowsPerSeat` / `allowsWholeVehicle` without
importing `core/booking/vehicle_booking_mode.dart`.

Dart resolves the *type* through a transitive import, which is why the error
message could name `VehicleBookingMode` — but **extension members are only in
scope when their defining library is imported directly**. That is why four
getters failed on a type the compiler could clearly see.

Fixed by adding the import. I also scanned every file for the same class of
mistake against the uniquely-named extension members
(`allowsPerSeat`, `allowsWholeVehicle`, `vehicleFilterKey`, `heroTitle`,
`heroSubtitle`, `isVehicle`) — nothing else is missing.

Dependency resolution succeeded on Railway, so the versions added in earlier
revisions are confirmed good: `google_maps_flutter 2.18.0`,
`share_plus 11.1.0`, `google_maps_flutter_web 0.6.3`.

## Revision 8 — live vehicles on the home map

### What it does

Home's hero is now a Google map showing every online vehicle of the selected
service inside a 5 km ring. Switching Car → Bike changes the markers instantly
(one fetch covers all categories, filtering happens client-side).

### Backend

```
GET /api/v1/catalog/vehicles/nearby?lat=&lng=&radiusKm=5&category=Car
```

Runs `ST_DWithin` against `udrive.driver_presence_locations`, which already has
a GIST index and is already written every 15 seconds by the driver app. No new
table, no new migration.

Filters: driver `Approved`, user `Approved`, vehicle `Verified`, `is_online`,
and presence newer than 90 seconds. That last one matters — a driver who closed
the app ten minutes ago must not show as available, or the customer books
something that was never there.

**Privacy, as approved:** the response carries no driver name, phone, plate or
driver id, and coordinates are rounded to 3 decimals (~100 m). The endpoint is
unauthenticated because the home map loads before sign-in, so there must be
nothing there worth harvesting. Identity is released only on a confirmed
booking, through the existing endpoints.

ETA is a straight-line estimate × 1.6 (mountain roads) at 25 km/h. It is a hint
on a pin, not a promise — a real figure needs the Distance Matrix API.

### Mobile

- `UdMap` gained `UdCircle` — renders as `gmap.Circle` online, `CircleMarker`
  offline, so the ring works in both modes.
- Polling every 10 s (`AppConfig.nearbyVehiclesPoll`). Google does not bill for
  this — Maps charges per map *load*, not per marker update.
- Tapping a marker opens a sheet with type, distance, ETA, rating and how the
  vehicle can be booked. Nothing identifying.
- Count chip over the map: "6 cars within 5 km", or "No cars nearby right now",
  or "Offline — vehicles unavailable".

### Map-load cost: IndexedStack

`MainShell` rebuilt the whole screen on every tab change, so returning to Home
would have instantiated a new map — and Google bills each instantiation. The
four bottom-nav destinations now live in an `IndexedStack` and stay mounted.

`TickerMode` marks the hidden ones inactive, and `_refreshNearby` checks
`TickerMode.of(context)` before fetching, so a Home tab sitting in the
background stops polling. (TickerMode pauses animations, not timers — the
explicit check is what actually stops the requests.)

### Admin hero images are now unused

The `home.hero.*.imageUrl` settings, `AppearanceRepository` and the admin
"Home screen artwork" page were built when Home showed a large illustration.
Home is a map now, so nothing reads them. I left the backend and admin page in
place rather than deleting work you might want for another screen — say the
word and they go.

The service blocks still use the vector illustrations, so those stay.

## Revision 7 — dark theme, auth redesign, suggestion fix

### Suggestion selection bug — fixed

`_onFocusChanged` cleared `_suggestions` whenever a field lost focus. Tapping a
suggestion removes focus from the text field *first*, so the list was torn out
of the widget tree before the tap could register — the suggestions looked
unselectable.

Two changes: focus loss no longer clears the list (it is dismissed on selection,
on an emptied query, or on switching service), and the suggestion rows use
`onTapDown`, which fires before the focus change.

### Dark premium theme

One palette for the whole app, in `AppColors` / `AppTint` / `AppText`:

```
background   #0B1417   deepest layer
surface      #14232A   cards and panels
surfaceAlt   #1B2E36   inset rows, inputs, chips
surfaceHigh  #213741   sheets, dialogs, floating chrome
border       #233A44
text         #F1F6F7 / #9FB3BB / #64808A
brand green  #8ED12B   unchanged — the only saturated colour
```

Status colours were brightened (`danger #FF5A4E`, `success #3DD68C`,
`info #5AA9FF`, `warning #FFB84D`) so they stay legible on dark surfaces.

`AppTheme.light` is now an alias for `AppTheme.dark`, so every existing call
site keeps working.

A global pass remapped the light hexes scattered through 14 screens — including
driver mode — onto these tokens, and added the missing imports. Nothing
ambiguous was touched: `Colors.white` was only replaced inside `BoxDecoration`
fills, never where it might be text on a dark surface.

### Language switch

The translate glyph is replaced by a labelled **EN / اردو** pill on Home,
matching the toggle already on the login screen. The active side is filled with
brand green.

### Notifications

The bell now opens a dismissible popup instead of navigating away — tap the
close button, the backdrop, or outside it. The unread dot clears on open.

### Login and verification screens

**Login:** full-screen vehicle artwork behind a four-stop scrim, with the form
on a raised sheet. Uses the same vector illustration as the home hero, so it is
sharp at any size and needs no bundled photograph.

**Verification:** four separate digit boxes instead of one wide letter-spaced
field, so the customer can see how many digits are expected and which one they
are on. The real input is offstage, so paste and SMS autofill still work; the
code auto-submits when the fourth digit lands. Adds a 30-second resend
countdown.

## Revision 6 — layout, sticky CTA, per-vehicle booking mode

### Home layout

- Hero shortened from `topInset + 330` to `topInset + 268`, so the service
  blocks sit higher. Title 26→23px, fade 150→130px.
- **The CTA is now pinned to the bottom.** Home is a `Column` of a scrolling
  `ListView` plus a fixed `_StickyCta` footer, so "Find a Car" is always
  reachable — no scrolling back down after editing an address.
- **Per-seat / full-vehicle and the passenger stepper are gone from Home.**
  Those choices belong on the next screen, where the actual vehicle and its
  rules are known. `_BusFareMode`, `_seats`, `_passengers` and the now-unused
  `UdSegmented` widget were all removed rather than left as dead code.

### Booking mode is set per vehicle by the driver

A driver decides how their vehicle can be booked, and the customer is only ever
offered what that vehicle allows.

```
WholeVehicle   default — customer books the entire vehicle
PerSeat        customer books individual seats
Both           customer chooses
```

**Driver side** (`vehicle_registration_screen.dart`): a "How can customers book
this vehicle?" card in the capacity step, with all three options and a
description each. Whole-vehicle is preselected, so a driver has to actively opt
into per-seat. On a one-seat vehicle the per-seat options are disabled with a
stated reason rather than silently missing.

**Customer side** (`udrive_route_flow_screen.dart`): the per-seat / whole-vehicle
toggle appears only when the driver allows both. With one permitted mode the
toggle is replaced by a short line — "This vehicle is offered per seat only." —
and that mode is forced. `_clampBookingMode()` runs whenever the customer
switches vehicle, so an illegal mode can never carry over.

**Backend:**

- `Migrations/028_vehicle_booking_mode.sql` — adds `booking_mode` to
  `udrive.vehicles`, defaulting to `WholeVehicle` with a CHECK constraint.
  Vehicles with 10+ seats are seeded to `Both`, since large vehicles are
  commonly sold either way; drivers can change theirs at any time.
- `PublicVehicleDto` gains `BookingMode`, and the catalog query selects it.

Run migration 028. `VehicleBookingModeInfo.fromApi` defaults to whole-vehicle on
any unknown or missing value, so an un-migrated database cannot accidentally
open per-seat booking.

## Revision 5 — blank screen fix

**Cause:** `ServiceSelector` used `Row(crossAxisAlignment: CrossAxisAlignment.stretch)`.
A `Row` inside a `Column` gets an unbounded vertical constraint, and `stretch`
forces every child to take that height — infinity. Layout threw, and the
exception took the entire booking card subtree with it, leaving the area below
the hero blank.

**Fix:** the stretch is removed. Each block already declares `height: 104`, so
the row sizes itself correctly from its children. This was my mistake in
revision 4 — the stretch was never needed.

**Hardening:** `ServiceIllustration` now checks `constraints.hasBoundedWidth` /
`hasBoundedHeight` and falls back to the 400x240 design ratio instead of passing
an infinite size to `CustomPaint`. A similar layout mistake anywhere else will
now degrade the artwork rather than blank a screen.

Note: `route_fields.dart` also uses `stretch`, but there the `Row` is wrapped in
`IntrinsicHeight`, which bounds it. That one is correct and was left alone.

## Revision 4 — service blocks, admin artwork, vehicle filtering

### Bigger service blocks with the picture inside

Each service is now a single 104px-tall block containing its illustration and
its name, instead of a small icon tile with the label floating underneath.
Selected blocks get the brand tint, a 1.6px green border and a soft shadow.

### Admin-controlled hero image

You can now change the large Home picture from the admin portal — no app build
needed.

**Admin portal:** new page at **Home screen artwork** (left nav, Control Centre
section). Four fields, one per service, each with a live preview. Paste an
`https://` image URL, or leave it empty to keep the built-in illustration.

**How it works:**

```
Admin saves  →  udrive.system_settings   (is_public = true)
                home.hero.bus.imageUrl
                home.hero.car.imageUrl
                home.hero.bike.imageUrl
                home.hero.hotel.imageUrl
                        ↓
App reads    →  GET /api/v1/settings/public   (no auth, 60s cache)
                        ↓
Home hero    →  URL set and loads   → show that image
                URL empty / fails   → built-in vector illustration
```

The app caches the last good response in shared preferences, so the right
artwork paints instantly on launch instead of flashing the fallback.

**New backend files:**

- `Controllers/PublicSettingsController.cs` — returns only rows flagged
  `is_public`, so operational settings never leak. Unwraps jsonb scalars so
  clients get `https://…` rather than `"\"https://…\""`.
- `Infrastructure/Persistence/Migrations/027_home_hero_images.sql` — seeds the
  four keys as public and empty.

Run migration 027 before using the admin page.

A bad URL cannot break Home — `errorBuilder` and `loadingBuilder` both fall
back to the illustration, and non-`https` values are rejected client-side.

### One vehicle type per service

"Find a Car" now shows only cars. Bike shows only bikes, Coaster/Bus only
coasters — no mixing.

`HomeService.vehicleFilterKey` (`'car'`, `'bike'`, `'coster'`) is threaded from
Home → `UDriveRouteFlowScreen` → `UDriveVehicleSelectionScreen`, which filters
`_choices` against `_normaliseVehicle`. If a filter ever matches nothing, the
unfiltered list is returned rather than an empty screen, so the customer is
never stuck.

### Structural cleanup

`HomeService` moved to `lib/core/widgets/home_service.dart`. The selector and
the illustration widget were importing each other; the enum now lives on its own
and `service_selector.dart` re-exports it, so existing imports still work.

## Revision 3 — full-bleed hero + correct artwork

**Bug found:** `assets/vehicles_photo/car_photo.png` actually contains a
motorbike, and `coaster_photo.png` is a marketing banner with text baked in.
That is why selecting Car showed a bike. The filenames do not match their
contents.

**Fix:** the four service illustrations are now drawn as vectors in
`lib/core/widgets/service_illustration.dart` (`CustomPainter`) instead of
loading PNGs. Reasons:

- Sharp at any size. The bundled art is 400x240; a full-bleed hero on a modern
  phone is roughly 1100px wide, so the bitmaps would visibly blur.
- No baked-in background, so the bottom fade blends perfectly.
- Colours come from `AppColors`, so the artwork follows the brand.
- No filename/content mismatch is possible — each painter is the service.

I cannot generate photographs, so these are flat vector illustrations in the
same style as your existing `assets/vehicles/` set. If you want photorealistic
renders instead, commission them and drop them in — the hero takes any widget.

**Hero layout** (`_buildServiceHero`): fills the whole top of the screen,
`topInset + 330` tall.

1. Diagonal background wash `#EFF6EA → #E7F0F2`
2. Two soft decorative blobs for depth
3. The illustration, cross-fading and sliding on service change (320ms)
4. **Bottom fade** — a 150px gradient from transparent to `#F6F8FA` at three
   stops, so the artwork dissolves into the page and no cut edge is visible
5. Service name (26px) and subtitle over the fade
6. Header controls overlaid on top

The booking card's `-24px` overlap was removed: with the fade doing the
blending there is nothing left to cover.

## Revision 2 — what changed after your feedback

1. **Map removed from Home.** The map band is replaced by a large illustration
   of the selected service, so the customer sees exactly what they picked.
   Selecting Coaster/Car/Bike/Hotel cross-fades the picture and updates the
   caption underneath. Uses your existing bundled artwork:
   `coaster_photo.png`, `car_photo.png`, `bike_photo.png`,
   `home_services/hotel_room.webp`.
2. **Free-text addresses.** The customer is no longer forced to tap a
   suggestion. Type anything; the address is geocoded when the button is
   pressed. If it cannot be resolved, the full route screen opens with the text
   pre-filled — no dead end. (Tour bookings are the one exception: that API
   needs real coordinates, so an unresolvable address asks for a more specific
   one.)
3. **Font sizes increased throughout** — captions 10.5→12, field text 14→16,
   service labels 11→12.5, CTA 15→16.5 and 50→56px tall, stepper values 15→17,
   driver-card fare 22→24. Buttons and tap targets grew to match.
4. **Header alignment fixed.** The location control and the three icon buttons
   now sit in a fixed 40px row on a shared centre axis, so they line up. Icon
   buttons went 33→40px.

`UdMap` still exists and is still used by Tour Map and Near Me — only Home
dropped it.

---

## 1. First run

```bash
cd udrive_unified_mobile
flutter pub get
flutter analyze
flutter run
```

Two new dependencies were added to `pubspec.yaml`:

| Package | Why |
| --- | --- |
| `google_maps_flutter: ^2.10.0` | Google Maps rendering |
| `share_plus: ^11.0.0` | Native share sheet for "Invite a friend" |

If `pub get` reports a version conflict, loosen the constraint to `any`, let pub
resolve it, then pin whatever it picked.

---

## 2. Google Maps API key

The map renders blank grey until a key is supplied. That is expected and does
not break anything else — every other screen works without it.

### Android

The manifest already has the placeholder wired:

```xml
<meta-data android:name="com.google.android.geo.API_KEY"
           android:value="${MAPS_API_KEY}" />
```

and `android/app/build.gradle.kts` supplies it from a Gradle property, falling
back to an empty string so a build never fails on a missing key:

```kotlin
manifestPlaceholders["MAPS_API_KEY"] =
    (project.findProperty("maps_key") ?: "") as String
```

Build with the key without committing it:

```bash
flutter build apk --release -Pmaps_key=AIza...
```

For CI, put the key in a repository secret and pass it the same way.

### iOS

`AppDelegate.swift` reads the key from `Info.plist`. Add a String entry:

```xml
<key>GMSApiKey</key>
<string>AIza...</string>
```

### Getting the key

1. `console.cloud.google.com` → new project
2. Attach a **billing account** (required — the API returns errors without one)
3. Enable: **Maps SDK for Android**, **Maps SDK for iOS**, **Places API**,
   **Geocoding API**
4. Create two API keys (Android, iOS)
5. Restrict each one — Android key to package `com.udrive.mobile` + your SHA-1
   (`cd android && ./gradlew signingReport`), iOS key to the bundle ID, and both
   to only the four APIs above
6. Set a **budget alert** so an unexpected spike is visible early

---

## 3. Maps: online Google, offline PMTiles

`lib/core/maps/ud_map.dart` is the single map surface used everywhere.

```
Connected      →  Google Maps
No connection  →  flutter_map + downloaded PMTiles pack for the route
No connection
  + no pack    →  flutter_map + cached OSM tiles, with an "Offline map" badge
```

The switch is automatic, driven by `connectivity_plus`. The existing offline
download system under `lib/core/offline_maps/` was **not** touched — `UdMap`
just consumes it.

Worth knowing: Google's Maps SDK has no offline API of any kind. Google's
consumer "download this area" feature is not exposed to developers. Keeping
PMTiles is the only way the app works in Neelum, Kel or Leepa when signal drops.

Callers use renderer-agnostic types (`UdMarker`, `UdPolyline`,
`UdMapController`) so no screen has to care which engine is active.

---

## 4. Address search: proxy first, Nominatim fallback

`lib/core/services/place_search_service.dart`

```
1. GET {API}/api/v1/places/autocomplete   ← Google key lives on YOUR server
2. Nominatim (OpenStreetMap)              ← no key, works today
```

This is why the Places key is admin-settable while the Maps SDK key is not:
autocomplete is an HTTP call your backend can proxy, so an admin sets the key
once server-side and every installed app picks it up with no rebuild. It also
keeps the key out of the APK, where anyone could extract it and spend your quota.

Until that endpoint exists, search runs on Nominatim and works fine.

Behaviour: 350 ms debounce, later requests cancel earlier ones, three-line
suggestion rows with a pin icon.

---

## 5. What changed, file by file

### New

| File | Purpose |
| --- | --- |
| `core/config/app_config.dart` | Advance %, cancellation window, radii, timeouts, map defaults |
| `core/theme/app_tokens.dart` | Tints, radii, soft shadows, text colours from the handoff |
| `core/maps/ud_map.dart` | Google + offline map wrapper |
| `core/services/place_search_service.dart` | Autocomplete + reverse geocoding |
| `core/widgets/service_selector.dart` | 4-column Coaster/Car/Bike/Hotel picker |
| `core/widgets/route_fields.dart` | Editable pickup/destination + connector + suggestions |
| `core/widgets/ud_controls.dart` | Toggle switch, stepper, segmented control |
| `core/widgets/rate_driver_card.dart` | Shared driver-offer card |
| `core/businesses/business_repository.dart` | Near Me data access |
| `models/business_models.dart` | Business listing, category, approval status |
| `screens/customer/tour_map_screen.dart` | Tour offers on a map + advance sheet |
| `screens/customer/tour_driver_detail_screen.dart` | Confirmation + 5-min cancel |
| `screens/customer/near_me_screen.dart` | Near Me browsing |
| `screens/business_owner/business_owner_add_screen.dart` | Business registration |
| `screens/business_owner/business_owner_dashboard.dart` | Owner's listings |

### Rewritten

`screens/customer/customer_home_screen.dart` — was 2,539 lines of dark
map-plus-bottom-sheet; now the light map band + floating booking card. All the
business logic carried over: location detection, reverse geocoding, the 12-second
active-trip poll, connectivity handling.

### Modified

- `core/theme/app_theme.dart` — `danger` corrected to `#D92D20`, added `text`
- `screens/main_shell.dart` — new bottom nav, Near Me tab, My business drawer entry
- `screens/hotels/hotel_list_screen.dart` — accepts city/dates/guests/rooms from Home
- `core/localization/app_strings.dart` — `nearMe`, `myBusiness` (EN + UR)
- `pubspec.yaml`, `AndroidManifest.xml`, `build.gradle.kts`, `AppDelegate.swift`

### Deleted (dead code, verified no referrers)

`screens/app_mode_shell.dart`, `screens/customer_shell.dart`,
`screens/driver/driver_shell.dart`, `screens/trips/trips_screen.dart`

`screens/profile/profile_screen.dart` also became unreferenced as a
consequence — `MainShell` uses the `ProfileScreen` in `customer/customer_pages.dart`.
I left it in place rather than delete something you might still want. Say the
word and it goes.

---

## 6. Service mapping

The `UDriveServiceType` enum did not need to change. Home just sets it correctly:

```
Coaster/Bus  →  vehicleCategory 'Coaster'
Car          →  vehicleCategory 'Car'
Bike         →  vehicleCategory 'Bike'
Hotel        →  HotelListScreen

Tour toggle OFF  →  UDriveServiceType.city
Tour toggle ON   →  tour flow (whole vehicle + advance)
Bus + "Full vehicle"  →  UDriveServiceType.privateVehicle
```

Tour is a flag, not a service — a customer can book a tour with any vehicle type.

Non-tour bookings skip the route-entry screen (Home already collected both ends)
and go straight to the existing vehicle selection, so all fare and booking logic
is reused untouched.

---

## 7. Tour flow — existing endpoints only

| Step | Call |
| --- | --- |
| Create tour request | `createLiveRideRequest({...})` |
| Poll offers (3 s) | `loadRideOffers(requestId)` |
| Accept + advance | `selectLiveDriverOffer(rideRequestId:, offerId:, advanceAmount:)` |
| Cancel within 5 min | `BookingRepository.cancelBooking(bookingId, reason)` |

**Advance rule:** 20% of the fare minimum (`AppConfig.tourAdvancePercent`). The
customer may pay more, never less; the field validates both bounds and the
balance updates live. Change the percentage in one place if the policy moves.

**Countdown:** `AppConfig.tourFreeCancellationWindow` (5 minutes), ticking every
second, cancelled on dispose and on successful cancel.

---

## 8. Three fields the API does not expose yet

The redesign's driver card asks for data the offers endpoint does not return.
Rather than invent values I handled each explicitly:

| Field | Current behaviour | Fix when backend adds it |
| --- | --- | --- |
| Driver photo | Branded initials avatar | Pass `photoUrl` to `RateDriverCard` |
| Reviews count | Omitted; shows rating + `completedTrips` | Add `reviewCount` to the card |
| Verified badge | Derived from `safetyScore >= 80` | Replace with a real `verified` flag |

The `safetyScore >= 80` rule is a placeholder I chose. Confirm it or give me the
real one.

---

## 9. Near Me — needs backend

The customer screen and the owner portal are built. They call these endpoints,
which **do not exist yet** in `udrive_api`. Until they ship, Near Me shows a
clean empty state rather than an error — by design, not by accident.

```
Customer
  GET  /api/v1/businesses/nearby?lat=&lng=&radiusKm=&category=&q=&sort=
  GET  /api/v1/businesses/{id}

Owner
  GET  /api/v1/businesses/mine
  POST /api/v1/businesses
  PUT  /api/v1/businesses/{id}

Admin
  POST /api/v1/admin/businesses/{id}/approve
  POST /api/v1/admin/businesses/{id}/reject
```

Listing shape:

```json
{
  "id": "...",
  "name": "Kashmir Grill",
  "category": "Restaurant",
  "latitude": 34.37, "longitude": 73.47,
  "address": "Domel Road, Muzaffarabad",
  "phone": "+92...",
  "photos": ["https://..."],
  "openNow": true,
  "hours": { "mon": "09:00-23:00" },
  "rating": 4.3,
  "reviewCount": 28,
  "distanceKm": 1.2,
  "verified": true,
  "status": "Approved"
}
```

Categories the client sends: `Restaurant`, `Grocery`, `MedicalStore`,
`Hospital`, `Bank`, `Fuel`, `Mosque`.

Approval works exactly like hotels — a submission starts `Pending` and only
reaches customers once an admin approves it.

Owner access is currently through the customer drawer → **My business**, rather
than a fourth `UserMode`. That keeps the enum's switch statements untouched. If
you want a dedicated business mode later, say so and I'll add
`UserMode.business` with its own shell.

Menu items and in-app ordering (your Phase C) are not started.

---

## 10. Still to do

1. `driver_offers_screen.dart` — swap its inline card for the shared
   `RateDriverCard` so both screens match
2. Migrate the other 6 map screens to `UdMap`: `udrive_route_flow_screen`,
   `vehicle_live_map`, `service_flow_screens`, `driver_home_screen`,
   `live_trip_navigation_screen`, `live_tracking_screen`
3. Full Urdu strings for the new screens (keys exist; copy needs translating)
4. `flutter analyze` clean-up after your first run

---

## 11. Non-functional notes

- **Security** — no API key in the APK for Places; `createLiveRideRequest`
  refreshes the JWT before the write, so a long form is never lost to an expired
  token; fares render only from server responses
- **Performance** — debounced and cancellable search; `AnimatedSwitcher` /
  `AnimatedSize` at 220 ms; `const` widgets throughout the booking card
- **Reliability** — every `Timer` cancelled in `dispose()` with `mounted` guards;
  failed polls keep the last good data rather than blanking the screen
- **Accessibility** — service columns padded to a 60x60 tap target; `Semantics`
  on SOS, locate, toggle, steppers and nav items; numeric keyboard on money fields
- **Offline** — connectivity banner above the booking card, CTA still visible,
  saved maps in use
