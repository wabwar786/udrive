# Phase 15 — Notifications & Communication

Implemented:
- Additive migration 016 for notification preferences, user devices, booking conversations/messages and notification delivery metadata.
- Authenticated notification list, unread count, mark one/all read.
- Notification preference read/update APIs.
- Device token registration foundation for FCM/APNs/web push.
- Booking-scoped customer/driver messaging with authorization, 2,000-character limit, read state and notification creation.
- Flutter live notification centre replacing dummy data.
- Flutter reusable booking chat screen with 10-second refresh.

Endpoints:
- GET /api/v1/notifications
- PUT /api/v1/notifications/{id}/read
- PUT /api/v1/notifications/read-all
- GET /api/v1/notification-preferences
- PUT /api/v1/notification-preferences
- POST /api/v1/devices/register
- GET /api/v1/bookings/{bookingId}/messages
- POST /api/v1/bookings/{bookingId}/messages

Still requires provider configuration before production push/SMS delivery:
- Firebase service account / FCM sender implementation
- APNs configuration for iOS
- Production SMS gateway credentials
- Native background notification permission testing
