import '../network/api_client.dart';
import '../../models/communication_models.dart';

/// The notification bell, and nothing else.
///
/// It used to carry a second pair of methods, `messages` and `send`, against
/// `/api/v1/bookings/{id}/messages`. They were the only callers of a whole
/// second chat system: `BookingChatScreen` wrote there, while the driver's own
/// trip screen read `/api/v1/trips/{id}/messages`. Two people on one trip, two
/// tables, neither side seeing the other's messages.
///
/// One chat now, and it is [TripChatRepository]'s. Those two methods and the
/// `BookingMessage` model they returned are gone with the screen. The API
/// endpoints still exist and still hold whatever was written to them — nothing
/// here deletes anything — but the app no longer reads or writes them.
class CommunicationRepository {
  CommunicationRepository(this.client);

  final ApiClient client;

  Future<NotificationPage> notifications() async {
    final r = await client.getJson('/api/v1/notifications');
    return NotificationPage.fromJson(Map<String, dynamic>.from(r['data'] as Map));
  }

  Future<void> markRead(String id) =>
      client.putJson('/api/v1/notifications/$id/read', const {});

  Future<void> markAllRead() =>
      client.putJson('/api/v1/notifications/read-all', const {});
}
