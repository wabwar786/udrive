-- The trip code, readable by the Customer it belongs to.
--
-- `trip_otp_hash` is a hash, by design: it proves a code without storing one.
-- But the Customer has to *read* the code and say it to the Driver, and a hash
-- cannot be read back. So the code was only ever visible in the single response
-- that created the booking. Close the app, come back through "Track ride", and
-- the OTP panel simply vanished — the trip could not be started at all.
--
-- Stored in plaintext next to the hash. This is not a secret from the Customer;
-- it is a secret from everyone else, and the API only returns it to the person
-- whose booking it is. The hash stays, and stays the only thing verification
-- compares against.

ALTER TABLE udrive.bookings
    ADD COLUMN IF NOT EXISTS trip_otp varchar(8);

COMMENT ON COLUMN udrive.bookings.trip_otp IS
    'The code the Customer reads out. Returned only to that Customer. '
    'Verification still compares against trip_otp_hash.';
