# UDrive — Privacy Policy, Terms, aur in-app legal reader

Do dastawez, dono zabanon mein, aur woh code ki tabdeeliyan jo un dastawezat ko
**sach** banati hain.

Ek baat pehle saaf kar doon: inDrive ka matn copy nahi kiya. Woh unka likha hua
hai, aur us mein unki companies, unke sub-processors aur unke servers likhe
hain. Agar aap ki policy kahe ke data Amsterdam jata hai jabke woh Railway par
hai, to woh policy aap ko bachaegi nahi — Play ke Data Safety se mail na khane
par takedown ki wajah ban jayegi. Jo yahan hai woh UDrive ka apna asal data
flow hai, code se milakar likha gaya.

**Main wakeel nahi hoon.** Yeh ek mazboot masauda hai. Publish se pehle Pakistan
mein kisi wakeel se parhwa lein.

---

## 1. Sab se pehle — do surakh jo is kaam ke doran nikle

Yeh policy likhne ki wajah se pakre gaye, aur dono theek kar diye hain:

**(a) Koi bhee, bina login ke, kisi bhee driver ka CNIC utha sakta tha.**
`PublicVehicleImageController` aur `CatalogController` ke image routes
`[AllowAnonymous]` hain. Woh `ResolveProtectedFile` ko call karte the, aur us
mein exact path na milne par `FindLegacyFile` **har storage root mein file ke
naam se recursive talash** karta hai. Yani
`GET /api/v1/vehicle-images/x/{koi-bhee-filename}.jpg` kisi bhee driver ka CNIC
wapas kar deta tha — bina kisi token ke. Dono par ab
`allowLegacyFallback: false` hai.

**(b) Har logged-in customer ya driver bhee yahi kar sakta tha** —
`/api/v1/feedback/files` par koi role, koi ownership, koi category check nahi
tha. Ab teen shartein hain: category `disputes` ho, owner woh case ho jis mein
aap shaamil hain, aur file us case ki evidence mein darj ho. `AdminDisputesController`
par bhee category ki pabandi aur fallback band.

Filenames random GUID hain, is liye andaze se nikalna aasan nahi tha — magar koi
bhee raasta jisse ek path bahar aaye (support email, screenshot, log) hamesha ke
liye khul jata tha.

## 2. Files kahan rakhni hain

ZIP ke andar ka raasta repo ke raaste jaisa hai.

### udrive_api

| File | Kya hai |
|---|---|
| `Content/legal/*.md` (6) | **Naya** — policy aur terms ka asal matn |
| `Services/LegalDocumentService.cs` | **Naya** — markdown parhta aur render karta hai |
| `Controllers/PublicPagesController.cs` | Badla — matn C# se nikal kar markdown se aata hai |
| `Controllers/FeedbackController.cs` | Badla — **security fix** |
| `Controllers/PublicVehicleImageController.cs` | Badla — **security fix** |
| `Controllers/CatalogController.cs` | Badla — **security fix** |
| `Services/LocalFileStorageService.cs` | Badla — naya `allowLegacyFallback` parameter |
| `Services/AccountDeletionService.cs` | Badla — ab documents aur files bhee mitti hain |
| `Services/WhatsAppService.cs` | Badla — SOS ka matn aur safety number ki tarteeb |
| `Program.cs`, `UDrive.Api.csproj` | DI aur EmbeddedResource |

### udrive_unified_mobile

| File | Kya hai |
|---|---|
| `assets/legal/*.md` (6) | **Naya** — wohi chhe files, app ke sath bundle |
| `lib/screens/common/legal_screen.dart` | **Naya** — app ke andr parhne wali screen |
| `tool/check_legal_sync.py` | **Naya** — dono copies ka pehra |
| `lib/screens/common/common_pages.dart` | Settings ke links ab andr khulte hain |
| `lib/screens/common/delete_account_screen.dart` | "What happens to my data?" |
| `lib/screens/auth/login_screen.dart` | Terms · Privacy ab tappable |
| `lib/screens/safety/customer_sos_sheet.dart` | Microphone nikal diya |
| `lib/core/communication/whatsapp_repository.dart` | Voice broadcast nikal diya |
| `pubspec.yaml` | `record` package nikala, `assets/legal/` jora |
| `android/.../AndroidManifest.xml` | `RECORD_AUDIO` nikala |
| `ios/Runner/Info.plist` | Background-location wali ghalat line nikali |

### play_store

`DATA_SAFETY.md` — Audio, Crash logs aur Diagnostics nikal diye (teenon declare
the magar code mein mojood hi nahi the).

## 3. Chalane ka tareeqa

```
cd udrive_api          && dotnet build
cd udrive_unified_mobile && flutter pub get && flutter analyze
```

Koi migration nahi. Koi naya environment variable nahi. `record` package hat gaya
hai, is liye `flutter pub get` zaroori hai.

Release se pehle **har baar**:

```
cd udrive_unified_mobile
python3 tool/check_legal_sync.py
```

Yeh API se live matn utha kar app ki bundled copy se milata hai aur ek byte ka
farq bhee ho to fail karta hai. Yehi woh cheez hai jo dono nuskhon ko alag hone
se rokti hai.

---

## 4. Dastawez

`content/legal/` mein chhe files:

- `privacy-policy.en.md` / `.ur.md`
- `terms.en.md` / `.ur.md`
- `account-deletion.en.md` / `.ur.md`

English **governing** hai, Roman Urdu tarjuma. Har file ke upar front matter
mein version aur tareekh hai. Operator **Tech Geni Ltd.**, qanoon aur adalat
**Azad Jammu & Kashmir, Muzaffarabad**, rabta **WhatsApp 0335-6823975**.

URLs wohi hain jo Play Console mein pehle se darj hain — `/privacy`, `/terms`,
`/account-deletion` — aur ab `?lang=ur` bhee chalta hai. Raw matn
`/legal/privacy-policy.en.md` par.

### Markazi waada

Jo aap ne khaas taur par maanga, aur jo UDrive **sach mein** keh sakta hai:

> Tasdeeq ke liye asal CNIC, licence aur registration lete hain. Sirf usi ke liye
> istemal hote hain. Kisi ko bechte nahi.

Aur is ke sath woh baat jo inDrive nahi likh sakta: **poore platform mein koi
analytics nahi, koi crash-reporting nahi, koi ishtihar nahi, koi attribution SDK
nahi, koi third-party cookie nahi.** Advertising ID, IMEI, MAC — koi cheez parhi
hi nahi jati. Device ID bhee sirf ek timestamp hai jo app khud banati hai.

Magar poori sachai bhee likhi hai: data kin ko jata hai — Google (Places,
Geocoding, Routes, Tiles, aur Maps SDK jo phone se seedha Google se baat karta
hai), WA Engine, OpenStreetMap, Google Fonts, Apple (iPhone par ek screen ka
geocoder), Unsplash (hotel ki namoona tasweerein), aur Railway. Yeh "sale" nahi,
service providers hain — magar naam se likhe hain.

## 5. App mein link — paanch jagah

1. **Login screen** — "Terms · Privacy" ab tappable hai. Yehi razamandi ka lamha
   hai, aur pehle yeh bejaan matn tha jis par tap hi nahi hota tha.
2. Settings → Privacy Policy
3. Settings → Terms
4. Delete account screen → "What happens to my data?"
5. Customer aur Driver dono ke menu Settings tak jate hain.

**Matn app ke andr khulta hai, browser mein nahi**, aur app ke sath bundle hai —
is liye Neelum ya Leepa mein bina signal ke bhee khul jata hai. Upar Roman /
English ka switch hai, aur ek "open online" ka button.

## 6. Code ki tabdeeliyan jo dastawez ko sach banati hain

**Microphone nikal diya.** SOS sheet 30 second ki recording kar ke
`/whatsapp/emergency-voice-broadcast` par bhejti thi — **woh endpoint API mein
kabhi bana hi nahi.** Har alert upload par 404 hota tha aur customer ko emergency
mein, aadha minute button dabane ke baad, likha aata tha ke "recording bheji
nahi gayi". Ab ek tap, aur wohi hissa chalta hai jo hamesha kaam karta tha:
safety desk ko case, aur trusted contacts ko naam + location.

**Account delete ab poora delete hai.** Pehle CNIC aur licence ke *number* mit
jate the magar *tasweerein* volume par pari rehti thin. Ab documents, unki rows,
payout account, top-up ke screenshots aur aakhri maloom jagah — sab mitte hain.
Files transaction commit hone ke baad mittī hain, taake rollback ki soorat mein
tasweerein bemaqsad zaya na hon.

**SOS ka paighaam** ab "emergency microphone/panic alert" nahi kehta — mic hai hi
nahi. Aur hamara safety number ab list mein **pehle** hai: pehle woh aakhir mein
lagta tha aur `Take(12)` us ko hi kaat deta tha jis ke paas barah trusted
contacts hon — yani ek emergency mein sab se zaroori number.

**iOS `Info.plist`** se woh line nikal di jo kehti thi ke UDrive background mein
location leta hai. Woh ghalat thi (Android manifest, aur poora code, is ke ulat
hai) aur policy ke barkhilaf thi.

## 7. Jo dawe ghalat the aur theek kiye

Dastawez ko ek alag reviewer se code ke khilaf janchwaya. Yeh nikla:

- Fare ki hadd **sirf tab** lagu hoti hai jab app server ka quote bhejti hai —
  `pricing.quote.required` abhi `false` par ship hoti hai. Terms ab yehi kehti
  hain, mutlaq dawa nahi.
- **18 saal ki koi jaanch nahi hoti.** Customer se tareekh-e-paidaish maangi hi
  nahi jati. Terms ab saaf kehti hain ke yeh aap ki tasdeeq hai, hamari jaanch
  nahi.
- §8 ki "poori fehrist" adhoori thi — Apple, Unsplash aur Google ki tile service
  chhoot gaye the.
- §12 dono taraf se adhoora tha: kuch cheezein code mitta hai jo likhi nahi
  thin, aur kuch reh jati hain jo "kya reh jata hai" mein nahi thin — trip chat
  ke paighaam, dispute ki evidence files, emergency reports ke coordinates.
- Trip ke ping mein `permission_status` bhee jata hai, woh likha nahi tha.
- Driver ka **safety score** customer ko dikhta hai aur yeh tay karta hai ke trip
  kis ko pehle bheji jaye. Aaj woh sab ka ek hi hai aur koi code usay badalta
  nahi — magar "kuch bhee aap ko score nahi karta" ab is tafseel ke sath likha
  hai.
- §13 ka dawa ke kaghazat sirf verification staff dekhta hai — ghalat tha.
  Customer ko driver ki tasweer aur gaari ki tasweer dikhai jati hai (yeh theek
  hai), aur dispute staff ko evidence. Ab yeh likha hai.

## 8. Janch jo ki gayi

- **Markdown renderer** ko Python mein port kar ke chhon dastawezat par chalaya:
  koi unconverted `**`, koi khali paragraph, list/table ke tag barabar.
- **Front matter ka crash**: reviewer ne pakra ke `---\n---\n` par
  `ArgumentOutOfRangeException` aata tha — yani ek wakeel do lines mita de to
  `/privacy` par **500**, us URL par jo Google Play khud dekhta hai. Theek kar ke
  saat adversarial inputs par dobara chalaya, sab saaf.
- **Account deletion ka SQL asal PostgreSQL par** chalaya — ek driver, gaari,
  do documents, ek vehicle document aur ek presence row seed kar ke. Natija:
  har personal column NULL, 0 documents, 0 presence rows, aur collect query ne
  teenon file URLs deletion se pehle theek nikaale.
- **`check_legal_sync.py`** ki teen failure paths azmaayin: placeholder reh jana,
  dono zabanon ka version alag hona, aur governing flag ghalat hona — teenon
  pakri gayin.
- Dono zabanein renderer mein **bilkul ek jaise block structure** deti hain
  (81/81, 62/62, 17/17) — is se pata chalta hai ke tarjuma shakal mein poora hai.
- `check_syntax.sh` → SYNTAX ERRORS: 0. `audit_structure.py` → AUDIT CLEAN.
  `check_imports.py` aur `check_const_colours.py` saaf.
- Render ki hui policy ka page browser mein khol kar dekha.

**Flutter SDK aur .NET 10 SDK yahan nahi hain**, is liye `flutter analyze` aur
`dotnet build` main nahi chala saka. Apni machine par pehle yeh dono chala lein.

## 9. Do cheezein jo aap ke faisle ki hain

**`_accepted` default `true` hai** (`login_screen.dart:38`) — yani terms wala
checkbox pehle se laga hua aata hai. Kai jurisdictions mein razamandi "pehle se
lagi hui" nahi honi chahiye. Aap ne kehne ko nahi kaha, is liye maine nahi chhua
— bolein to `false` kar doon.

**`pricing.quote.required` abhi `false` hai.** Jab nayi app build sab ke paas
pohanch jaye, isay `true` kar dein — tab fare ki hadd har request par lagu
hogi, aur Terms ka §4 bina kisi shart ke sach ho jayega.
