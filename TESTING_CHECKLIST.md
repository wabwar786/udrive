# Testing Checklist

## API

- [ ] API builds successfully.
- [ ] Migration 012 is applied.
- [ ] Eligible request response contains `customerName`.
- [ ] Reject endpoint returns HTTP 200.
- [ ] Rejected request no longer appears for the rejecting Driver.
- [ ] Rejected request remains visible to another eligible Driver.
- [ ] Accepted/sent-offer request no longer appears for the same Driver.
- [ ] Customer can still see the offer.

## Driver UI

- [ ] Header shows Good morning/afternoon/evening and Driver first name.
- [ ] Profile icon opens Driver Profile.
- [ ] Online/offline switch is in the app bar.
- [ ] No old hero, metric blocks or vehicle-readiness section.
- [ ] Customer request cards are compact.
- [ ] Customer initials/name, pickup, destination, fare and actions are visible.
- [ ] Accept opens fare sheet.
- [ ] Reject removes card.
- [ ] Latest assignment renders correctly.
- [ ] Four colorful Driver tools work.
- [ ] Create Package opens package creation.
- [ ] Driver packages show status.
