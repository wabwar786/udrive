-- Phase 20: production hardening, operational indexes and launch settings.

CREATE INDEX IF NOT EXISTS ix_otp_expired_cleanup
    ON udrive.auth_otp_challenges(expires_at, consumed_at);

CREATE INDEX IF NOT EXISTS ix_refresh_tokens_cleanup
    ON udrive.refresh_tokens(expires_at, revoked_at);

CREATE INDEX IF NOT EXISTS ix_tracking_tokens_cleanup
    ON udrive.trip_tracking_tokens(expires_at, revoked_at);

CREATE INDEX IF NOT EXISTS ix_trip_location_history_retention
    ON udrive.trip_location_history(server_timestamp);

CREATE INDEX IF NOT EXISTS ix_notifications_retention
    ON udrive.notifications(created_at)
    WHERE read_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_package_holds_expiry
    ON udrive.package_seat_holds(expires_at)
    WHERE status = 'Active';

INSERT INTO udrive.system_settings(key,value_json,description,is_public,created_at,updated_at)
VALUES
 ('production.maintenance_interval_hours','6'::jsonb,'Background cleanup interval.',false,now(),now()),
 ('production.otp_retention_hours','24'::jsonb,'Expired OTP challenge retention.',false,now(),now()),
 ('production.refresh_token_retention_days','30'::jsonb,'Expired or revoked refresh-token retention.',false,now(),now()),
 ('production.notification_retention_days','180'::jsonb,'Read-notification retention.',false,now(),now()),
 ('production.release_mode','"soft_launch"'::jsonb,'Current production launch mode.',false,now(),now())
ON CONFLICT(key) DO UPDATE SET
 value_json = EXCLUDED.value_json,
 description = EXCLUDED.description,
 updated_at = now();
