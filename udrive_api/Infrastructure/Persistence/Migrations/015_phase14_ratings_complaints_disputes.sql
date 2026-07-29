CREATE TABLE IF NOT EXISTS udrive.trip_ratings (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    reviewer_user_id uuid NOT NULL REFERENCES udrive.users(id),
    reviewee_user_id uuid NOT NULL REFERENCES udrive.users(id),
    reviewer_role varchar(20) NOT NULL CHECK (reviewer_role IN ('Customer','Driver')),
    overall_rating smallint NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
    driving_rating smallint CHECK (driving_rating BETWEEN 1 AND 5),
    behaviour_rating smallint CHECK (behaviour_rating BETWEEN 1 AND 5),
    cleanliness_rating smallint CHECK (cleanliness_rating BETWEEN 1 AND 5),
    punctuality_rating smallint CHECK (punctuality_rating BETWEEN 1 AND 5),
    communication_rating smallint CHECK (communication_rating BETWEEN 1 AND 5),
    review_text varchar(1200),
    is_visible boolean NOT NULL DEFAULT true,
    moderation_status varchar(20) NOT NULL DEFAULT 'Published',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (booking_id, reviewer_user_id)
);
CREATE INDEX IF NOT EXISTS ix_trip_ratings_reviewee ON udrive.trip_ratings(reviewee_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.dispute_cases (
    id uuid PRIMARY KEY,
    case_reference varchar(32) NOT NULL UNIQUE,
    booking_id uuid REFERENCES udrive.bookings(id),
    opened_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    against_user_id uuid REFERENCES udrive.users(id),
    category varchar(50) NOT NULL,
    priority varchar(20) NOT NULL DEFAULT 'Normal',
    subject varchar(180) NOT NULL,
    description text NOT NULL,
    requested_resolution varchar(80),
    disputed_amount numeric(12,2),
    status varchar(30) NOT NULL DEFAULT 'Open',
    assigned_admin_user_id uuid REFERENCES udrive.users(id),
    resolution_summary text,
    resolved_at timestamptz,
    closed_at timestamptz,
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_dispute_cases_queue ON udrive.dispute_cases(status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_dispute_cases_user ON udrive.dispute_cases(opened_by_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.dispute_evidence (
    id uuid PRIMARY KEY,
    case_id uuid NOT NULL REFERENCES udrive.dispute_cases(id) ON DELETE CASCADE,
    uploaded_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    file_url text NOT NULL,
    file_name varchar(240) NOT NULL,
    content_type varchar(120) NOT NULL,
    file_size bigint NOT NULL,
    description varchar(500),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_dispute_evidence_case ON udrive.dispute_evidence(case_id, created_at);

CREATE TABLE IF NOT EXISTS udrive.dispute_case_events (
    id uuid PRIMARY KEY,
    case_id uuid NOT NULL REFERENCES udrive.dispute_cases(id) ON DELETE CASCADE,
    actor_user_id uuid REFERENCES udrive.users(id),
    event_type varchar(50) NOT NULL,
    is_internal boolean NOT NULL DEFAULT false,
    message text NOT NULL,
    metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_dispute_case_events_case ON udrive.dispute_case_events(case_id, created_at);
