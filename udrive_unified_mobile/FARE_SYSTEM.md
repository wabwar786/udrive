# UDrive fare system

Everything about what a trip costs, and where each number lives.

## The short version

The server prices the trip. The customer may offer that price or more, never
less. The driver may counter, but not below the same floor. Nothing in the app
decides a fare any more.

## How a fare is built

```
distance cost = per-km × fuel index × km
time cost     = per-minute × minutes
meter         = base fare + distance cost + time cost
terrain       = meter × zone difficulty
empty return  = distance cost × zone return share × zone difficulty
subtotal      = terrain + empty return
floor         = minimum fare × fuel index × zone difficulty
charged       = max(subtotal, floor)

recommended   = charged × surge
minimum       = charged × (1 + (surge − 1) × 0.5)
maximum       = recommended × 3
```

Everything is rounded **up** to the nearest 5, never to nearest — a fare
rounded down can land below the floor it was just clamped to.

At surge 1.0 the minimum and the recommendation are the same number. One figure
on screen, and the only direction to move it is up.

Per seat: `max(subtotal ÷ seat capacity × 1.35, per-seat floor)`, then × seats.
A published route fare in `seat_fares` replaces all of it and is not negotiable
by either side.

## On the day this ships, nothing changes

Every multiplier defaults to the value that reproduces the old arithmetic:

| | ships as | effect |
| --- | --- | --- |
| `base_fare` | 0 | no flagfall, as before |
| fuel baselines | 0 | indexing off, factor is exactly 1.0 |
| pricing zones | all inactive | every trip priced flat |
| `pricing.surge.enabled` | false | multiplier is exactly 1.0 |
| `pricing.quote.required` | false | an app build that sends no quote still books |

A regression test in the delivery checks this: with all of the above at their
shipped values, every category at every distance quotes exactly what the old
client arithmetic quoted.

## Turning it on, in order

1. **Fuel.** Pricing → Fuel prices. Record today's petrol and diesel, then press
   *Set to today's prices* — that writes the baselines at today's level, so
   nothing moves until the next revision.
2. **Zones.** Pricing → Fare zones. Seven zones are seeded **inactive** with
   approximate coordinates. Open each, check the circle on a map, fix the
   centre and radius, read the *on a long trip* figure, then activate.
   The seeded coordinates are starting points written from memory, not
   surveyed — they must be checked before a zone prices anything.
3. **Base fare.** Pricing → the rule editor. See below.
4. **Require quotes.** Once the new app build has rolled out, set
   `pricing.quote.required` to `true`. Until then a client can still book
   without a quote, which is what keeps older installs working.
5. **Surge.** Leave `pricing.surge.enabled` off until enough drivers keep the
   app open for requests-per-driver to describe anything real.

## The thing worth deciding early

With the seeded rates, the per-kilometre rate does nothing inside a city:

| vehicle | per-km | minimum | clears the minimum at |
| --- | --- | --- | --- |
| Bike | 32 | 250 | 6.8 km |
| Car | 65 | 1,600 | 22.9 km |
| Hiace | 110 | 4,500 | 39.2 km |
| Coster | 160 | 7,500 | 45.5 km |

Muzaffarabad is about six kilometres across, so **every car ride in the city
costs exactly 1,600**. Setting a base fare and lowering the minimum together is
what fixes that:

| distance | today | base 150, minimum 350 |
| --- | --- | --- |
| 2 km | 1,600 | 350 |
| 5 km | 1,600 | 500 |
| 10 km | 1,600 | 850 |
| 20 km | 1,600 | 1,550 |
| 30 km | 2,095 | 2,245 |

Short rides get much cheaper. That is a pricing decision, not a bug fix, which
is why `base_fare` ships at 0 and the numbers are yours to choose.

## Zones compound

Difficulty multiplies the whole meter. The return share is a slice of the
distance cost and is charged through the same terrain, so it carries the
difficulty too. On a long trip almost all of the fare is distance, so the two
together land near `difficulty × (1 + return share)`.

Difficulty 1.30 with a 0.55 return share is **roughly double** the flat fare on
a valley run, not thirty per cent more. The zone editor prints the compounded
figure next to the fields; read that one.

## Route insights

Pricing → Route insights. For each origin zone → destination zone → vehicle it
shows the median fare drivers actually accepted, the median UDrive suggested,
how many requests attracted no offer at all, and the gap between the two fares
as a suggested percentage.

Read the **no-offer** column first. A route where the suggestion is close to the
agreed fare but a third of requests get no offer is priced below what a driver
will get out of bed for — and the median cannot show that, because the rides
nobody accepted are not in it.

Nothing on that screen changes a price. It reports; you decide.

There is deliberately no model and no AI in the fare path. When a driver asks
why a fare is what it is, the answer has to be a list of numbers he can check.

## Where the guards are

- **Quote token** — HMAC-SHA256 over the band, the trip, the vehicle, the seat
  count and the customer's own id. Valid 15 minutes, single use (unique index
  on `ride_requests.quote_id`), and refused if the booked trip is more than
  500 m from the quoted one at either end.
- **`QUOTE_SIGNING_SECRET`** — set this in Railway. The API refuses to start if
  it is shorter than 32 characters, and the production check refuses the
  development default. A forged quote sets its own floor.
- **Distance** — the claimed road distance is checked against the straight line
  between the two points: never shorter, and no more than 4× (mountain roads
  switchback, and Leepa is reached over a pass).
- **Driver offers** — held to the same minimum as the customer, and to the same
  maximum. On a published route fare those are the same number.
- **Raise fare** — still strictly upward, and now also capped at the quoted
  maximum.

## Commission

One percentage, `driver.commission.percentage`, read by both the wallet debit
at TripStarted and the earnings ledger at Completed. The 15% default that used
to be compiled into the ledger trigger — and the seeded `commission_rules` row
that kept it reachable — are both gone. Rows already written keep the
percentage they were written with; no history is restated.
