# Phase 13 API Testing Checklist

- [ ] Finance dashboard returns HTTP 200 for SuperAdmin/Admin/FinanceOfficer.
- [ ] Driver finance endpoint denies Customer tokens.
- [ ] Completing an assigned booking creates exactly one earning and wallet credit.
- [ ] Repeating completion/reconcile does not create duplicate earning.
- [ ] Commission amount and net amount reconcile to gross fare.
- [ ] Payout greater than available balance is rejected.
- [ ] Second active payout request is rejected.
- [ ] Stale wallet or payout version returns HTTP 409.
- [ ] Paid payout moves pending balance to paid balance.
- [ ] Rejected/failed payout restores available balance.
- [ ] Refund greater than paid amount is rejected.
- [ ] Completed refund updates payment refund amount/status.
- [ ] Final payout/refund cannot be edited.
- [ ] Only SuperAdmin can create commission rules or adjustments.
- [ ] Every payout/refund/adjustment action creates an audit log.
- [ ] Admin Finance page uses live API data and displays empty/error/loading states.
- [ ] Driver earnings screen loads live wallet activity and submits payout request.
