# Customer UI Redesign — Map-first home + real vehicle pictures

Yeh update customer app ki UI ko inDrive-style **map-first** bana deta hai aur
har ride card par **asli vehicle ki picture** dikhata hai. Tourism focus Azad
Kashmir par set hai.

## Kya change hua

### 1. Map-first home (inDrive style)
`lib/screens/customer/customer_home_screen.dart` ab poori screen par
OpenStreetMap dikhata hai (Azad Kashmir / Muzaffarabad center), upar floating
"Where in Kashmir to?" search bar + popular destination chips, aur neeche ek
**draggable bottom sheet** jismein rides, vehicle-type tabs, search, current
booking, metrics aur quick actions hain. Map par:
- Tourist destination pins (Muzaffarabad, Pir Chinasi, Neelum Valley, Sharda,
  Arang Kel, Rawalakot, Banjosa) — pin tap karne par booking us destination ke
  saath khul jati hai.
- "Live" nearby vehicles Muzaffarabad ke aas-paas (map ko active feel dene ke
  liye).
- User ki apni location ka dot (agar permission mile).
- Recenter (my-location) button.

### 2. Asli vehicle pictures on cards
- Nayi flat illustrations: `assets/vehicles/{sedan,suv,van,coaster,bike,rickshaw}.png`
- Naya helper: `lib/core/widgets/vehicle_art.dart`
  - `VehicleArt.from(text)` — vehicle name/title/registration se category detect
    karta hai (car, 4x4 jeep, van, coaster, bike, rickshaw).
  - `VehicleThumb` — ride cards par vehicle ki picture (Muzaffarabad ke pahaari
    routes ke liye 4x4/jeep alag dikhta hai).
  - `VehicleBanner` — package card ke bade cover ke liye fallback (agar scenery
    cover na ho to vehicle illustration).
- Home ke scheduled ride cards, `LivePackagesScreen` ke cards aur package detail
  header — sab par vehicle picture.

### 3. Tourism (Kashmir) focus
Local pick/drop (inDrive) ke bajaye yeh destinations-first hai: map par tourist
points, chips se direct booking, aur Muzaffarabad hub.

## Build karne se pehle (zaroori)
Naya asset folder add hua hai, is liye:

```bash
cd udrive_unified_mobile
flutter pub get
flutter run     # ya: flutter build apk
```

Location permissions (`ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`)
AndroidManifest mein pehle se maujood hain.

## Notes
- Map ke liye koi Google Maps API key ki zaroorat nahi — app pehle se
  `flutter_map` + OpenStreetMap tiles use karti hai (free).
- Abhi vehicle pictures clean illustrations hain (category-based). Jab backend
  mein driver ki asli vehicle photo ka field aa jaye, `VehicleThumb` ko sirf
  `imageUrl:` pass kar dena — woh apne aap photo dikha dega, warna illustration.
- Nearby vehicles aur destination coordinates `vehicle_art.dart` ke
  `KashmirPlaces` mein hain — aasani se edit ho sakte hain.
