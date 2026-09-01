# UDrive Admin Portal — Guide

Generated from `admin_portal/app/lib/guide-content.ts`, which is the same
content the portal shows behind the **Guide** button and on **/help**.
Edit that file, not this one, or the two will disagree.

## Start here

What the portal is, how a booking moves through it, and the rules that  apply everywhere.

### How a ride actually flows
`/`

The path every ride takes, so you know which screen owns which stage.

1. A Customer sets a pickup and destination, picks a vehicle, and names a fare. That creates a ride request — visible under Ride requests.
1. Drivers within range see it and answer with their own fare. Each answer is a Driver offer.
1. The Customer accepts one offer. That creates a booking and assigns the Driver — visible under Bookings.
1. The Driver drives to the pickup, takes the trip OTP from the Customer, and starts the trip. Progress is under Operations & dispatch and Live tracking.
1. The trip completes, money settles under Finance, and either side may leave a rating.

**Watch out**

- A ride request is not a booking. Cancelling a request costs nothing; cancelling a booking affects a Driver who has already committed and may already be driving.
- The Customer names the fare and the Driver answers it. The admin sets the rate that seeds that first figure — never the final price of an individual ride.

### Overview
`/`

The day at a glance, and what is waiting for someone.

1. Read the headline counts first — active trips, pending verifications, open disputes.
1. Anything with a number that should be zero is your queue for the day.
1. Open the record before acting. Never act from a dashboard count alone.

### Roles and what each can do
`/`

The portal restricts by role. Knowing yours saves guessing at a locked button.

1. SuperAdmin — everything, including deletion and commission rules.
1. Admin — everything operational: verification, pricing, disputes, refunds.
1. Manager and Operations — day-to-day dispatch, bookings, support. Read access to money.
1. FinanceOfficer — payouts, refunds, reconciliation, and pricing rates.
1. SupportAgent — tickets and lookups. No money, no verification.

**Watch out**

- A button that does nothing usually means your role cannot do it, not that the portal is broken. Check with whoever holds the higher role rather than retrying.

## Operations

Live rides, requests and the dispatch desk.

### Ride requests
`/ride-requests`

Customers who are asking for a ride but do not have one yet.

1. Watch the offers count. A request sitting at zero offers means no Driver has taken the fare.
1. Repeated zero-offer requests in one area usually mean the per-km rate there is too low, or nobody is online. Check Pricing and the online Driver count before assuming a fault.
1. Requests expire on their own. There is nothing to clean up.

### Bookings
`/bookings`

Rides that have a Driver. This is the record of the trip.

1. Search by booking reference, Customer name or phone.
1. Open a booking to see the fare, the Driver, the vehicle and the full status history.
1. The status history is the truth about what happened and when. Read it before believing either side of a dispute.

**Watch out**

- Cancelling here affects a real Driver who may already be driving. Record why.

### Operations & dispatch
`/operations`

The desk for trips in progress.

1. Sort by last activity. The oldest untouched trip is the one most likely to be in trouble.
1. A trip stuck at DriverEnRoute with no GPS for several minutes needs a phone call, not a status change.
1. Change a status by hand only when you have spoken to someone and know the real state.

**Watch out**

- Forcing a status hides the problem instead of fixing it. The Driver app will keep reporting what it sees.

### Live tracking
`/live-tracking`

Where the vehicles are right now.

1. Stale markers mean the Driver app has stopped reporting — usually signal, sometimes a closed app.
1. Use it to answer "where is my ride" calls without phoning the Driver mid-drive.

### Tour packages
`/packages`

Multi-day tour products offered by Drivers.

1. Review a package before it goes live: route, seats, price, what is included.
1. Tour pricing is set by each Driver on their own vehicle, not here.

## People & fleet

Who is allowed to drive, and in what.

### Verification
`/verification`

Approving Drivers and vehicles. The most consequential screen in the portal.

1. Open the submission and check every document against the person: CNIC, licence, registration.
1. Confirm the licence has not expired and the name matches the CNIC.
1. Confirm the vehicle registration matches the vehicle photographs.
1. Approve, or reject with a reason the Driver can act on.

**Watch out**

- An approval puts a stranger in a car with a Customer. Rejecting a good application costs a Driver a day; approving a bad one costs someone much more.
- "Rejected" with no reason is not a decision, it is a wall. Write what has to be fixed.
- A Driver cannot appear on any Customer map until both the Driver is Approved and the vehicle is Verified.

*Roles: SuperAdmin, Admin*

### Drivers
`/drivers`

The Driver roster, their standing and their history.

1. Use it to look up a Driver during a complaint or a support call.
1. Suspension takes a Driver offline immediately and stops new requests reaching them.

**Watch out**

- Suspension is not a warning. It removes someone’s income that day. Use the disputes process for anything short of a safety concern.

### Vehicles and vehicle pictures
`/vehicles`

The fleet, and the photographs Customers see when choosing a vehicle.

1. Upload one clear photograph per category: Car, Bike, Coster, Hiace.
1. Use the same style for all four — same angle, same background — or the picker looks assembled from different apps.
1. A category with no photograph falls back to a plain icon in the app.

**Watch out**

- This is what the Customer judges the vehicle by. A dark or cropped photograph makes a good vehicle look worse than it is.

### Users & access
`/customers`

Customer accounts and portal staff accounts.

1. Create staff accounts with the lowest role that lets them do their job.
1. Remove access the day someone leaves, not at the end of the month.

## Money

What a ride costs, and where the money goes.

### Pricing & fares
`/pricing`

The per-kilometre rate Customers are quoted, and any narrower rules.

1. Set the standard rate for each vehicle in the top grid: rate per km, and a minimum fare.
1. A trip is priced: rate per km × road distance, plus a small per-minute amount, and never below the minimum.
1. For anything narrower — a weekend rate, a rate for one town — add a rule below with days and an area.
1. Use Fare preview before saving. Enter a distance, a time and an area and it shows exactly what a Customer would be quoted, and which rule produced it.

**Watch out**

- Rate per km and minimum fare are different numbers. Putting a minimum fare (say 1,600) into the per-km field prices a 12 km trip at nineteen thousand rupees.
- The most specific active rule wins: an area beats everywhere, a smaller area beats a larger one, named days beat every day.
- Tourism is not priced here. Each Driver sets their own tour rate in the Driver app.
- Coster per-seat routes use fixed route fares, also set on this screen. On a listed route the Customer cannot bid at all.

*Roles: Read: most roles. Change: SuperAdmin, Admin, FinanceOfficer.*

### Finance & settlements
`/finance`

Driver earnings, payouts, refunds and commission.

1. Work payouts from oldest to newest.
1. Match a refund to its booking before approving it.
1. Reconcile completed trips regularly rather than in one large batch.

**Watch out**

- A refund is real money leaving the business. Confirm the booking and the reason first.

*Roles: SuperAdmin, Admin, FinanceOfficer*

### Reports & reconciliation
`/reports`

Totals for a period, for accounting and for decisions.

1. Pick the period first; every figure on the page follows it.
1. Export before a period is edited, so the numbers you quoted can be reproduced.

## Trust & safety

When something goes wrong.

### Safety incidents
`/safety`

SOS alerts and incidents raised from either app.

1. Treat every alert as real until you have spoken to someone.
1. Phone the Customer first, then the Driver.
1. Record what you did and when. The log is what any later review reads.

**Watch out**

- This queue comes before everything else on this page.

### Complaints & disputes
`/disputes`

Disagreements about a trip, a fare or conduct.

1. Read the booking status history before either account of events.
1. Ask both sides. A one-sided decision produces a second dispute.
1. Write the outcome so the next person reading it understands the reasoning without asking you.

### Support tickets
`/support`

Everything that is not an incident or a dispute.

1. Find the booking or user before opening a ticket.
1. Record the exact problem, the time, the screen and what was already tried.

**Watch out**

- Never read technical error text to a Customer or Driver. Describe the problem in their terms and escalate.

### Audit log
`/audit`

Who did what in this portal.

1. Check it before asking a colleague what happened — the answer is usually here.

## Places & content

What Customers see when they search and browse.

### Map places
`/places`

Named pickup and drop points Customers can search.

1. Add the places people actually name — bus stands, hospitals, well-known markets.
1. Set the coordinates on the map, not by typing them, so the pin lands where a vehicle can stop.

### Destinations
`/destinations`

Tourism destinations shown in Explore.

1. Keep photographs current. An out-of-season photograph sets the wrong expectation.

### Routes
`/routes`

Named routes used for tours and Coster services.

1. A route here should match a fixed per-seat fare in Pricing if it is sold by the seat.

### Road advisories
`/advisories`

Warnings shown to Drivers and Customers.

1. Post closures and landslides as soon as they are confirmed.
1. Remove them the moment they clear. A stale advisory trains people to ignore all of them.

### Hotels & approvals
`/hotels`

Hotel listings and the owners who submit them.

1. Check the address, the phone number and the photographs before approving.

### Notifications
`/notifications`

Messages sent to Customers or Drivers.

1. Write the message, choose the audience, and read it once more before sending.

**Watch out**

- A notification cannot be recalled. Every recipient sees it on their phone.

## System

Configuration and health.

### Settings
`/settings`

Portal and platform configuration.

1. Change one thing at a time and check the effect before changing the next.

### Diagnostics
`/diagnostics`

Whether the API, database and maps are healthy.

1. Check here first when several screens misbehave at once. One failing dependency looks like many broken screens.

### Data management
`/data-management`

Bulk data operations.

1. Export before you import. Read what a job will change before running it.

**Watch out**

- Actions here affect many records at once and are not always reversible.

*Roles: SuperAdmin*

