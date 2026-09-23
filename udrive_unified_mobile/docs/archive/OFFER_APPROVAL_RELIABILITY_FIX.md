# Offer Approval Reliability Fix

- Driver-facing fare status remains a 20-second UI window.
- Instant driver offers now keep a hidden server validity/grace window so network polling does not invalidate a fare while it is visible to the customer.
- Customer receives a full 10-second decision window starting when the offer first reaches that device.
- While Approve is in progress, the customer auto-timeout cannot decline the same offer.
- Selection endpoint includes a short network grace for an in-flight approval request.
- Existing post-approval Driver Confirmed / live tracking flow is unchanged.
