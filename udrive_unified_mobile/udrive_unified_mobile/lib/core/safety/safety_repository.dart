import '../network/api_client.dart';

class TrustedContact {
  TrustedContact({required this.id, required this.name, required this.phone, required this.relationship, required this.isPrimary});
  final String id, name, phone, relationship;
  final bool isPrimary;
  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
    id: '${j['id']}', name: '${j['name'] ?? ''}', phone: '${j['phoneNumber'] ?? ''}',
    relationship: '${j['relationship'] ?? ''}', isPrimary: j['isPrimary'] == true,
  );
}

class SafetyRepository {
  SafetyRepository(this.client);
  final ApiClient client;

  Future<List<TrustedContact>> contacts() async {
    final r = await client.getJson('/api/v1/safety/trusted-contacts');
    final d = r['data'] as List? ?? const [];
    return d.map((e) => TrustedContact.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> addContact({required String name, required String phone, required String relationship, required bool primary}) =>
      client.postJson('/api/v1/safety/trusted-contacts', {'name': name, 'phoneNumber': phone, 'relationship': relationship, 'isPrimary': primary});

  Future<void> raiseSos({String? bookingId, required String type, required String description, double? latitude, double? longitude, double? accuracy}) =>
      client.postJson('/api/v1/safety/sos', {'bookingId': bookingId, 'emergencyType': type, 'description': description, 'latitude': latitude, 'longitude': longitude, 'accuracyMeters': accuracy});

  Future<Map<String, dynamic>> createPin(String bookingId) async =>
      Map<String, dynamic>.from((await client.postJson('/api/v1/safety/trips/$bookingId/pin', const {}))['data'] as Map);

  Future<void> verifyPin(String bookingId, String pin) =>
      client.postJson('/api/v1/safety/trips/$bookingId/pin/verify', {'pin': pin});

  Future<void> report({required String bookingId, required String type, required String severity, required String description, double? latitude, double? longitude}) =>
      client.postJson('/api/v1/safety/reports', {'bookingId': bookingId, 'reportType': type, 'severity': severity, 'description': description, 'latitude': latitude, 'longitude': longitude});
}
