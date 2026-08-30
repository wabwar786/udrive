# UDrive Redesign — Delivery 1 & 2 (revision 3)

Implements the Home & Tour Booking redesign handoff against the existing
`udrive_unified_mobile` app. Presentation layer only — no repository, model or
API contract was changed except where a new module required new endpoints
(Near Me, listed at the end).

**This code has not been compiled.** Run `flutter pub get` then
`flutter analyze` before building. Fix anything that surfaces and tell me — I'd
rather correct it than have you work around it.

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
