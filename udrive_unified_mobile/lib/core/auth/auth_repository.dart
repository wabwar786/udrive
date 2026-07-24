import 'package:file_picker/file_picker.dart';
import '../network/api_client.dart';
import 'session_store.dart';
import '../../models/auth_models.dart';

class AuthRepository {
  AuthRepository(this.sessionStore) : client = ApiClient(sessionStore);

  final SessionStore sessionStore;
  final ApiClient client;

  Future<OtpChallenge> requestOtp(String phoneNumber) async {
    final response = await client.postJson(
      '/api/v1/auth/otp/request',
      {'phoneNumber': phoneNumber, 'purpose': 'login'},
      authenticated: false,
    );
    return OtpChallenge.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<CurrentUser> verifyOtp({
    required String phoneNumber,
    required String code,
    required String fullName,
    required String language,
  }) async {
    final deviceId = await sessionStore.deviceId();
    final response = await client.postJson(
      '/api/v1/auth/otp/verify',
      {
        'phoneNumber': phoneNumber,
        'code': code,
        'fullName': fullName,
        'language': language,
        'deviceId': deviceId,
        'deviceName': 'uDrive mobile',
      },
      authenticated: false,
    );
    final tokens = AuthTokens.fromJson(response['data'] as Map<String, dynamic>);
    await sessionStore.saveTokens(tokens);
    return tokens.user;
  }

  Future<CurrentUser> me() async {
    final response = await client.getJson('/api/v1/auth/me');
    final user = CurrentUser.fromJson(response['data'] as Map<String, dynamic>);
    await sessionStore.saveUser(user);
    return user;
  }

  Future<void> logout({bool allDevices = false}) async {
    final refresh = await sessionStore.readRefreshToken();
    try {
      await client.postJson('/api/v1/auth/logout', {
        'refreshToken': refresh,
        'revokeAllDevices': allDevices,
      });
    } finally {
      await sessionStore.clear();
    }
  }

  Future<DriverProfileLive?> getDriverProfile() async {
    try {
      final response = await client.getJson('/api/v1/driver/onboarding');
      return DriverProfileLive.fromJson(response['data'] as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<DriverProfileLive> saveDriverProfile(Map<String, dynamic> payload) async {
    final response = await client.putJson('/api/v1/driver/onboarding', payload);
    return DriverProfileLive.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<DriverProfileLive> submitDriverProfile() async {
    final response = await client.postJson('/api/v1/driver/onboarding/submit', const {});
    return DriverProfileLive.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> uploadDriverDocument({
    required String documentType,
    required PlatformFile file,
    String? expiryDate,
  }) async {
    final response = await client.uploadFile(
      '/api/v1/driver/documents',
      fieldName: 'file',
      file: file,
      fields: {
        'documentType': documentType,
        if (expiryDate != null && expiryDate.isNotEmpty) 'expiryDate': expiryDate,
      },
    );
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  Future<List<LiveVehicle>> getVehicles() async {
    final response = await client.getJson('/api/v1/driver/vehicles');
    return (response['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => LiveVehicle.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<LiveVehicle> createVehicle(Map<String, dynamic> payload) async {
    final response = await client.postJson('/api/v1/driver/vehicles', payload);
    return LiveVehicle.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> uploadVehicleDocument({
    required String vehicleId,
    required String documentType,
    required PlatformFile file,
    String? expiryDate,
  }) async {
    final response = await client.uploadFile(
      '/api/v1/driver/vehicles/$vehicleId/documents',
      fieldName: 'file',
      file: file,
      fields: {
        'documentType': documentType,
        if (expiryDate != null && expiryDate.isNotEmpty) 'expiryDate': expiryDate,
      },
    );
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  Future<LiveVehicle> submitVehicle(String vehicleId) async {
    final response = await client.postJson('/api/v1/driver/vehicles/$vehicleId/submit', const {});
    return LiveVehicle.fromJson(response['data'] as Map<String, dynamic>);
  }
}
