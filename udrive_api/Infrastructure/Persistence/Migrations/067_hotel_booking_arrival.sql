-- Hotel bookings learn who is coming, when, and how.
--
-- A booking used to carry only the room and the dates. The hotel had no way of
-- knowing when to expect the guest, or how to reach them, until the guest
-- turned up. Now the customer says when they will arrive and how they are
-- getting there (their own car, a UDrive ride, or the hotel's own transport),
-- and the owner is sent all of it on WhatsApp the moment the booking is made.
--
-- guest_name / guest_phone are copied onto the booking rather than read from
-- the user each time: they are what the hotel was told, and a later profile
-- edit must not change the record of it.
--
-- owner_notified_at / owner_notify_error record whether that WhatsApp message
-- went out, so a failed send is visible instead of silently lost. A booking is
-- never refused because the message could not be sent.

ALTER TABLE udrive.hotel_bookings
    ADD COLUMN IF NOT EXISTS booking_reference text,
    ADD COLUMN IF NOT EXISTS arrival_time time,
    ADD COLUMN IF NOT EXISTS arrival_mode text NOT NULL DEFAULT 'OwnCar',
    ADD COLUMN IF NOT EXISTS car_number text,
    ADD COLUMN IF NOT EXISTS guest_name text,
    ADD COLUMN IF NOT EXISTS guest_phone text,
    ADD COLUMN IF NOT EXISTS owner_notified_at timestamptz,
    ADD COLUMN IF NOT EXISTS owner_notify_error text;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_hotel_bookings_arrival_mode'
    ) THEN
        ALTER TABLE udrive.hotel_bookings
            ADD CONSTRAINT ck_hotel_bookings_arrival_mode
            CHECK (arrival_mode IN ('OwnCar', 'UDriveRide', 'HotelTransport'));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_hotel_bookings_reference
    ON udrive.hotel_bookings (booking_reference)
    WHERE booking_reference IS NOT NULL;
