# UDrive — Admin Guide / Admin ki Guide

**Every module of the admin portal, in English and Roman Urdu.**
**Admin portal ka har module, English aur Roman Urdu dono mein.**

> English first, Roman Urdu underneath in *italics*.
> The portal itself is in English, so every menu name here is written exactly as it appears on screen.
> *Portal khud English mein hai, is liye har menu ka naam waise hi likha hai jaise screen par hai.*

---

## The menu, group by group / Menu, group ke hisaab se

| Group | Screens |
|---|---|
| **DAILY OPERATIONS** | Overview · Ride requests · Bookings · Operations & dispatch · Live tracking · Verification · Car rentals · Driver top-ups |
| **PEOPLE & FLEET** | Drivers · Customers · Vehicles |
| **TOURISM** | Tour packages · Destinations · Hotels & approvals · Routes · Road advisories |
| **PRICING & MONEY** | Pricing & fares · Fare zones · Fuel prices · Route insights · Finance & settlements · Legacy payments |
| **GROWTH** | Campaigns · Launch cities |
| **TRUST & SAFETY** | Safety incidents · Fraud review · Complaints & disputes · Support tickets |
| **REPORTS** | Executive operations · Reports & reconciliation · Audit log |
| **SETUP** | Services · Driver updates · Notifications · Settings · Map places · Address search · Data management · Diagnostics · Help |

The groups are ordered by how often a screen is opened, not by which table it reads. DAILY OPERATIONS is what you work every morning, in the order the queues should be cleared. SETUP is what you configure once and leave alone.

*Groups is tarteeb mein hain ke kaunsi screen kitni dafa kholi jati hai, na ke kaunsi table parhti hai. DAILY OPERATIONS har subah ka kaam hai, usi tarteeb mein jis mein qatarein saaf honi chahiyein. SETUP aik dafa set kar ke chhor dene wali cheez hai.*

---

# DAILY OPERATIONS

## Overview
The day in one screen. Start here, then work the queues below in order.
*Aik screen mein poora din. Yahan se shuru karein, phir neeche ki qatarein tarteeb se.*

## Ride requests
Live requests and the offers drivers have sent against them.
- A request with no offers after a while means no verified driver is online nearby. That is a supply problem, not a bug.
- *Kuch dair baad bhi jis request par koi offer nahi, us ka matlab qareeb koi verified driver online nahi. Yeh supply ka masla hai, kharabi nahi.*

## Bookings
Every booking and its status history. **Read the status history before either side's account of events** — it is the only record neither party wrote.
*Har booking aur us ki status history. **Kisi bhi taraf ki baat sunne se pehle status history parhein** — yeh wahid record hai jo kisi fareeq ne nahi likha.*

## Operations & dispatch
Assigning a driver by hand, sending offers, changing a trip's status, rescheduling.
- Overriding a status is logged with your name. Use it when the app and reality disagree, and write why.
- *Status override aap ke naam se log hota hai. Jab app aur haqeeqat alag hon tab istemal karein, aur wajah likhein.*

## Live tracking
Where vehicles are right now.

## Verification
The queue that decides whether a driver can work at all.
1. Open the driver, view each document, approve or reject.
2. **A rejection must say why.** The driver sees your reason and uploads again — a bare rejection produces the same photo twice.
3. Approving sets `approved_at`, which the "new driver" segment and the founding window both read.

*1. Driver khol kar har dastavez dekhein, manzoor ya reject karein.*
*2. **Reject karte waqt wajah likhna lazmi hai.** Driver aap ki wajah parh kar dobara bhejta hai — bina wajah reject se wohi tasveer dobara aati hai.*
*3. Manzoori `approved_at` set karti hai, jise "naya driver" segment aur founding window dono parhte hain.*

## Car rentals
Rentals running now, starting this week, advance collected, cancellations.
- The **security deposit is held by the owner, not by the platform.** The portal records the number; it does not hold the money.
- You see **ticks** that the customer's CNIC and licence exist — not the images. Looking at them would make the platform a party to a check its own disclaimer says it does not perform.
- *Cancelling here affects both sides and is recorded against whoever cancelled.*

*- **Security deposit gaari ke malik ke paas hota hai, platform ke paas nahi.** Portal sirf raqam likhta hai, paisa nahi rakhta.*
*- Aap ko sirf **nishan** dikhte hain ke customer ki CNIC aur licence mojood hain — tasveerein nahi. Unhein dekhna platform ko us tasdeeq ka fareeq bana deta jis se us ka apna disclaimer inkaar karta hai.*
*- Yahan se cancel karna dono taraf par asar daalta hai aur cancel karne wale ke naam likha jata hai.*

## Driver top-ups
Wallet top-ups waiting for verification. Match the reference against the bank before approving.
*Wallet top-ups jo tasdeeq ke muntazir hain. Manzoori se pehle reference bank se mila lein.*

---

# PEOPLE & FLEET

## Drivers
Every driver, their verification status, rating, trips, safety score and vehicle count.

## Customers
Every customer account and its history.

## Vehicles
Every vehicle, its category, its approval status, and which driver it belongs to.
- A vehicle that is not approved cannot be used for a ride, a tour or a rental.
- *Jo gaari manzoor nahi, woh na ride, na tour, na kiraye ke kaam aati hai.*

---

# TOURISM

## Tour packages
Packages waiting for approval and packages running. Check the route, the inclusions and the cancellation rule before approving — customers pay against what is written there.
*Manzoori ke muntazir aur chalte huay packages. Manzoori se pehle route, sahulaat aur cancel ka usool dekh lein — customer usi likhe par paisa deta hai.*

## Destinations · Routes · Road advisories
The map of what UDrive covers. An advisory reaches drivers and customers both — write it as a fact, with a date.
*UDrive ka naqsha. Advisory driver aur customer dono tak jati hai — use haqeeqat ki tarah, tareekh ke sath likhein.*

## Hotels & approvals
Hotel listings and the approvals they need.

---

# PRICING & MONEY

## Pricing & fares · Fare zones · Fuel prices · Route insights
How a fare is calculated: the zone, the difficulty factor, the fuel price of the day, and the rules on top.
- Changing a rule changes future quotes only. Quotes already given stand.
- *Rule badalne se sirf aage ke quotes badalte hain. Jo quote diye ja chuke woh waise hi rehte hain.*

## Finance & settlements
What is owed to whom, and what has been paid.

## Legacy payments
The older payment records. Read-only in practice.

---

# GROWTH

## Campaigns
**Every driver reward is created here. Before this screen existed, no campaign could be created at all** — everything running was a row a migration had seeded.

1. **New campaign**.
2. **Type** and **Condition** are dropdowns. They are dropdowns because the engine **silently returns 0** for anything outside its lists — no error, no payment. A free-text box would let you create a funded campaign that can never pay anybody.
3. **City** blank means every city.
4. Add **Steps** if the reward is paid in parts. A campaign with steps ignores the single reward above it.
5. **Set a budget.** When it runs out a reward goes `OnHold` rather than disappearing, and the driver is told why.
6. **Saving does not run a campaign.** Press **Start** afterwards.
7. **Paid** shows which driver received what, and when.

*1. **New campaign**.*
*2. **Type** aur **Condition** dropdown hain. Is liye ke engine apni list se bahar har lafz ko **khamoshi se 0** kar deta hai — na error, na payment. Azad text box ka matlab hota: campaign ban gayi, budget lag gaya, aur kisi ko kabhi kuch na mila.*
*3. **City** khaali chhorne ka matlab har shehar.*
*4. Reward qiston mein dena ho to **Steps** daalein. Steps wali campaign oopar wala single reward istemal nahi karti.*
*5. **Budget zaroor daalein.** Khatam hone par reward `OnHold` hota hai, ghayab nahi, aur driver ko wajah bata di jati hai.*
*6. **Save karne se campaign chalti nahi.** Baad mein **Start** dabayein.*
*7. **Paid** dikhata hai kis driver ko kya mila aur kab.*

**The seven types the engine measures / Engine sirf yeh saat types naapta hai**
`WelcomeBonus` · `DailyMission` · `PeakHourReward` · `WeeklyReward` · `Referral` · `Reactivation` · `FoundingBenefit`

**The eleven conditions / Gyarah conditions**

| Condition | What the number means |
|---|---|
| `AccountVerified` | Documents approved — use 1 |
| `ProfileCompleted` | Profile filled in — use 1 |
| `VehicleApproved` | At least one vehicle approved — use 1 |
| `FirstRide` | Any completed ride — use 1 |
| `CompletedRides` | Number of completed rides in the period |
| `OnlineSeconds` | Seconds online (1 hour = 3600) |
| `OnlineSessions` | Separate days online in the period |
| `AcceptanceRate` | Percentage, 0–100 |
| `ReferralVerified` | Invited drivers whose documents were approved |
| `ReferralFirstRide` | Invited drivers who completed a ride |
| `ReferralActive` | Invited drivers who became active |

**Careful / Khayal rakhein**
- Changing a reward amount does not change rows already paid. The old amount stands on old awards.
- *Reward ki raqam badalne se woh rows nahi badalti jo pay ho chuki hain. Purani qeemat purane awards par rehti hai.*
- Reordering steps is safe — the page sends each step's id back. **Deleting a step cannot be undone.**
- *Steps ki tarteeb badalna mehfooz hai — page har step ki id wapis bhejta hai. **Step delete karna wapis nahi hota.***

**Reactivation needs no new code.** The engine has measured the `Reactivation` type and the `Inactive` segment (14 days without a ride) since day one — there was simply no way to create such a campaign. Now there is.
***Reactivation ke liye koi naya code nahi chahiye.** Engine `Reactivation` type aur `Inactive` segment (14 din bina ride) pehle din se naapta tha — sirf campaign banane ka rasta nahi tha. Ab hai.*

## Launch cities
A city, its stage, its founding numbers, and which zone is expected to be busy when.

**Stage — only four are valid / Marhala — sirf chaar jaiz hain**
`BuildingNetwork` · `CampaignSoon` · `CampaignActive` · `PublicLaunch`
"Live" is **not** one of them. The database rejects anything else outright.
*"Live" in mein **shaamil nahi**. Database baqi har lafz ko reject kar deta hai.*

**Founding numbers / Founding numbers**
- Numbers run **per city** and are given from the panel on this page.
- The number comes from a single statement, so two admins pressing at the same moment produce **#74 and #75**, not two #74s.
- **A founding number is not taken back.** Confirm the driver first.
- *Numbers **shehar ke hisaab se** chalte hain aur isi page ke panel se diye jate hain.*
- *Number aik hi statement se nikalta hai, is liye do admin aik waqt par dabayein to **#74 aur #75** bante hain, do #74 nahi.*
- ***Founding number wapis nahi liya jata.** Pehle driver confirm kar lein.*

**Expected demand / Expected demand**
- This is where "High demand — Domel" on the driver's home screen comes from.
- **Choosing no day means every day.**
- A window needs a pricing zone, so create zones under **Fare zones** first.
- *Driver ke home screen par "High demand — Domel" yahin se aata hai.*
- ***Koi din na chunne ka matlab har din.***
- *Window ke liye pricing zone chahiye, is liye pehle **Fare zones** mein zone banayein.*

**Careful / Khayal rakhein**
- Switching a city off stops measuring its drivers. Check running campaigns first.
- *Shehar band karne se us ke driver naapne band ho jate hain. Pehle chalti campaigns dekh lein.*

---

# TRUST & SAFETY

## Safety incidents
**This queue comes before everything else in the portal.**
1. Treat every alert as real until you have spoken to someone.
2. Phone the customer first, then the driver.
3. Record what you did and when. The log is what any later review reads.

***Yeh qatar poore portal mein sab se pehle aati hai.***
*1. Har alert ko asli samjhein jab tak kisi se baat na ho jaye.*
*2. Pehle customer ko phone karein, phir driver ko.*
*3. Jo kiya aur jab kiya, likh dein. Baad mein jo review hoga woh yehi log parhega.*

## Fraud review
Signals the system raised. **Nothing happens to a driver until somebody here decides.**

**The two signals / Do signals**

| Signal | What it is |
|---|---|
| `MockLocation` | The phone itself told the server its position was faked. **Android reports this — it is not our inference.** |
| `ImpossibleSpeed` | Two heartbeats in one session put the driver further apart than any road allows: **above 120 km/h.** |

`ImpossibleSpeed` is only raised when all four hold: both positions known, the gap between 20 and 150 seconds, the distance over 400 metres, and the speed over 120 km/h. A driver who closed the app and travelled is never flagged.

*`ImpossibleSpeed` tabhi uthta hai jab chaaron sharait poori hon: dono location maaloom, gap 20 se 150 second, faasla 400 metre se zyada, aur raftar 120 km/h se oopar. Jo driver app band kar ke safar kare us par kabhi flag nahi lagta.*

**How to decide / Faisla kaise karein**
1. Use the **city and the ride count** shown on the row. The same flag means very different things against 400 rides and against 2.
2. **Confirm** holds every reward this driver has earned but not yet been paid.
3. **Clear** releases them again — unless another confirmed flag is still open.
4. **Always write the reason.** It is what gets read next time.

*1. Row par likhe **shehar aur rides** dekhein. Aik hi flag 400 rides wale aur 2 rides wale par bilkul alag matlab rakhta hai.*
*2. **Confirm** us driver ke woh saare rewards rok deta hai jo kama liye magar abhi mile nahi.*
*3. **Clear** unhein wapis chala deta hai — bashart ke koi doosra confirmed flag khula na ho.*
*4. **Wajah hamesha likhein.** Agli dafa yehi parha jayega.*

**What Confirm does NOT do / Confirm kya nahi karta**
- It does **not** take money back out of a wallet. Clawback is the most expensive argument a launch can have.
- It does **not** block the driver. They keep driving and keep earning fares.
- It does **not** release a reward held for a different reason — a budget hold stays a budget hold.

*- Wallet se paisa **wapis nahi** leta. Clawback launch ka sab se mehnga jhagra hai.*
*- Driver ko **block nahi** karta. Woh gaari chalata aur kiraya kamata rehta hai.*
*- Kisi aur wajah se ruka reward **nahi** chalata — budget ka hold budget ka hold hi rehta hai.*

## Complaints & disputes
1. Read the booking status history before either account of events.
2. Ask both sides. A one-sided decision produces a second dispute.
3. Write the outcome plainly.

*1. Dono taraf ki baat se pehle booking ki status history parhein.*
*2. Dono se poochein. Aik tarfa faisla doosri shikayat paida karta hai.*
*3. Nateeja saaf likhein.*

## Support tickets
Ordinary questions from both apps. Answer in the language the person wrote in.
*Dono apps ke aam sawalat. Jis zuban mein likha gaya ho usi mein jawab dein.*

---

# REPORTS

## Executive operations
The numbers a decision is made on.

## Reports & reconciliation
What the books say against what the wallets say.

## Audit log
Who did what, and when. Every override and every manual change is here under a name.
*Kis ne kya kiya, kab kiya. Har override aur har hath se ki gayi tabdeeli yahan naam ke sath mojood hai.*

---

# SETUP

## Services
Which services are switched on.

## Driver updates
What drivers are told, by city.
1. Choose the city and the category, write the title and the body, press **Publish**.
2. **Leaving the city blank means every city** — a commission change is written once and reaches the whole country.
3. A published update can be edited by clicking its row, or deleted.
4. **Write only what a driver can act on today.**

*1. Shehar aur category chun kar title aur tafseel likhein, phir **Publish**.*
*2. **Shehar khaali chhorne ka matlab har shehar** — commission ki tabdeeli aik dafa likhne se poore mulk tak jati hai.*
*3. Likhi hui update row par click kar ke badli ja sakti hai, ya delete.*
*4. **Sirf woh baat likhein jis par driver aaj kuch kar sake.***

## Notifications
Platform-wide notification settings.

## Settings · Map places · Address search · Data management · Diagnostics
Configuration, set once and left alone. **Data management** can delete real records — read what a button says before pressing it.
*Configuration, aik dafa set kar ke chhor dein. **Data management** asli record mita sakta hai — button dabane se pehle us par likha parh lein.*

## Help / How to use
The same guide as this document, built into the portal, in Roman Urdu and English. The Guide button at the top of every screen opens it at that screen.
*Yehi guide portal ke andar bhi hai, Roman Urdu aur English mein. Har screen ke oopar Guide ka button use usi screen par khol deta hai.*

---

## The one rule that runs through all of it / Aik usool jo har jagah chalta hai

**The system raises signals. It does not punish.** A mocked position, an impossible jump, a budget running out — each writes a row and waits for a person. A launch incentive that bans drivers on its own will eventually ban an honest one, and that driver tells every other driver in the city.

***System nishandahi karta hai, saza nahi deta.** Jhooti location, na-mumkin chhalang, budget ka khatam hona — har aik aik row likhta hai aur insaan ka intezar karta hai. Jo launch khud-ba-khud driver band karne lage, woh aik din kisi imandaar ko band karega — aur woh driver shehar ke har doosre driver ko bataega.*
