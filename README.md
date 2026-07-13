# UDrive UI — Phase 1

A functional frontend starter for UDrive, a tourism-focused ride and tour package platform for Azad Kashmir.

## Included projects

- `customer_app/` — Flutter customer application
- `driver_app/` — Flutter driver application
- `admin_portal/` — Next.js Super Admin portal

## Current functionality

### Customer app
- English and Urdu switching with RTL support
- Ride request form with validation
- Suggested fare and customer offer
- Simulated driver counteroffers
- Driver comparison and booking confirmation
- Tour package discovery and package details
- Trip history and profile screens

### Driver app
- English and Urdu switching with RTL support
- Online/offline dashboard
- Ride request list with accept and counteroffer actions
- Driver-created package list
- Multi-step package creation form
- Earnings and profile screens

### Admin portal
- Responsive operations dashboard
- Booking, driver and package summaries
- Package approval workflow using dummy data
- Live operations visual panel
- English/Urdu language toggle

## Run the Flutter apps

Flutter was not available in the generation environment. On a machine with Flutter installed, first generate the native platform scaffolding:

```bash
./bootstrap_flutter_projects.sh
```

Then run either app:

```bash
cd customer_app
flutter run
```

```bash
cd driver_app
flutter run
```

## Run the admin portal

```bash
cd admin_portal
npm install
npm run dev
```

Then open `http://localhost:3000`.

## Architecture note

The apps intentionally avoid third-party state-management and mapping packages in Phase 1. Dummy repositories can later be replaced with REST/Firebase services without changing the primary screen structure.

## Railway deployment

Use the included `RAILWAY_DEPLOYMENT.md` guide. Dockerfiles are provided for all three services so the monorepo can be deployed directly from GitHub to Railway.
