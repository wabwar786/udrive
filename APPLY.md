# Phase 3 — fare system. How to apply.

Build label goes to **rev 145**. Three repos are touched; 40 files.

## 1. Copy

Extract over `D:\Softwares\Github\uDrive\`, keeping the folder structure —
`udrive_api\`, `udrive_unified_mobile\` and `admin_portal\` all sit at that
level. Replace existing files.

Nothing is deleted this time.

## 2. Set QUOTE_SIGNING_SECRET in Railway — before deploying

Railway → udrive-api → Variables:

```
QUOTE_SIGNING_SECRET = <32+ random characters, your own>
```

**The API will not start without it** once `ENFORCE_PRODUCTION_SECURITY` is on,
and that is deliberate. A fare quote is signed with this key; anyone who can
forge one sets their own floor, so it is the same class of secret as
`JWT_SIGNING_KEY`. Generate it locally, never in a chat.

## 3. Deploy

API first (five migrations run themselves at startup, 049 through 053), then
the portal, then push the app and let CI build.

Nothing changes for customers on the day it lands. Every new multiplier ships
at the value that reproduces today's arithmetic — that is tested, see
FARE_SYSTEM.md.

## 4. Then, in this order

`FARE_SYSTEM.md` has the detail. In short:

1. Pricing → **Fuel prices**: record today's petrol and diesel, press
   *Set to today's prices*.
2. Pricing → **Fare zones**: seven zones are seeded **inactive** with
   approximate coordinates written from memory. Check each on a map, fix the
   centre and radius, read the *on a long trip* figure, then activate.
3. Pricing → the rule editor: decide the **base fare** question. With the
   seeded rates every car ride inside Muzaffarabad costs exactly 1,600, because
   the meter does not clear the minimum until about 23 km.
4. Once the new app build has rolled out: set `pricing.quote.required` to
   `true`.
5. Leave surge off until there are enough drivers online for it to mean
   anything.

## 5. What to test

- Book a ride: the fare box opens at the server's number and will not go below
  it, by stepper or keypad.
- Offer below the minimum from a patched client → refused,
  "The lowest fare for this trip is PKR …".
- Driver types a number below the floor → refused, and the floor is shown in
  the field's helper text before he types.
- Driver types the customer's number exactly → the offer shows as accepted, not
  countered.
- A fixed `seat_fares` route → neither side can move the fare.
- Old app build (no quote) → still books, while
  `pricing.quote.required` is false.

## 6. Known and deliberate

- `udrive_route_flow_screen` quotes at submit rather than live. If the quote
  cannot be had at all, the request goes through unbanded — refusing to let
  someone book because a pricing lookup failed would be worse than the problem.
  The server still applies its own rules.
- That screen also said "Coaster" where every rate card says "Coster". Fixed,
  which means ride requests from it now carry the same category as the rest of
  the system. Driver matching is by seat capacity, not category, so nothing
  else moves.
- Surge is measured from `driver_presence_locations`, which only sees drivers
  with the app open. Until that is a real population the sample guards keep the
  multiplier at 1.0 — which is why it ships off.
