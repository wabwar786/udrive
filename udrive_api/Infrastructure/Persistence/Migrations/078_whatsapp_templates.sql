-- WhatsApp messages for bookings, acceptances and a low wallet — with every
-- text kept in the database, so an Admin can change it or switch it off at
-- any time from Setup → WhatsApp messages.
--
-- 1. message_templates: one row per message. {placeholders} in the body are
--    filled in when the message is sent. default_body is the original text,
--    for "Reset to default".
-- 2. whatsapp_outbox: messages waiting to go. A booking only writes a row
--    here; a background sender delivers it through WA Engine and retries, so
--    a slow or offline WhatsApp never holds up or undoes a booking.
--
-- Safe to run more than once. An Admin's edits are never overwritten.

CREATE TABLE IF NOT EXISTS udrive.message_templates (
    key varchar(64) PRIMARY KEY,
    title varchar(120) NOT NULL,
    audience varchar(16) NOT NULL,
    description varchar(300) NOT NULL,
    placeholders text[] NOT NULL DEFAULT '{}',
    body text NOT NULL,
    default_body text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    sort_order int NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid,
    CONSTRAINT ck_message_templates_audience CHECK (audience IN ('Customer', 'Driver'))
);

CREATE TABLE IF NOT EXISTS udrive.whatsapp_outbox (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key varchar(64) NOT NULL,
    to_phone varchar(32) NOT NULL,
    body text NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'Pending',
    attempts int NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    last_error varchar(300),
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz,
    CONSTRAINT ck_whatsapp_outbox_status CHECK (status IN ('Pending', 'Sent', 'Failed'))
);

CREATE INDEX IF NOT EXISTS ix_whatsapp_outbox_due
    ON udrive.whatsapp_outbox (next_attempt_at)
    WHERE status = 'Pending';

CREATE INDEX IF NOT EXISTS ix_whatsapp_outbox_template
    ON udrive.whatsapp_outbox (template_key, created_at DESC);

INSERT INTO udrive.message_templates
    (key, title, audience, description, placeholders, body, default_body, sort_order)
SELECT k, t, a, d, p, b, b, o
FROM (VALUES
    ('tour_booking_customer', 'Tour booking — customer', 'Customer',
     'Customer ne tour (seat ya poori gaari) book ki aur advance diya.',
     ARRAY['tour','departure','booking','total','advance','pickup','driver','driver_phone','vehicle','ref'],
     E'UDrive: aap ki tour booking confirm ho gayi ✅\nTour: {tour} · {departure}\nBooking: {booking} · Kul PKR {total} · Advance PKR {advance}\nPickup: {pickup}\nDriver: {driver} · {driver_phone} · Gaari: {vehicle}\nRef: {ref}',
     10),
    ('tour_booking_driver', 'Tour booking — driver', 'Driver',
     'Driver ki tour par nayi booking aayi (accept karne ki zaroorat nahi).',
     ARRAY['tour','departure','customer','customer_phone','booking','total','seats'],
     E'UDrive: nayi tour booking ✅ (accept karne ki zaroorat nahi)\nTour: {tour} · {departure}\nCustomer: {customer} · {customer_phone}\nBooking: {booking} · PKR {total}\nSeats: {seats} book\nUDrive app → Tour & Rent bookings',
     20),
    ('rent_booking_customer', 'Rent booking — customer', 'Customer',
     'Customer ki rent-a-car booking confirm ho gayi.',
     ARRAY['vehicle','mode','dates','days','total','advance','pickup','owner','owner_phone','ref'],
     E'UDrive: aap ki gaari confirm ho gayi ✅\nGaari: {vehicle} · {mode}\nTareekh: {dates} ({days} din) · Kul PKR {total} · Advance PKR {advance}\nPickup: {pickup}\nOwner: {owner} · {owner_phone}\nRef: {ref}',
     30),
    ('rent_booking_driver', 'Rent booking — driver', 'Driver',
     'Driver ki gaari rent par book ho gayi (accept karne ki zaroorat nahi).',
     ARRAY['vehicle','mode','dates','days','total','customer','customer_phone'],
     E'UDrive: nayi rent booking ✅ (accept karne ki zaroorat nahi)\nGaari: {vehicle} · {mode}\nTareekh: {dates} ({days} din) · PKR {total}\nCustomer: {customer} · {customer_phone}\nUDrive app → Tour & Rent bookings',
     40),
    ('waitlist_accepted_customer', 'Waiting list accept — customer', 'Customer',
     'Driver ne customer ki waiting list request accept kar li.',
     ARRAY['what','until','where'],
     E'UDrive: khushkhabri! Driver ne aap ki request accept kar li ✅\n{what}\n{until} tak advance de kar booking pakki karein, warna jagah kisi aur ko di ja sakti hai.\nUDrive app kholein → {where}',
     50),
    ('wallet_low_driver', 'Wallet kam — driver', 'Driver',
     'Driver ka wallet setting wali had se neeche aa gaya (City rides, Tour, Rent sab).',
     ARRAY['balance','line'],
     E'UDrive: aap ka wallet PKR {balance} reh gaya hai, {line} se kam.\nWallet kam ho to nayi rides ya bookings nahi milein gi.\nTop-up: UDrive app → Wallet → Top-up ka tareeqa',
     60)
) AS v(k, t, a, d, p, b, o)
ON CONFLICT (key) DO NOTHING;
