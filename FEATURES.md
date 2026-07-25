# Driver Marketplace Features

- Driver dashboard shows pending Customer ride requests from the live database.
- Open requests load before optional package data for a faster Driver dashboard.
- Driver sees Customer fare, route, date/time, passenger count, luggage and requested vehicle category.
- Driver selects one of their verified vehicles with sufficient passenger capacity.
- Driver submits their own fare, pickup ETA and optional message.
- Request response window is one hour from creation.
- Driver cards show a live countdown.
- Requests from a previous Pakistan calendar date are automatically expired and hidden.
- If no Driver sends an offer within one hour, the request becomes `NoDriverAccepted`.
- If one or more offers exist when the response window closes, the request becomes `OffersReceived` and is removed from the open Driver queue.
- Driver offers remain selectable until the scheduled pickup time unless otherwise closed.
- Customer offer screen shows a clear no-Driver outcome instead of waiting indefinitely.
