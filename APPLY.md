# UDrive — Demo OTP text hata di, reviewer demo account 03000000001 / 5095

App ki kisi bhi screen par ab koi OTP likha hua nahi hai, aur Google Play
reviewer ke liye demo account ka poora intezam tay ho gaya hai.

**Server par koi code change nahi** — na API, na migration, na naya environment
variable. Reviewer number ek database setting hai jo aap portal se lagayenge
(neeche section 3).

---

## 1. Files kahan rakhni hain

ZIP ke andar ka raasta bilkul repo ke raaste jaisa hai.

| ZIP ka file | Kya badla |
|---|---|
| `udrive_unified_mobile/lib/screens/auth/otp_screen.dart` | OTP wali screen ka info panel — ab koi code nahi likhta |
| `udrive_unified_mobile/lib/screens/auth/login_screen.dart` | login screen ki neeche wali line — ab har build mein ek hi jumla |
| `udrive_unified_mobile/lib/core/localization/app_strings.dart` | teen purani keys nikal di gayin |
| `udrive_unified_mobile/lib/core/state/app_controller.dart` | demo login ab `5095` istemal karta hai |
| `PLAY_STORE_RELEASE.md` | ek ghalat dawa theek kiya |
| `play_store/DATA_SAFETY.md` | reviewer ke liye asal credentials aur qadam |
| `RAILWAY_CHECKLIST.md` | SuperAdmin login ka qadam durust kiya |
| `udrive_api/README.md` | test accounts ka section durust kiya |

Phir:

```
cd udrive_unified_mobile
flutter pub get
flutter analyze
flutter build appbundle --release
```

`versionCode` barhana na bhoolein.

---

## 2. Kya hataaya — aur kyun

### `otp_screen.dart` — yahi asal masla tha

OTP wali screen ke neeche ek info panel tha jo likhta tha:

> **Use code 1234 during testing.** / ٹیسٹنگ کے لیے کوڈ 1234 استعمال کریں۔

Is par **koi build-guard nahi tha**. Yani yeh release Android build mein bhee
dikhta tha — Play Store par chali gayi har build mein. Aur jis waqt provider
`Development` ho, woh 1234 **har number** par chalta hai, sirf test number par
nahi. Matlab app khud har us bande ko chaabi de rahi thi jo yeh screen kholta
tha.

`PLAY_STORE_RELEASE.md` mein likha hua tha ke release build mein yeh line nahi
dikhti. Woh dawa sirf login screen ke liye durust tha. Ab dono theek hain.

Nayi line:

> The code is sent on WhatsApp and expires in 5 minutes.
> کوڈ واٹس ایپ پر بھیجا جاتا ہے اور 5 منٹ میں ختم ہو جاتا ہے۔

### `login_screen.dart`

Pehle debug/web build mein "Testing code is 1234 on test builds." likha aata
tha. Ab har build mein ek hi jumla:

> A 4-digit code is sent to this number on WhatsApp.
> کوڈ آپ کے واٹس ایپ نمبر پر بھیجا جائے گا۔

"Use approved driver demo" wala button pehle ki tarah sirf web aur debug mein
hai; release mein nahi.

### `app_strings.dart`

Teen keys nikal di gayin — `demoLogin`, `otpSubtitle`, `invalidOtp` (angrezi aur
urdu dono). Inhein koi widget parhta hi nahi tha, magar do mein `1234` likha
hua tha aur woh APK ke andr string ban kar chali jati thin, jahan se koi bhee
nikal sakta hai. Dono maps ab 372-372 keys par barabar hain.

### `app_controller.dart`

Demo login ab `5095` bhejta hai, `1234` nahi, aur number aur code do named
constants mein aa gaye hain (`demoPhoneNumber`, `demoReviewerCode`).

---

## 3. Portal mein kya karna hai

1. Admin portal mein **SuperAdmin** se login karein.
2. **Services** page → neeche WA Engine / OTP ka panel.
3. *Google Play reviewer number* = `03000000001`
4. *Reviewer code (4 digits)* = `5095`
5. **Save**.

Ab `03000000001` hamesha `5095` qubool karega, us par koi WhatsApp message nahi
jayega, aur yeh har provider se upar chalta hai.

### ⚠️ Yeh check kiye baghair release na karein

Usi panel mein sab se upar likha hota hai ke codes kahan se aa rahe hain:

- `Login codes: WhatsApp — live` — **theek hai.**
- `Login codes: Development code (WhatsApp off)` — **masla hai.** Is halat mein
  har number ka code ek hi fixed code hota hai, yani koi bhi kisi ke account
  mein ja sakta hai. Reviewer number lagane se yeh theek nahi hota.

Agar doosri surat ho to Railway par yeh dekhein:

- `OTP_PROVIDER_OVERRIDE` — yeh database se upar chalta hai.
- `OTP_PROVIDER` — sirf `WhatsApp` aur `Development` pehchane jate hain. Koi aur
  value (maslan `PHASE_20_ENVIRONMENT.example` mein likha hua
  `ProductionProvider`) **chupke se `Development` ban jati hai**. Is liye
  variable par bharosa na karein — portal jo likh raha hai wohi sach hai.

---

## 4. Demo account — reviewer ko kya dena hai

`03000000001` database mein pehle se hai (`003_seed_catalog.sql`): naam
**"Adeel Khan"**, role **Driver**, status Approved, aur verified gaari
`AJK-DEMO-01`.

Yeh ek hi account reviewer ko dono taraf dikha deta hai:

- Login ke baad app **Customer mode** mein khulta hai — booking, fare,
  tracking, Explore.
- Home par **"Switch to Driver Mode"** ka card aata hai (kyunke account approved
  driver hai) — ek tap aur driver ka app: requests, offers, earnings.

Play Console → **App access** mein yeh daalein:

```
Username / phone: 03000000001
Password / OTP:   5095

1. Open the app. The first screen asks for a name and a mobile number.
2. Enter the phone number above and tap "Send verification code".
3. Enter the 4-digit code above. No SMS or WhatsApp message is sent to this
   number — the code above always works.
4. The app opens in Customer mode: book a ride, browse Explore, view tours.
5. To review the driver side, tap "Switch to Driver Mode" on the home screen.
   The same account is an approved driver with a verified vehicle.
```

Agar aap portal mein code kabhi badlein, to `app_controller.dart` ka
`demoReviewerCode` bhee badalna hoga — warna web/debug wala demo button kaam
karna chhor dega. Yeh jaan boojh kar aise rakha hai: app ke andr ek alag code
rakhna, jise portal se mansookh na kiya ja sake, is se bura hai.

---

## 5. Janch jo ki gayi

- `lib/` mein ab koi OTP kisi UI string mein nahi. `1234` sirf do comments mein
  raha, aur `5095` sirf us ek constant mein.
- `app_strings.dart` ke dono maps 372-372 keys, dono ke key-set bilkul barabar,
  koi duplicate nahi, braces barabar, aur teenon hatai gayi keys kahin nahi.
- Hatai gayi keys kahin parhi nahi jati thin — poore `lib/` aur `test/` mein
  grep kar ke dekha (`_demoLogin` sirf ek method ka naam hai, key nahi).
- Repo ke apne static tools: `check_imports.py` saaf (0 ambiguous, 0 undeclared,
  0 swallowed, 0 missing widget fields, 0 wrong API forms), `audit_structure.py`
  → AUDIT CLEAN.
- Dono badle hue widget blocks haath se parh kar dekhe — brackets barabar.

**Yahan Flutter SDK nahi hai, is liye `flutter analyze` aur `flutter build` main
nahi chala saka.** Apni machine par pehle `flutter analyze` chala lein.

---

## 6. Ek cheez jo main ne nahi chhoi

`login_screen.dart:34` mein phone ka khana `03001234567` se pehle se bhara hua
aata hai (`hintText` bhee wohi). Aap ne kehne ko nahi kaha, is liye chhor diya —
bolein to hata doon.
