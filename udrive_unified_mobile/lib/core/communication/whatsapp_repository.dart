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
}
