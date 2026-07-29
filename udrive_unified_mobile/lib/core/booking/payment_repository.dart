import '../network/api_client.dart';

class PaymentRepository {
  PaymentRepository(this._api);
  final ApiClient _api;

  Future<Map<String, dynamic>> summary(String bookingId) async {
    final value = await _api.getJson('/api/v1/payments/booking/$bookingId');
    return Map<String, dynamic>.from(value['data'] as Map);
  }

  Future<Map<String, dynamic>> create({
    required String bookingId,
    required String method,
    required String paymentType,
    required double amount,
  }) async {
    final value = await _api.postJson('/api/v1/payments', {
      'bookingId': bookingId,
      'method': method,
      'paymentType': paymentType,
      'amount': amount,
      'idempotencyKey': 'mobile:$bookingId:${DateTime.now().microsecondsSinceEpoch}',
    });
    return Map<String, dynamic>.from(value['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> payoutAccounts() async {
    final value = await _api.getJson('/api/v1/driver/payout-accounts');
    final raw = value['data'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> savePayoutAccount({
    required String method,
    required String accountTitle,
    required String accountIdentifier,
    String? bankName,
    bool isDefault = true,
  }) async {
    await _api.postJson('/api/v1/driver/payout-accounts', {
      'method': method,
      'accountTitle': accountTitle,
      'accountIdentifier': accountIdentifier,
      'bankName': bankName,
      'isDefault': isDefault,
    });
  }
}
