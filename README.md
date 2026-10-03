# UDrive — Car rental

19 files. Screenshot alag bheja hai: **UDrive_shipped_rental.png**.

> ## Pehle `udrive_vehicle_usage.zip` lagayein
>
> Yeh zip us ke **upar** aata hai. Aath files dono zips mein hain — un ki
> **nayi** copy isi zip mein hai, to tarteeb yeh rahe:
>
> **1.** `udrive_vehicle_usage.zip` → **2.** yeh zip.
>
> Ulta kiya to rental ka kaam adhoora reh jayega.

---

## Pehle yeh karein

Extract se **pehle** yeh 10 purani files delete kar dein:

```
udrive_api\Models\DriverDtos.cs
udrive_api\Services\VehicleUsageService.cs
udrive_api\Services\TripOperationsService.cs
udrive_api\Services\PackageMarketplaceService.cs
udrive_api\Controllers\VehicleUsageController.cs
udrive_api\Program.cs
udrive_unified_mobile\lib\core\vehicles\vehicle_usage_repository.dart
udrive_unified_mobile\lib\screens\customer\customer_home_screen.dart
udrive_unified_mobile\lib\screens\driver\live_vehicle_usage_screen.dart
udrive_unified_mobile\lib\screens\driver\live_vehicle_list_screen.dart
```

Yeh **nau nayi** files hain, bas rakh dein:

```
udrive_api\Infrastructure\Persistence\Migrations\062_car_rental.sql
udrive_api\Models\RentalDtos.cs
udrive_api\Services\RentalService.cs
udrive_api\Services\CustomerDocumentsService.cs
udrive_api\Controllers\RentalController.cs
udrive_unified_mobile\lib\core\rental\rental_repository.dart
udrive_unified_mobile\lib\screens\customer\rental_list_screen.dart
udrive_unified_mobile\lib\screens\customer\rental_booking_screen.dart
udrive_unified_mobile\lib\screens\driver\driver_rentals_screen.dart
```

---

## Aap ke teen faisle, jaisa tay hua

### 1 · Tasweer — aik, driver ki apni zimmedari

`vehicles.image_url` column **pehle se schema mein tha**, pehli migration se.
Aaj tak usay sirf demo seed bharta tha, kyun ke driver ke liye koi upload raasta
hi nahi tha. Ab wohi column bharta hai:

- **Aik tasweer per gaari.** Naya table nahi, gallery nahi, naya column nahi.
- Driver daalta hai, **seedha live** — koi admin review nahi.
- Rent ka switch tasweer ke baghair **chalta hi nahi**.
- Stock tasweer kabhi nahi lagti. Jis gaari ki tasweer nahi, wo rental list mein
  **aati hi nahi** — yeh server rokta hai, app nahi.

Serve karne ke liye maujooda **anonymous** route istemal hota hai
(`/api/v1/vehicle-images/...`), kyun ke `img` tag token nahi bhej sakta. Driver
ke documents apne protected route par hi rehte hain.

**Aik upload, chaar jagah faida:** `image_url` ko vehicle card, trip aur booking
DTOs pehle se parhte hain — asli gaari ab city rides aur tour par bhi dikhegi.

### 2 · Paisa — 20% advance app se, baqi maalik ko

| | |
|---|---|
| Booking par, app se | `rental.advance_percent` = **20%** |
| Gaari lete waqt, maalik ko naqd | baqi kiraya **+ poora deposit** |

Deposit UDrive ke paas **kabhi nahi** aata. Rakhne ka matlab hota: har khuronch
aur har wapsi ka jhagra hamari support queue se guzre, jis ka na kisi ko faida
hai na koi kamai.

Customer ki screen par deposit **apni line par**, "refundable" ke saath — total
mein chupa dena wohi cheez hai jis par handover ke waqt jhagra hota hai.

### 3 · Cancel — 48 ghante

| Kaun | Kab | Natija |
|---|---|---|
| Customer | 48 ghante se pehle | advance poora wapas |
| Customer | 48 ghante ke andar | advance maalik ko |
| Maalik | kabhi bhi | advance poora wapas |

`rental.free_cancel_hours` = 48. App apne aap yeh hisaab **nahi** karti — server
har booking ke saath `advanceRefundableNow` bhejta hai, to button par seedha
likha aata hai *"Cancel — advance returned"* ya *"advance not returned"*.

---

## Database — jo bana, aur jo jaan bujh kar nahi banaya

Aap ne kaha tha DB overload nahi karni. Is liye:

| Cheez | Faisla |
|---|---|
| `rental_bookings` | **Aik naya table** — bas yehi |
| Disclaimer ka record | **Table nahi** — do column booking par hi (`disclaimer_version`, `disclaimer_accepted_at`) |
| Customer ke documents | **Table nahi** — chaar column `customer_profiles` par |
| Listing photos | **Table nahi** — maujooda `vehicles.image_url` |
| Settings | Teen: `rental.advance_percent`, `rental.free_cancel_hours`, `rental.disclaimer_version` |

Disclaimer ka alag table banana aasan tha aur us ka faida sifar: aik booking ka
aik hi iqrar hota hai, usi waqt, aur us se kabhi sirf aik sawal poocha jata hai —
*"kon sa text mana tha"*. Version yeh bata deta hai.

Customer documents ke table ke saath status, reviewer, review notes aur poori
queue aati — us cheez ke liye jisay **koi review karta hi nahi**. Review jaan
bujh kar nahi hai: gaari dene wala kaghaz saamne khare shakhs se milata hai, aur
yehi aik check hai jo waqai kuch sabit karta hai. Admin ka hafta pehle aik CNIC
ki tasweer dekh lena kuch sabit nahi karta, aur platform ko aisa dikhata hai
jaise us ne zamanat di ho.

**Double booking:** gaari + tareekhon par `EXCLUDE USING gist` (`btree_gist`),
aur us se pehle booking ke waqt vehicle row ka `FOR UPDATE` lock. Agar managed
Postgres extension ki ijazat na de to migration **rukti nahi** — constraint
chhoot jata hai aur lock kaam karta rehta hai.

---

## Rental ab teen jagah asar daalti hai

**1 · City dispatch.** Admin ki "suitable drivers" list us gaari ko `available =
f` dikhati hai, aur assignment validator saaf mana karta hai — *"That vehicle is
out on rent across these dates."*

**2 · Tour packages (dono taraf).**

| Package ki haalat | Rental | Package ka kya |
|---|---|---|
| Koi seat nahi biki | ho jati hai | departure public search se **chup** jati hai, rental khatam hote hi **khud wapas** |
| Seat bik chuki hai | **mana** | jaisi hai waisi |

Mana karte waqt wajah likhi aati hai: *"carrying the Neelum departure on 20 Jun
with 4 seat(s) already sold"*. Sirf "not available" kehna driver ko soch mein
daal deta hai ke app kharab hai.

**3 · Self-drive par sirf gaari band, driver nahi.** Customer khud chala raha hai
to gaari chali gayi magar driver ghar par hai — us ki **doosri** gaari city rides
leti rahegi.

---

## Build ke baad verify karein

| File | Yeh text milna chahiye |
|---|---|
| `062_car_rental.sql` | `ex_rental_bookings_no_overlap` |
| `RentalDtos.cs` | `RentalBlockedDayDto` |
| `RentalService.cs` | `rental_clashes_with_package` |
| `CustomerDocumentsService.cs` | `customer-documents` |
| `RentalController.cs` | `DriverRentalController` |
| `VehicleUsageService.cs` | `vehicle_photo_required` |
| `VehicleUsageController.cs` | `UploadPhoto` |
| `DriverDtos.cs` | `PhotoUrl` |
| `TripOperationsService.cs` | `rental_bookings` |
| `PackageMarketplaceService.cs` | `rb.status IN ('Confirmed', 'HandedOver')` |
| `Program.cs` | `RentalService` |
| `rental_repository.dart` | `RentalBlockedDay` |
| `rental_list_screen.dart` | `_VehicleCard` |
| `rental_booking_screen.dart` | `_ModeTile` |
| `driver_rentals_screen.dart` | `DriverRentalsScreen` |
| `vehicle_usage_repository.dart` | `uploadPhoto` |
| `live_vehicle_usage_screen.dart` | `_uploadPhoto` |
| `live_vehicle_list_screen.dart` | `DriverRentalsScreen` |
| `customer_home_screen.dart` | `_openCarRental` |

Repo ke checkers saaf: `audit_structure.py` → AUDIT CLEAN, `check_imports.py` →
WRONG API 0 / MISSING WIDGET FIELDS 0 / AMBIGUOUS 0 (`driver_home_screen.dart:
uses 'S'` purana false-positive hai), `check_const_colours.py` → 0. Readiness ke
17 test sab pass.

> Checker ne is baar aik asli ghalti pakri: maine `FilePicker.platform.pickFiles`
> likha tha, is project ka file_picker static form deta hai. Theek kar diya —
> warna build toot-ti.

---

## Live Postgres par kya kya chala kar dekha

1. Migration 062 **do baar** — saaf. Exclusion constraint bana.
2. Overlapping booking **mana**; agle din wali **manzoor**; **cancelled** purani
   booking rokti nahi.
3. Ghalat mode, ulti tareekhein, rate 0 — teenon database ne roke.
4. Rent on + rate set magar **tasweer nahi** → list mein nahi aayi. Tasweer lagte
   hi aa gayi.
5. 11–13 Jun par rent → 10–12 Jun ki search ne kuch nahi dia; blocked days ne
   teen din `rented` ke saath wapas kiye.
6. Package par seat na biki → koi clash nahi. 4 seat biki → clash, naam aur
   tareekh ke saath.
7. Dispatch: rental se pehle `available = t`, rental par `f`, validator ka rental
   flag `t`, rental cancel karte hi wapas `t`.
8. Package public search: rental se pehle nazar aaya, rental par gayab, rental
   khatam hote hi khud wapas.

---

## Deploy ke baad

Migration khud lag jayegi. Us ke baad:

1. **Admin portal → Services → Car rental** khol dein. Band hone par tile par
   "SOON" aata rahega, bilkul pehle ki tarah.
2. Driver ko batana hoga: **Vehicles → gaari → tasweer lagayein**, phir
   **"What this vehicle is for" → Rent a car**.
3. Advance, cancel window aur disclaimer version `system_settings` mein
   `rental.*` se badalte hain. In ka admin page agle package mein daal sakta
   hoon — bolein to.

---

## Agla

**Growth zip 5** — referral, weekly, updates, notifications. Ya rental ka
admin page (bookings ki list, settings ke field). Jo kahein.
