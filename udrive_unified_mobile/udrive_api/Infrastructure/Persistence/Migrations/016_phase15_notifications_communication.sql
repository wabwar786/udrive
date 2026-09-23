CREATE TABLE IF NOT EXISTS udrive.notification_preferences (
    user_id uuid PRIMARY KEY REFERENCES udrive.users(id) ON DELETE CASCADE,
    booking_alerts boolean NOT NULL DEFAULT true,
    package_alerts boolean NOT NULL DEFAULT true,
    payout_alerts boolean NOT NULL DEFAULT true,
    complaint_alerts boolean NOT NULL DEFAULT true,
    promotional_alerts boolean NOT NULL DEFAULT false,
    push_enabled boolean NOT NULL DEFAULT true,
    sms_enabled boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.user_devices (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    device_token text NOT NULL,
    platform varchar(24) NOT NULL,
    device_name varchar(120),
    is_active boolean NOT NULL DEFAULT true,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_devices_token UNIQUE(device_token)
);
CREATE INDEX IF NOT EXISTS ix_user_devices_user_active ON udrive.user_devices(user_id,is_active);

CREATE TABLE IF NOT EXISTS udrive.booking_conversations (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL UNIQUE REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    is_read_only boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.booking_messages (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES udrive.booking_conversations(id) ON DELETE CASCADE,
    sender_user_id uuid NOT NULL REFERENCES udrive.users(id),
    body text NOT NULL,
    sent_at timestamptz NOT NULL DEFAULT now(),
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_booking_messages_conversation_time ON udrive.booking_messages(conversation_id,sent_at DESC);
CREATE INDEX IF NOT EXISTS ix_booking_messages_unread ON udrive.booking_messages(conversation_id,read_at) WHERE read_at IS NULL;

ALTER TABLE udrive.notifications ADD COLUMN IF NOT EXISTS action_path varchar(240);
ALTER TABLE udrive.notifications ADD COLUMN IF NOT EXISTS delivery_status varchar(24) NOT NULL DEFAULT 'Stored';
