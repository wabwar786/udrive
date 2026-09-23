# Phase 16 — Payments, Wallet and Payout Production Foundation

Implemented as an additive upgrade over Phase 15.

## Included
- Booking payment summary and ledger
- Cash, bank transfer, card, Easypaisa and JazzCash method foundation
- Advance, partial, balance and full payment types
- Idempotent payment creation
- Payment attempt history and failed-payment reason
- Admin/Finance payment confirmation endpoint
- Driver payout account storage with masked identifiers
- Wallet freeze schema foundation
- Refund method and refund idempotency fields
- Customer Flutter payment screen and payment history
- Existing Driver wallet, earnings, payouts, refunds, commission rules and Admin finance workspace preserved

## Migration
`017_phase16_payments_wallet_payouts.sql`

## New endpoints
- `GET /api/v1/payments/booking/{bookingId}`
- `POST /api/v1/payments`
- `PUT /api/v1/payments/{paymentId}/confirm`
- `GET /api/v1/driver/payout-accounts`
- `POST /api/v1/driver/payout-accounts`

## Provider note
Card/Easypaisa/JazzCash provider callbacks still require real provider credentials and webhook configuration. The code deliberately records them as pending until a trusted server-side confirmation is received.
