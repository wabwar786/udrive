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
| Financial info → Other financial info (wallet top-ups, commission) | App functionality |
| Messages → Other in-app messages (rider ↔ driver chat) | App functionality |
| Photos and videos → Photos (driver documents, vehicle photos) | App functionality; Fraud prevention, security and compliance |
| Audio → Voice or sound recordings *(optional — SOS only)* | App functionality |
| App activity → Other user-generated content (trips, ratings) | App functionality; Analytics |
| App info and performance → Crash logs | App functionality |
| App info and performance → Diagnostics | App functionality |
| Device or other IDs | Fraud prevention, security and compliance |

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

Admin portal → **Services & coming soon → WhatsApp OTP** mein:
- "Google Play reviewer number" = ek number jo aap ke paas ho (jaise `03001234567`)
- "Reviewer code" = 4 hindse (jaise `4417`)

Yeh number kisi bhi provider mein us fixed code se login karta hai aur us par koi
message nahi jata. Phir Play Console mein yeh instructions daalein:

```
Username / phone: 03001234567
Password / OTP:   4417

1. Open the app and choose Customer.
2. Enter the phone number above and tap "Send verification code".
3. Enter the 4-digit code above. No SMS or WhatsApp message is needed for this
   test number.
```
