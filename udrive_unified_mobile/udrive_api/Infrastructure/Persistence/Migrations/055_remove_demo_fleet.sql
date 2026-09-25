-- Take the 54-driver demo fleet out of circulation.
--
-- Migration 010 ran automatically on every boot and inserted 54 driver
-- accounts marked Approved and online, with INVENTED average_rating,
-- completed_trips and safety_score, plus 54 vehicles marked Verified. The
-- inserts have been removed from 010, but every database that has already
-- booted still holds the rows and will never re-run 010, because its id is
-- recorded in schema_migrations. This migration is what clears them there.
--
-- WHY DEACTIVATE RATHER THAN DELETE
--
-- Twenty tables carry a foreign key to driver_profiles and more than thirty to
-- users. If anybody — a tester, a customer during a trial, an admin — ever
-- created a booking, an offer, a wallet entry or a dispute against one of
-- these accounts, a DELETE either fails at the first constraint or, worse,
-- invites somebody to "fix" it with a cascade that takes real trip history
-- with it. A hard delete was tried first and did in fact fail: tour_packages
-- references the demo vehicles.
--
-- Flipping the three flags the public query filters on removes them from every
-- customer-facing surface just as completely, keeps referential integrity
-- intact, and is safely re-runnable.
--
-- MarketplacePricingService requires v.status='Verified' AND
-- dp.verification_status='Approved' AND u.status='Approved', so changing any
-- one of them is enough; all three are set so no other query can pick them up
-- either.
--
-- SCOPE: 'demo.%@udrive.local' — the same pattern AdminDataService and
-- MarketplacePricingService use to mean "a seeded demo account". This was
-- 'demo.driver%' at first, which missed the bike and rickshaw accounts that
-- 010's later section seeded under demo.bike01@ and demo.rickshaw01@; those
-- stayed Approved, online and bookable. Matching the codebase's own definition
-- is the only way this stays correct as seed data changes. The
-- Play reviewer account is driver.demo@udrive.local on +923000000001 from
-- 003_seed_catalog.sql — a different address on a different number range. The
-- two extra predicates below make that exclusion explicit rather than leaving
-- it to the LIKE pattern.

-- No BEGIN/COMMIT here. SqlMigrationRunner already opens a transaction per
-- file and records the migration id inside it; a COMMIT in the script commits
-- the runner's transaction early, so the ledger insert would land outside it
-- and the runner's rollback would no longer cover anything after this point.

UPDATE udrive.vehicles v
SET status = 'Suspended',
    updated_at = now()
FROM udrive.driver_profiles dp
JOIN udrive.users u ON u.id = dp.user_id
WHERE v.driver_profile_id = dp.id
  AND u.email LIKE 'demo.%@udrive.local'
  AND u.phone_number <> '+923000000001'
  AND u.email <> 'driver.demo@udrive.local'
  AND v.status <> 'Suspended';

UPDATE udrive.driver_profiles dp
SET verification_status = 'Suspended',
    is_online = false,
    updated_at = now()
FROM udrive.users u
WHERE u.id = dp.user_id
  AND u.email LIKE 'demo.%@udrive.local'
  AND u.phone_number <> '+923000000001'
  AND u.email <> 'driver.demo@udrive.local'
  AND (dp.verification_status <> 'Suspended' OR dp.is_online);

UPDATE udrive.users
SET status = 'Suspended',
    updated_at = now()
WHERE email LIKE 'demo.%@udrive.local'
  AND phone_number <> '+923000000001'
  AND email <> 'driver.demo@udrive.local'
  AND status <> 'Suspended';
