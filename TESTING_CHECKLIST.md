# Testing checklist

1. API `dotnet publish` succeeds without CS0103.
2. Customer submits a new request.
3. Request is stored in `udrive.ride_requests` with `ReceivingOffers`.
4. Login as demo Driver `03109000001`.
5. Open Driver mode > Live Requests.
6. Customer request appears.
7. Verified/Approved demo vehicle is selectable.
8. Driver sends fare offer.
9. Customer offers screen shows the Driver offer.
