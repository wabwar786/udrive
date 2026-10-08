-- Approved page: an Admin can send something that is already live back for
-- review, or suspend it. Either way its rides / bookings stop at once and the
-- owner's dashboard says why.
--
-- 1. listing_holds: one open hold per thing (city vehicle, tour vehicle, rent
--    vehicle, hotel, business). Review = back to Verification, with the
--    documents the Admin wants again. Suspend = stays on the Approved page
--    until an Admin unsuspends it. released_at closes the hold.
-- 2. hold_claims: the owner's re-claim against a suspension ("the reason is
--    wrong" / "I fixed it"), with up to three photos. One open claim at a time.
-- 3. Four WhatsApp messages, editable in Setup → WhatsApp messages.
--
-- Safe to run more than once.

CREATE TABLE IF NOT EXISTS udrive.listing_holds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind varchar(16) NOT NULL,
    entity_id uuid NOT NULL,
    owner_user_id uuid NOT NULL REFERENCES udrive.users(id),
    hold_type varchar(16) NOT NULL,
    reason varchar(1000) NOT NULL,
    requested_docs text[] NOT NULL DEFAULT '{}',
    uploaded_docs text[] NOT NULL DEFAULT '{}',
    submitted_at timestamptz,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz,
    released_by uuid,
    release_note varchar(300),
    CONSTRAINT ck_listing_holds_kind CHECK (kind IN ('city', 'tour', 'rent', 'hotels', 'businesses')),
    CONSTRAINT ck_listing_holds_type CHECK (hold_type IN ('Review', 'Suspend'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_listing_holds_open
    ON udrive.listing_holds (kind, entity_id)
    WHERE released_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_listing_holds_owner_open
    ON udrive.listing_holds (owner_user_id)
    WHERE released_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_listing_holds_entity
    ON udrive.listing_holds (entity_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.hold_claims (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hold_id uuid NOT NULL REFERENCES udrive.listing_holds(id),
    user_id uuid NOT NULL REFERENCES udrive.users(id),
    claim_type varchar(16) NOT NULL,
    message varchar(1000) NOT NULL,
    photo_urls text[] NOT NULL DEFAULT '{}',
    status varchar(16) NOT NULL DEFAULT 'Pending',
    admin_note varchar(1000),
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    decided_by uuid,
    CONSTRAINT ck_hold_claims_type CHECK (claim_type IN ('WrongReason', 'Fixed')),
    CONSTRAINT ck_hold_claims_status CHECK (status IN ('Pending', 'Accepted', 'Rejected'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_hold_claims_open
    ON udrive.hold_claims (hold_id)
    WHERE status = 'Pending';

INSERT INTO udrive.message_templates
    (key, title, audience, description, placeholders, body, default_body, sort_order)
SELECT k, t, a, d, p, b, b, o
FROM (VALUES
    ('hold_review_owner', 'Dobara review — owner', 'Driver',
     'Admin ne approved gaari / hotel / business ko dobara review mein bheja.',
     ARRAY['item','reason','docs'],
     E'UDrive: aap ki {item} dobara review mein hai.\nJab tak review nahi hoti, koi ride ya booking nahi milegi.\nWajah: {reason}\nYeh bhejein: {docs}\nUDrive app kholein → dashboard par upload karein.',
     70),
    ('hold_suspend_owner', 'Suspend — owner', 'Driver',
     'Admin ne approved gaari / hotel / business suspend kiya.',
     ARRAY['item','reason'],
     E'UDrive: aap ki {item} suspend ho gayi hai.\nJab tak admin dobara chalu nahi karta, koi ride ya booking nahi milegi.\nWajah: {reason}\nAgar wajah galat hai to UDrive app → dashboard → Re-claim.',
     80),
    ('hold_released_owner', 'Dobara chalu — owner', 'Driver',
     'Suspend khatam ho gaya; rides / bookings dobara chalu.',
     ARRAY['item'],
     E'UDrive: aap ki {item} dobara chalu ho gayi hai ✅\nAb rides / bookings phir se milein gi.',
     90),
    ('claim_rejected_owner', 'Re-claim reject — owner', 'Driver',
     'Admin ne suspension par owner ka re-claim reject kiya.',
     ARRAY['item','note'],
     E'UDrive: {item} ki suspension par aap ki request manzoor nahi hui.\nAdmin: {note}\nAap app se dobara re-claim kar sakte hain.',
     100)
) AS v(k, t, a, d, p, b, o)
ON CONFLICT (key) DO NOTHING;
