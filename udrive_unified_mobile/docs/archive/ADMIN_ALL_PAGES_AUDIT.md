# Admin page endpoint audit

- **advisories**: `/api/v1/admin/operations/advisories`
- **audit**: `/api/v1/admin/operations/audit-logs`
- **bookings**: `/api/v1/admin/executive/bookings`
- **customers**: `/api/v1/admin/operations/users`, `/api/v1/admin/operations/users/`, `/api/v1/admin/users`, `/api/v1/admin/users/`
- **destinations**: `/api/v1/admin/operations/destinations`
- **diagnostics**: `/api/v1/admin/executive/diagnostics`
- **disputes**: `/api/v1/admin/disputes`, `/api/v1/admin/disputes/`, `/api/v1/admin/disputes/dashboard`
- **drivers**: `/api/v1/admin/operations/drivers`
- **executive-operations**: `/api/v1/admin/executive/operations/live`
- **finance**: `/api/v1/admin/finance/`, `/api/v1/admin/finance/dashboard`
- **live-tracking**: `/api/v1/tracking/admin/`, `/api/v1/tracking/admin/active`
- **login**: No API endpoint
- **marketplace**: `/api/v1/admin/packages/`, `/api/v1/admin/packages/pending`
- **notifications**: `/api/v1/admin/operations/notifications/broadcast`
- **operations**: `/api/v1/admin/trip-operations`, `/api/v1/admin/trip-operations/`
- **packages**: `/api/v1/admin/packages/`, `/api/v1/admin/packages/pending`, `/api/v1/admin/tour-marketplace/packages`
- **payments**: `/api/v1/admin/operations/payments`, `/api/v1/admin/operations/payments/`
- **reports**: `/api/v1/admin/executive/finance/reconciliation`, `/api/v1/admin/executive/reports/daily`
- **ride-requests**: `/api/v1/admin/operations/ride-requests`
- **routes**: `/api/v1/admin/operations/routes`
- **safety**: `/api/v1/admin/safety/dashboard`, `/api/v1/admin/safety/emergencies`, `/api/v1/admin/safety/emergencies/`
- **settings**: `/api/v1/admin/operations/settings`
- **support**: `/api/v1/admin/operations/tickets`, `/api/v1/admin/operations/tickets/`
- **vehicles**: `/api/v1/admin/operations/vehicles`
- **verification**: `/api/v1/admin/verification/`, `/api/v1/admin/verification/drivers`, `/api/v1/admin/verification/drivers/`, `/api/v1/admin/verification/vehicles`, `/api/v1/admin/verification/vehicles/`

Pages checked: 25
All referenced endpoint families are present in the API controllers. Runtime schema compatibility is handled by migration 021.