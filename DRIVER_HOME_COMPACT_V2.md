# Driver Home Compact V2

Updated 2026-08-15.

## Driver home UX
- Removed duplicate Online/Offline switch from the Driver Home body. Use the existing top menu control.
- Replaced the large dashboard header with a compact greeting + nearby request count.
- Removed the permanent My Fare Offers section from the Driver Home.
- Removed the continuous searching progress indicator from the empty state.
- Nearby requests continue to refresh in the background every 5 seconds; GPS presence continues every 15 seconds.

## Fare submission behavior
- After a Driver submits a fare, a compact Fare Sent card remains visible for 10 seconds.
- The card shows the route, Driver fare, and countdown.
- If the Customer approves during that window, the card changes to APPROVED / LIVE.
- After 10 seconds the temporary card disappears and the Driver Home resumes the normal nearby request queue.
- If the same Customer request is still open, it can appear again as a fresh opportunity after the 10-second Driver cooldown.

## Backend queue rule
- Rejected requests remain hidden for that Driver.
- Offered requests are hidden from the same Driver for 10 seconds only.
- After that cooldown, if the request is still open and its pickup is within 5 KM, it is eligible to appear again.
- Existing active-trip rule remains: next rides unlock only within 1 KM of the current destination and still require a pickup within 5 KM.
