# Phase 20 Release Checklist

## Builds
- [ ] API restore and publish pass
- [ ] Admin `npm ci` and `npm run build` pass
- [ ] Flutter `flutter analyze`, tests and web build pass

## Environment
- [ ] Unique JWT signing key configured
- [ ] OTP and identity hash secrets configured
- [ ] Development OTP disabled
- [ ] CORS origins restricted
- [ ] Swagger disabled or intentionally protected
- [ ] Upload volume mounted at `/app/uploads`

## Database
- [ ] Backup completed
- [ ] Migration 022 applied
- [ ] Restore rehearsal completed
- [ ] Expired seat holds and OTP cleanup verified

## Regression
- [ ] Customer request to completed trip
- [ ] Driver offer, pickup, boarding PIN and destination
- [ ] 2-wheel, 3-wheel and 4-wheel filters
- [ ] Tourism package approval, booking and completion
- [ ] Payment, refund, wallet and payout
- [ ] Rating, complaint and dispute
- [ ] SOS, trusted contact and Admin safety workflow
- [ ] Admin bookings, operations, packages, finance and reports

## Launch
- [ ] Demo data isolated or removed
- [ ] Real support and emergency contacts configured
- [ ] Privacy policy and terms published
- [ ] Monitoring and alerts enabled
- [ ] Soft launch completed
- [ ] Public launch approved
