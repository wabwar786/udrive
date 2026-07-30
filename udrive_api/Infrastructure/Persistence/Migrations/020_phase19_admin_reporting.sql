CREATE INDEX IF NOT EXISTS ix_bookings_admin_created_status ON udrive.bookings(created_at DESC,status);
CREATE INDEX IF NOT EXISTS ix_bookings_admin_pickup_status ON udrive.bookings(pickup_at,status);
CREATE INDEX IF NOT EXISTS ix_payments_admin_booking_status ON udrive.payments(booking_id,status,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_logs_admin_created ON udrive.audit_logs(created_at DESC,action,entity_type);
CREATE INDEX IF NOT EXISTS ix_emergency_cases_admin_status ON udrive.emergency_cases(status,severity,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_dispute_cases_admin_status ON udrive.dispute_cases(status,priority,created_at DESC);
INSERT INTO udrive.system_settings(key,value_json,description,is_public,created_at,updated_at) VALUES
('admin.report_default_days','30'::jsonb,'Default date range for executive reports.',false,now(),now()),
('admin.dashboard_refresh_seconds','30'::jsonb,'Executive dashboard refresh interval.',false,now(),now()),
('admin.live_operations_refresh_seconds','10'::jsonb,'Live operations refresh interval.',false,now(),now())
ON CONFLICT(key) DO NOTHING;
