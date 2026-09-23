# Customer multi-driver fare flow

- City-to-City no longer auto-selects a Driver.
- Customer offer screen polls every 2 seconds and displays multiple Driver fare cards on one screen.
- Each card displays large PKR fare, Driver name, vehicle/model/year, registration, GPS distance from pickup, server-calculated ETA, rating, Approve and Reject.
- Customer decision window is 10 seconds from when the offer first appears on the Customer device.
- Driver offer remains valid on the backend for 20 seconds to absorb network/polling delay.
- Reject immediately expires that Driver offer for this request.
- Approve immediately creates the booking and opens Driver-approved/live tracking flow.
- Driver ETA is calculated server-side from latest Driver GPS to pickup using a practical city-speed estimate instead of being manually entered by Driver.
- A Driver who has just offered is suppressed from seeing the same ride as new for 20 seconds.
