# UDrive — Admin ka Car rentals page

10 files. Screenshot alag bheja hai: **UDrive_shipped_admin_rental.png**.

> ## Tarteeb
>
> **1.** `udrive_vehicle_usage.zip` → **2.** `udrive_car_rental.zip` → **3.** yeh zip.
>
> Paanch files pichle zip mein bhi theen; un ki **nayi** copy isi mein hai.

---

## Pehle yeh karein

Extract se **pehle** yeh 6 purani files delete kar dein:

```
udrive_api\Models\RentalDtos.cs
udrive_api\Services\VehicleUsageService.cs
udrive_api\Program.cs
admin_portal\app\components\admin-frame.tsx
udrive_unified_mobile\lib\core\rental\rental_repository.dart
udrive_unified_mobile\lib\screens\customer\rental_booking_screen.dart
```

Yeh **chaar nayi** files hain, bas rakh dein:

```
udrive_api\Infrastructure\Persistence\Migrations\063_rental_admin.sql
udrive_api\Services\AdminRentalService.cs
udrive_api\Controllers\AdminRentalController.cs
admin_portal\app\rentals\page.tsx
```

---

## Page kahan hai

Admin portal → **Daily operations → Car rentals** (Bookings ke theek neeche).
Rental bhi aik booking hai — sirf ghanton ke bajaye dinon ki.

Chaar hissay: **numbers → list → settings → rent par lagi gaariyan**.

---

## Aap ke teen sawalon ke jawab — wohi jo maine tajweez kiye thay

### 1 · Customer ke kaghaz — admin ko **nishan** dikhte hain, tasweer nahi

Detail screen par likha aata hai *"CNIC front · CNIC back · Licence · Photo"* aur
saath yeh jumla: **"The owner sees the images. We see only whether they were
given."**

Tasweer dekhne ka matlab hai platform us check ka hissa ban gaya jo us ki apni
shartein kehti hain wo nahi karta. Aur asli check wo hai jo gaari dene wala
saamne khare shakhs ke chehre se milata hai — us ki naql kisi daftar mein baithe
shakhs ki screen par mumkin hi nahi.

### 2 · Admin cancel — haan, magar wajah laazmi

Khali box par button hi nahi chalta, aur server bhi `cancel_reason_required` keh
kar mana karta hai.

Record mein `cancelled_by = Admin` likha jata hai — **maalik par dagh nahi,
customer par bhi nahi** — aur advance customer ko wapas. "Owner cancelled"
likhna platform ka apne hi driver ke bare mein jhoot hota.

Har admin cancel `audit_logs` mein bhi jata hai (`rental.cancelled`), wajah ke
saath.

### 3 · Deposit — **maximum**, jaisa maine kaha tha

`rental.maximum_deposit`. **0 = koi had nahi**, jahan se yeh shuru hota hai.

Had lagate hi driver app bhi maanti hai: zyada deposit rakhne par
`rent_deposit_too_high` — *"The most you can ask as a deposit is PKR 50,000."*
Pehle koi had nahi thi, aur 2 lakh deposit maang kar gaari ko listing mein
rakhte huay bhi na-qabil-e-booking banaya ja sakta tha.

---

## Aik cheez jo maine saath hi theek kar di

**Terms ka text ab database mein hai**, app ke andar nahi.

Pehle aik jumla badalne ke liye naya build, Play Store review aur intezar chahiye
tha — us lafz ke liye jo wakeel usi dopahar badalwana chahe. Is se bhi buri baat:
**version pehle se har booking par mehfooz tha**, yani database bari ehtiyat se
likh raha tha ke customer ne kon sa text mana, jab ke text wahan tha jahan
database dekh hi nahi sakta.

- Do nayi public settings: `rental.disclaimer_text_en` aur `_ur`.
- App unhein usi **public settings route** se parhti hai jo pehle se chal raha
  hai — koi naya plumbing nahi, aur login se pehle bhi parhi ja sakti hain.
- **Version khud barhta hai** jab text badalta hai. Admin ke haath mein chhorne
  ka matlab: jis din koi lafz badal kar number bhool gaya, us ke baad ki har
  booking aise version par ishara karti hai jis ka text ab mojood hi nahi — aur
  acceptance record, jis ke liye version rakha hi gaya tha, bekaar ho jata hai.
- App wohi version bhejti hai jo **us ne screen par dikhaya**. Agar admin terms
  usi waqt badal de jab customer screen khole baitha hai, server booking mana kar
  deta hai — jo theek hai: customer ne wo lafz manay thay jo ab lafz nahi rahe.
- Settings call na chale to app `version 0` wala purana text dikhati hai, jis par
  booking **ho hi nahi sakti**. Aise lafzon par razamandi jinhein platform baad
  mein pehchan na sake, dono mein se kisi ke kaam ki nahi.

---

## Jo admin yahan se **nahi** kar sakta

- Kisi ki booking ki tareekhein, rate ya deposit badalna. Wo do doosray logon ka
  tay kiya hua mamla hai; us mein haath dalna, aur wo bhi dono ko batai baghair,
  is page ka kaam nahi.
- Customer ke kaghaz ki tasweer kholna.
- Maalik ki taraf se cancel dikhana.

---

## Chhoti cheezein jo kaam ki hain

- **Deposit kabhi "paid" nahi likha.** List mein likha aata hai
  *"+ PKR 20,000 deposit, with the owner"*. Wo raqam platform ke paas aati hi
  nahi, aur aisa refund dhoondna jo humne liya hi nahi — aik lamba bekaar din
  hota hai.
- **CSV export** wohi rows deta hai jo screen par hain, filter samet. Server se
  dobara query karne ka matlab hota ke export aur table chupke se alag ho jayein.
- **Hidden ki wajah** poori likhi hoti hai — *"No photograph of this vehicle."* —
  un lafzon mein jo agent phone par dohra sakta hai. Sirf "hidden" kehna call ko
  shuru se shuru karwa deta hai.
- **Advance collected** sirf advance ginta hai. Balance aur deposit platform tak
  pohonchte hi nahi; unhein revenue dikhana aisa number hota jis par koi na koi
  aakhir amal kar baithta.

---

## Build ke baad verify karein

| File | Yeh text milna chahiye |
|---|---|
| `063_rental_admin.sql` | `rental.maximum_deposit` |
| `AdminRentalService.cs` | `cancel_reason_required` |
| `AdminRentalController.cs` | `admin/rentals` |
| `RentalDtos.cs` | `AdminRentalSummaryDto` |
| `VehicleUsageService.cs` | `rent_deposit_too_high` |
| `Program.cs` | `AdminRentalService` |
| `admin_portal/app/rentals/page.tsx` | `Vehicles on offer for rent` |
| `admin_portal/app/components/admin-frame.tsx` | `Car rentals` |
| `rental_repository.dart` | `class RentalTerms` |
| `rental_booking_screen.dart` | `_terms.version` |

Admin portal par `tsc --noEmit` saaf. Readiness ke 17 test pass.
Dart checkers saaf (`driver_home_screen.dart: uses 'S'` purana false-positive).

---

## Live Postgres par kya chala kar dekha

1. Migration 063 **do baar** — saaf. Chhe `rental.*` settings, sab `is_public`.
2. Summary ke number: aik gaari bahar, aik self-drive, aik is hafte shuru,
   advance **9,300** — cancelled booking ka 5,400 isi liye shamil nahi.
3. Fleet: tasweer wali gaari `listed`, baghair tasweer wali `hidden` +
   *"no photo"*.
4. Settings upsert: version 1 → 2, text badla, `maximum_deposit` 50,000 — aur
   wohi value jo `VehicleUsageService` ceiling ke taur par parhti hai.
5. Admin cancel: pehli baar 1 row, **doosri baar 0** (do dafa cancel nahi hota),
   audit row likhi gayi, aur cancelled booking ne apni tareekhein chhor deen.

---

## Deploy ke baad

Migration khud lag jayegi. Us ke baad:

1. Admin portal → **Car rentals** kholein. Settings mein deposit ki had rakh dein
   (abhi 0 = koi had nahi).
2. Terms ka text parh lein — jo abhi hai wo wohi hai jo app mein likha tha. Badal
   dein to version khud 2 ho jayega.

---

## Agla

**Growth zip 5** — referral, weekly, updates, notifications. Jo kahein.
