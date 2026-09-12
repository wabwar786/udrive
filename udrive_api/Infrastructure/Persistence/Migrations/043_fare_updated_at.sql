-- When the Customer last raised their fare.
--
-- Raising the fare has to put the request back in front of every Driver,
-- including the ones who already declined or offered — their earlier answer was
-- to a different price, and holding it against them means raising the fare
-- reaches a *smaller* pool than before, which is the opposite of the point.
--
-- `updated_at` cannot be used for this. It moves whenever anything about the
-- request changes — the status flipping to ReceivingOffers the moment the first
-- offer lands, for one — so every offer would clear every Driver's decision and
-- re-alert the whole area. Its own column moves only when the price does.

ALTER TABLE udrive.ride_requests
    ADD COLUMN IF NOT EXISTS fare_updated_at timestamptz;

COMMENT ON COLUMN udrive.ride_requests.fare_updated_at IS
    'When customer_offer was last raised. Decisions older than this are ignored '
    'so the request is offered again at the new price.';
