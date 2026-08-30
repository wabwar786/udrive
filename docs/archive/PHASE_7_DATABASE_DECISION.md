# Phase 7 Database Decision

## Selected database

**PostgreSQL 17 with PostGIS 3.5** is the primary system of record.

## Why this is the best fit

- Relational transactions protect seat inventory, whole-vehicle locks, payments and driver-offer selection.
- PostGIS supports nearby-driver searches, route areas, tourist destinations, geofencing and spatial indexes.
- JSONB and arrays provide flexibility for itineraries, inclusions and multilingual tourism metadata without losing relational integrity.
- Railway provides a PostGIS template and private database networking.
- PostgreSQL avoids locking the application into a proprietary mobile database platform.

## Supporting storage later

- Redis: temporary seat holds, live-location cache, distributed locks, rate limits and real-time presence.
- S3-compatible object storage: CNIC/licence/vehicle files, package photos and incident evidence.
- PostgreSQL remains the authoritative database.
