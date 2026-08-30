# UDrive Redesign — Delivery 1 & 2 (revision 11)

Implements the Home & Tour Booking redesign handoff against the existing
`udrive_unified_mobile` app. Presentation layer only — no repository, model or
API contract was changed except where a new module required new endpoints
(Near Me, listed at the end).

**This code has not been compiled.** Run `flutter pub get` then
`flutter analyze` before building. Fix anything that surfaces and tell me — I'd
rather correct it than have you work around it.

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
