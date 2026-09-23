# UDrive — Google Play release guide

Package name: **com.wabwar.udrive** (pehle upload ke baad kabhi nahi badlega)
Developer account: Tech Geni Ltd. (existing Play Console account, nayi fee nahi)
Privacy / Terms / About mein company ka naam: Tech Geni Ltd. (Railway: `PublicPages__CompanyName` se badal sakte hain)

---

## 0. WhatsApp OTP chalu karein (launch blocker)

Pehle API `OTP_PROVIDER=Development` par thi — har number ka code `1234`, yani koi bhi kisi ka account
khol sakta tha. Ab login code WhatsApp (WA Engine) se jata hai, aur sab kuch admin portal se set hota hai.

Admin portal → **Services & coming soon → WhatsApp OTP**. Yahan sirf do cheezein bharni hoti hain:

1. **WA Engine API key** paste karein → **Save**
2. **Send a test message** mein apna WhatsApp number daal kar test bhejein

Test message pohanchte hi WhatsApp **khud on** ho jata hai — koi provider ya endpoint chunne ki zaroorat nahi.
Base URL (`https://wa-engine-deploy-production.up.railway.app`), send path (`/api/send`) aur message ka text
server par fixed hain.

Key badalni ho to nayi key paste kar ke Save karein, phir ek test bhejein. Jab tak nayi key se test pass na ho,
codes fixed development code par chale jate hain — yani galat key se login kabhi band nahi hota.

**Check WA connection** button WA Engine ka `/api/status` call karta hai — bagair message bheje pata chal jata
hai ke WhatsApp session connected hai ya nahi.

**Agar phir bhi kabhi login band ho jaye:** Railway → udrive-api → Variables mein
`OTP_PROVIDER_OVERRIDE=Development` daal dein. Yeh database se upar chalta hai, aur aap `1234` se
login kar ke settings theek kar sakte hain.

**Reviewer number:** usi page par "Google Play reviewer number" aur 4-hindson ka "Reviewer code" set karein.
Us number par koi message nahi jata aur wohi code chalta hai — yehi Play Console ke "App access" mein dena hai.

API key database mein rehti hai (`udrive.system_settings`), kabhi wapas nahi dikhayi jati (sirf aakhri 4
hindse), aur general System settings page par is ki row aati hi nahi.

**Admin portal ab username/password se khulta hai** (OTP se nahi), taake WA Engine kharab hone par bhi
portal khul sake. Pehla admin banane ka tareeqa `ADMIN_LOGIN.md` mein hai.

## 1. Upload key banayein (sirf ek dafa)

`udrive_unified_mobile` folder mein:

- Windows: `create_upload_key.bat`
- Mac / Linux: `./create_upload_key.sh`

Yeh bante hain:
- `android/app/upload-keystore.jks`
- `android/key.properties`

**In dono files aur password ka backup lazmi rakhein** (Google Drive + USB). Yeh kho gaye to update
upload nahi ho sakay ga (Play support se key reset karwani paray gi). Git mein commit **na** karein —
`android/.gitignore` inhein pehle se ignore karta hai.

## 2. Signed bundle (.aab) banayein

Windows: `build_play_bundle.bat` (Android Maps key poochay ga)

Ya manually:
```
flutter build appbundle --release ^
  --dart-define=DEFAULT_MODE=customer ^
  --dart-define=API_BASE_URL=https://udrive-api-production.up.railway.app ^
  -Pmaps_key=YOUR_ANDROID_MAPS_KEY
```
File: `build/app/outputs/bundle/release/app-release.aab`

Key set na ho to build khud ruk jata hai ("No upload key configured") — debug-signed file Play par nahi jati.

**Har naye upload par** `pubspec.yaml` mein `version: 9.0.0+10` ka aakhri number (+10 → +11 → +12)
barhana zaroori hai. Play same versionCode dobara qabool nahi karta.

GitHub Actions se banana ho to repo secrets add karein: `UDRIVE_KEYSTORE_BASE64`
(`base64 -w0 android/app/upload-keystore.jks`), `UDRIVE_KEYSTORE_PASSWORD`, `UDRIVE_KEY_ALIAS` (`upload`),
`UDRIVE_KEY_PASSWORD`, `MAPS_ANDROID_KEY`. "Build Play Store bundle" job `.aab` artifact de ga.

## 3. API deploy + URLs check

API deploy karne ke baad browser mein kholein:
- Privacy policy: `https://udrive-api-production.up.railway.app/privacy`
- Account deletion: `https://udrive-api-production.up.railway.app/account-deletion`
- Terms: `https://udrive-api-production.up.railway.app/terms`

**Railway → udrive-api → Variables (production checklist):**

| Variable | Value |
|---|---|
| `DATABASE_URL` | Postgres service ka reference — value box mein `${{` type kar ke list se **DATABASE_URL** chunein (naam hath se likha aur match na hua to value khali reh jati hai aur API start nahi hoti) |
| `UPLOAD_ROOT` | `/data/uploads` (volume par, warna documents deploy par mit jate hain) |
| `JWT_SIGNING_KEY` | 48+ random characters (apni banayein) |
| `OTP_HASH_SECRET` | 48+ random characters (alag) |
| `IDENTITY_HASH_SECRET` | 48+ random characters (alag) — **shuru mein hi set karein**, baad mein badla to purane drivers ke CNIC/licence hash match karna chhor dein ge |
| `ALLOWED_ORIGINS` | admin portal ka URL, comma se alag agar ek se zyada |
| `ENFORCE_PRODUCTION_SECURITY` | `true` — sab se aakhir mein lagayein |
| `PublicPages__SupportEmail` | aap ka asal support email (default `support@udrive.pk`) |
| `PublicPages__SupportPhone` | WhatsApp / phone (optional) |
| `ADMIN_BOOTSTRAP_PHONE/USERNAME/PASSWORD` | pehla portal login — dekhein `ADMIN_LOGIN.md`, password kam az kam 10 characters |

`OTP_PROVIDER` ko haath **na** lagayein. WhatsApp admin portal se on hota hai; env par sirf woh soorat mein
`OTP_PROVIDER_OVERRIDE=Development` lagana hai jab WA Engine kharab ho aur login band ho jaye.

`ENFORCE_PRODUCTION_SECURITY=true` in cheezon par API rok deta hai: teen secrets ka default hona,
`EXPOSE_DEVELOPMENT_OTP=true`, ya `ALLOWED_ORIGINS` ka khali hona. WhatsApp abhi on na ho to sirf warning
aati hai, API band nahi hoti.

Email se deletion request aaye to: Admin portal → **System settings → Delete a user account**.

## 4. Play Console — Create app

Play Console → **Create app**
- App name: `UDrive – Rides & Tours Kashmir`
- Default language: English (United States) — baad mein Urdu listing bhi add kar sakte hain
- App or game: App · Free or paid: Free
- Declarations tick karein → Create

## 5. App content (Policy → App content)

| Section | Kya bharna hai |
|---|---|
| Privacy policy | `https://udrive-api-production.up.railway.app/privacy` |
| App access | "All or some functionality is restricted" → reviewer number + code jo aap ne WhatsApp OTP page par set kiya (dekhein `play_store/DATA_SAFETY.md`). |
| Ads | No, my app does not contain ads |
| Content rating | Questionnaire: Category "All other app types"; violence, sexual, drugs, gambling sab No; "users can interact / share location" = Yes. Result aam tor par "Everyone / PEGI 3" + "Users interact, Shares location". |
| Target audience | 18 and over |
| News app | No |
| Government app | No |
| Financial features | "My app doesn't provide any financial features" (wallet sirf driver commission ke liye hai) |
| Health | No |
| Data safety | Neeche section 6 |

## 6. Data safety — jawab (poori tafseel `play_store/DATA_SAFETY.md` mein)

**Data collection and security**
- Does your app collect or share user data? **Yes**
- Is all data encrypted in transit? **Yes**
- Do you provide a way for users to request deletion? **Yes** → URL: `.../account-deletion`

**Data types** (har aik: Collected = Yes, Shared = No*, Processed ephemerally = No, Required)

| Data type | Purpose |
|---|---|
| Location → Precise location | App functionality, Fraud prevention/security |
| Location → Approximate location | App functionality |
| Personal info → Name | App functionality, Account management |
| Personal info → Phone number | App functionality, Account management, Fraud prevention |
| Personal info → Email address (optional) | Account management |
| Personal info → Address (drivers) | Fraud prevention/security, Account management |
| Personal info → Other info (CNIC, licence, date of birth) | Fraud prevention/security |
| Financial info → Purchase history / Other financial info (wallet top-ups, commission) | App functionality |
| Messages → Other in-app messages (rider–driver chat) | App functionality |
| Photos and videos → Photos (driver documents, vehicle photos) | App functionality, Fraud prevention |
| Audio → Voice or sound recordings (SOS, optional) | App functionality (safety) |
| App activity → Other actions (trips, ratings) | App functionality, Analytics |
| App info and performance → Crash logs, Diagnostics | App functionality |
| Device or other IDs | Fraud prevention/security |

\* "Shared" = No, kyunke rider/driver ko ek doosre ka naam/location dikhana app ka hissa hai aur
service providers (hosting, maps) Google ki definition mein "sharing" nahi.

## 7. Store listing (Grow → Store presence → Main store listing)

**Short description (80):**
`Book rides, tours and hotels across Azad Kashmir with verified local drivers.`

**Full description:**
```
UDrive is the local ride and travel app for Azad Jammu & Kashmir.

• Book a ride: car, motorcycle, rickshaw or coaster — see the fare before you go.
• Offer your own fare and choose from nearby drivers' offers.
• Verified drivers: every driver and vehicle is checked with CNIC, licence and vehicle documents.
• Live trip tracking, in-app chat and trip OTP for a safe pickup.
• SOS button and trusted contacts for emergencies.
• Tours and packages to Neelum, Leepa, Rawalakot, Banjosa and more.
• Hotel bookings with local partners.
• Drive with UDrive: register your vehicle, get ride requests near you and track your earnings.

Available in English and Urdu.
```

**Sab text aur graphics tayyar hain:** `play_store/` folder mein —
`STORE_LISTING.txt` (naam, descriptions, category, URLs), `graphics/` (icon 512×512,
feature graphic 1024×500, 5 phone screenshots 1080×1920), aur `DATA_SAFETY.md`
(Data safety + App access ke exact jawab). Screenshots purani screens se bane hain;
`play_store/README.md` mein likha hai unhein nayi screenshots se dobara kaise banana hai.

## 8. Testing → Release

1. **Testing → Internal testing** → Create release → `.aab` upload → testers (apni email) → Rollout.
   Pehli upload par Play App Signing "Use Google-generated key" accept karein.
2. **Google Maps fix (zaroori):** Setup → **App signing** → "App signing key certificate" ka **SHA-1**
   copy karein → Google Cloud Console → Credentials → Android Maps key → Android apps restriction mein
   package `com.wabwar.udrive` + yeh SHA-1 add karein. (Upload key ka SHA-1 bhi add kar dein.)
   Warna Play se install hui app mein map khali aaye ga.
3. **Closed testing:** agar aap ka account **personal** hai aur Nov 2023 ke baad bana tha, to nayi app ke
   liye 12 testers × lagatar 14 din closed test zaroori hai, phir Dashboard → "Apply for production".
   Organization account par yeh pabandi nahi.
4. **Production** → Create release → same `.aab` promote → Countries: Pakistan → Review → Rollout.
   Review aam tor par 1–7 din.

## 9. App mein kya badla (is release mein)

- Package `com.wabwar.udrive`, target API 36 (Android 16), release signing via upload key
- Permissions: sirf Internet, Location (app khuli ho tab), Notifications, Microphone (SOS recording).
  Background location, foreground service aur CALL_PHONE hata diye.
- Settings → **Delete account** (DELETE type kar ke) — server par naam, number, CNIC/licence data mitata
  hai, tamam sessions band, number dobara register ho sakta hai. Live ride ke dauran allowed nahi.
- Settings → Privacy / Terms ab asal pages kholte hain, About mein build number.
- Login code WhatsApp (WA Engine) se jata hai; admin portal se provider, key, path aur message set hote hain.
- Play build mein "Use approved driver demo" button aur "Testing code 1234" wali line nahi dikhti
  (web aur debug builds mein pehle ki tarah mojood hain).
