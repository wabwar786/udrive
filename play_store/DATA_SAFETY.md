# Data safety — Play Console ke exact jawab

Play Console → **App content → Data safety**. Jawab isi tarteeb se aate hain.

## 1. Data collection and security

| Sawal | Jawab |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data is deleted? | **Yes** |
| Deletion URL | `https://udrive-api-production.up.railway.app/account-deletion` |
| Account deletion | **Users can request account deletion and data deletion** (app ke andar Settings → Delete account bhi hai) |

## 2. Data types

Har type par: **Collected = Yes**, **Shared = No**, **Processed ephemerally = No**,
**Required (not optional)** — siwaye jahan likha ho.

| Category → Data type | Purposes |
|---|---|
| Location → Precise location | App functionality; Fraud prevention, security and compliance |
| Location → Approximate location | App functionality |
| Personal info → Name | App functionality; Account management |
| Personal info → Phone number | App functionality; Account management; Fraud prevention, security and compliance |
| Personal info → Email address *(optional)* | Account management |
| Personal info → Address *(drivers only)* | Account management; Fraud prevention, security and compliance |
| Personal info → Other info (CNIC number, licence number, date of birth) | Fraud prevention, security and compliance; Account management |
| Financial info → Payment info *(drivers only)* | App functionality |
| Financial info → Other financial info (wallet top-ups, commission) | App functionality |
| Messages → Other in-app messages (rider ↔ driver chat) | App functionality |
| Photos and videos → Photos (driver documents, vehicle photos) | App functionality; Fraud prevention, security and compliance |
| App activity → Other user-generated content (trips, ratings) | App functionality |
| Personal info → Other info (trusted contacts, emergency contacts, and tour passenger names) | App functionality; Fraud prevention, security and compliance |
| Personal info → Other info (tour passenger **gender** and age group) | App functionality |
| Device or other IDs | Fraud prevention, security and compliance |

**Do entries baad mein shaamil ki gayin** (release audit ke dauran — code inhein
bhejta tha magar form mein declare nahi thin, aur kam declare karna bhee ghalat
declare karne jitna he masla hai):

- **Financial info → Payment info** — driver apna payout account deta hai:
  account title, bank ka naam aur account number. Yeh "Other financial info"
  se alag cheez hai.
- **Personal info → Other info (gender)** — tour package book karte waqt har
  passenger ka gender aur age group liya jata hai (`CreateTourPassenger`
  request), kyunke family-only aur women-only gaariyon ka intezam isi par
  chalta hai. Play gender ko sensitive ginta hai, is liye declare karna
  lazmi hai — chhupana reject hone ki wajah banta hai. Yeh sirf us booking
  ke driver tak jata hai, kahin bika nahi jata, ads mein istemal nahi hota.

- **Personal info → Other info (doosre logon ka data)** — trusted contacts ka
  naam aur number, booking ka emergency contact, aur tour passengers ke naam.
  Yeh user ka apna data nahi, kisi aur ka hai, is liye alag entry chahiye.
  (Play ka "Contacts" type sirf phone ki contact list parhne ke liye hai —
  app woh nahi parhti, user khud likh kar deta hai.)

**Teen entries jaan boojh kar hata di gayi hain.** Pehle yeh declare hoti thin,
magar code mein mojood hi nahi thin — aur ghalat declaration bhee utni hi buri
hai jitni kam declaration:

- ~~Audio → Voice or sound recordings~~ — SOS ki recording us endpoint par jati
  thi jo API mein kabhi bana hi nahi. Ab microphone poori tarah nikal diya gaya
  hai (`RECORD_AUDIO` permission bhee).
- ~~App info and performance → Crash logs~~ aur ~~→ Diagnostics~~ — poore
  platform mein koi crash-reporting ya diagnostics SDK nahi. Flutter ki poori
  dependency list mein Firebase, Sentry ya Crashlytics mein se kuch nahi.

Isi tarah `App activity` se `Analytics` ka maqsad bhee hata diya — koi analytics
tool mojood nahi hai, yeh data sirf app chalane ke liye hai.

**"Shared" sab par No kyun:** rider aur driver ka ek doosre ko naam aur location
dikhna user ke apne action se hota hai (Google is ko sharing nahi ginta), aur
hosting / maps jaise service providers bhi Google ki definition mein "sharing"
nahi hain.

## 3. Security practices

- Data is encrypted in transit: **Yes**
- Users can request that data be deleted: **Yes**
- Data collection follows the Families policy: N/A (app 18+ hai)
- Independent security review: **No**

## 4. Baqi App content sections

| Section | Jawab |
|---|---|
| Privacy policy | `https://udrive-api-production.up.railway.app/privacy` |
| Ads | No, my app does not contain ads |
| App access | All or some functionality is restricted → reviewer ke liye login instructions (neeche) |
| Content rating | Category: "All other app types". Violence / sexual / drugs / gambling: No. "Users can interact", "Shares location": Yes. |
| Target audience | 18 and over |
| News app | No |
| Government app | No |
| Financial features | My app doesn't provide any financial features |
| Health | No |
| Data deletion | URL upar wali |

## 5. App access — reviewer ke liye login

Admin portal → **Services → WhatsApp OTP** mein (SuperAdmin se login):
- "Google Play reviewer number" = `03000000001`
- "Reviewer code" = `5095`

Yeh number kisi bhi provider mein usi fixed code se login karta hai aur us par koi
message nahi jata.

`03000000001` database mein pehle se mojood hai (`003_seed_catalog.sql`) — naam
"Adeel Khan", **Approved Driver**, ek verified gaari `AJK-DEMO-01` ke sath. Login
ke baad app **Customer mode** mein khulta hai, aur home par "Switch to Driver
Mode" ka card se reviewer driver wala app bhee dekh leta hai. Is liye ek hi
credential se dono taraf ka jaiza liya ja sakta hai.

> **Yeh credentials app ke andar NAHI hain, aur dobara na daalein.** Pehle
> `AppController` mein `demoPhoneNumber` aur `demoReviewerCode` `static const`
> thay, yani AAB mein ship hote thay — jo bhi bundle kholta, woh production
> par ek verified Approved Driver ban kar login kar sakta tha. Aur login
> screen ka one-tap demo button `kIsWeb || kDebugMode` par tha, is liye kisi
> bhi production **web** build par woh sab ko nazar aata tha. Dono hata diye
> gaye hain. Reviewer ko rasta sirf isi "App access" field se milta hai, aur
> server us ko `system_settings` se manta hai — to ek hi jagah se revoke bhi
> ho jata hai.
>
> **Listing approve hone ke din:** Admin portal → Services → WhatsApp OTP mein
> reviewer number aur code khali kar dein. Us ke baad woh bypass band.

Play Console ke "App access" mein yeh instructions daalein:

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

**Har release se pehle check karein:** portal ke usi panel mein upar
`Login codes: WhatsApp — live` likha hona chahiye. Agar `Development code
(WhatsApp off)` likha hai to reviewer number bemaani hai — us halat mein har
number ka code ek hi fixed code hota hai, yani koi bhi kisi ke account mein ja
sakta hai.
