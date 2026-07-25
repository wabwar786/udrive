# Database Changes

Migration `009_phase13_finance_wallets.sql` is additive.

New tables:
- `commission_rules`
- `driver_wallets`
- `driver_earnings`
- `driver_wallet_entries`
- `driver_payout_requests`
- `refund_requests`
- `financial_adjustments`

Added safe columns/indexes on `payments` for idempotency, refund totals, and finance review metadata.

A PostgreSQL trigger calls `udrive.ensure_driver_earning(booking_id)` when a booking first changes to `Completed`. The booking remains the source of truth for gross fare. The selected commission rule is resolved server-side, and only one earning can exist per booking.
