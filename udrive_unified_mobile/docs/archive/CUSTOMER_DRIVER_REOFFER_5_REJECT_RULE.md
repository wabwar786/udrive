# Customer / Driver re-offer rule

- Reject #1 to #4: same Driver may send same or new fare again for the same ride.
- Every resend appears to the Customer as a fresh offer with a fresh 10-second decision window.
- Reject #5: same Driver is blocked for that specific ride request.
- Driver remains eligible for every other/new ride.
- Automatic 10-second Customer timeout does not increment the five-reject counter.
- Existing 20-second Driver/server offer validity remains unchanged.
