CREATE TABLE IF NOT EXISTS udrive.driver_ride_request_decisions (
    ride_request_id uuid NOT NULL REFERENCES udrive.ride_requests(id) ON DELETE CASCADE,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    decision varchar(24) NOT NULL,
    reason varchar(500),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ride_request_id, driver_profile_id),
    CONSTRAINT ck_driver_request_decision CHECK (decision IN ('Rejected', 'Offered'))
);

CREATE INDEX IF NOT EXISTS ix_driver_request_decisions_driver
    ON udrive.driver_ride_request_decisions(driver_profile_id, decision, updated_at DESC);
