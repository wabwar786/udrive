import '../network/api_client.dart';

class WhatsAppRepository {
  WhatsAppRepository(this.client);
  final ApiClient client;

  Future<void> shareLocation({
    required String to,
    required String contactName,
    required double latitude,
    required double longitude,
  }) async {
    await client.postJson('/api/v1/communication/whatsapp/location-share', {
      'to': to,
      'contactName': contactName,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<int> emergencyBroadcast({
    required List<String> numbers,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String customerName,
  }) async {
    final response = await client.postJson('/api/v1/communication/whatsapp/emergency-broadcast', {
      'numbers': numbers,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'customerName': customerName,
    });
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return (data['recipientCount'] as num?)?.toInt() ?? numbers.length;
    }
    return numbers.length;
  }
}
