-- The Customer could never accept a Driver's offer.
--
-- `SelectDriverOfferAsync` records the outcome against the Driver's decision on
-- that request:
--
--     INSERT INTO udrive.driver_ride_request_decisions (..., decision, ...)
--     VALUES (..., 'Accepted', ...)
--
-- but migration 012 constrained that column to ('Rejected', 'Offered'). Every
-- accept therefore raised 23514, rolled the whole transaction back, and reached
-- the Customer as a generic failure — which the app rendered as "this offer is
-- no longer available. Please choose another driver."
--
-- It was never a timing problem. It failed on the first attempt, the fastest
-- attempt and every attempt, because the statement could not commit at all. The
-- booking, the trip operation, the assignment and the notification were all
-- written correctly and then discarded a few lines later.
--
-- The code has written 'Accepted' since the marketplace flow was built, so the
-- constraint is what is wrong here, not the value.

ALTER TABLE udrive.driver_ride_request_decisions
    DROP CONSTRAINT IF EXISTS ck_driver_request_decision;

ALTER TABLE udrive.driver_ride_request_decisions
    ADD CONSTRAINT ck_driver_request_decision
    CHECK (decision IN ('Rejected', 'Offered', 'Accepted'));

COMMENT ON COLUMN udrive.driver_ride_request_decisions.decision IS
    'Offered = Driver sent a fare. Rejected = Driver declined. '
    'Accepted = the Customer took this Driver''s offer.';
