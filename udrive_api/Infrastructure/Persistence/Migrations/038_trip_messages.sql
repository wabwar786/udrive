-- Messages between the Customer and the Driver of one booking.
--
-- Until now the only way to reach each other was a phone call. That works when
-- someone can answer, and fails exactly when it matters: on a mountain road
-- with one bar of signal, when the Driver is driving, or when the Customer is
-- standing on a street the Driver cannot find and neither of them speaks the
-- other's first language comfortably. A short written line survives all three.
--
-- Scoped to a booking on purpose. There is no general inbox and no way to
-- message someone you are not currently travelling with, which is the whole
-- safety property: a Driver cannot keep messaging a Customer after the ride.

CREATE TABLE IF NOT EXISTS udrive.trip_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    sender_user_id uuid NOT NULL REFERENCES udrive.users(id),

    -- Denormalised so the app can lay a message left or right without joining
    -- back to work out who sent it.
    sender_role varchar(20) NOT NULL CHECK (sender_role IN ('Customer','Driver')),

    body varchar(1000) NOT NULL,

    -- Set when the other side has loaded the message. Drives the unread badge;
    -- nothing more is inferred from it.
    read_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT trip_messages_body_not_blank CHECK (length(btrim(body)) > 0)
);

-- The only query there is: this booking's messages, oldest first, usually
-- filtered to those newer than the last one the client already has.
CREATE INDEX IF NOT EXISTS ix_trip_messages_booking
    ON udrive.trip_messages (booking_id, created_at);

CREATE INDEX IF NOT EXISTS ix_trip_messages_unread
    ON udrive.trip_messages (booking_id, sender_role)
    WHERE read_at IS NULL;

COMMENT ON TABLE udrive.trip_messages IS
    'Chat between the two people on one booking. No general messaging exists.';
