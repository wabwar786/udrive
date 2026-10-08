import 'package:file_picker/file_picker.dart';

import '../network/api_client.dart';

/// One line in the hotel wallet's history.
class HotelWalletEntry {
  const HotelWalletEntry({
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  /// Welcome, Topup, Commission, Refund or Adjustment.
  final String type;
  final double amount;
  final String description;
  final DateTime createdAt;

  factory HotelWalletEntry.fromJson(Map<String, dynamic> json) => HotelWalletEntry(
        type: '${json['type'] ?? ''}',
        amount: _number(json['amount']),
        description: '${json['description'] ?? ''}',
        createdAt: _time(json['createdAt']) ?? DateTime.now(),
      );
}

/// A top-up the owner sent, waiting for or decided by an Admin.
class HotelWalletTopup {
  const HotelWalletTopup({
    required this.amount,
    required this.reference,
    required this.status,
    required this.adminNotes,
    required this.createdAt,
  });

  final double amount;
  final String? reference;

  /// Pending, Approved or Rejected.
  final String status;
  final String? adminNotes;
  final DateTime createdAt;

  factory HotelWalletTopup.fromJson(Map<String, dynamic> json) => HotelWalletTopup(
        amount: _number(json['amount']),
        reference: _text(json['senderReference']),
        status: '${json['status'] ?? ''}',
        adminNotes: _text(json['adminNotes']),
        createdAt: _time(json['createdAt']) ?? DateTime.now(),
      );
}

/// The hotel owner's prepaid wallet.
class HotelWallet {
  const HotelWallet({
    required this.balance,
    required this.commissionPercentage,
    required this.minimumBalance,
    required this.lowBalanceAlert,
    required this.visible,
    required this.easypaisaNumber,
    required this.easypaisaName,
    required this.entries,
    required this.topups,
  });

  final double balance;
  final double commissionPercentage;
  final double minimumBalance;
  final double lowBalanceAlert;

  /// False: the balance is below the minimum and the hotel is hidden.
  final bool visible;
  final String? easypaisaNumber;
  final String? easypaisaName;
  final List<HotelWalletEntry> entries;
  final List<HotelWalletTopup> topups;

  bool get low => balance < lowBalanceAlert;

  factory HotelWallet.fromJson(Map<String, dynamic> json) => HotelWallet(
        balance: _number(json['balance']),
        commissionPercentage: _number(json['commissionPercentage']),
        minimumBalance: _number(json['minimumBalance']),
        lowBalanceAlert: _number(json['lowBalanceAlert']),
        visible: json['visible'] != false,
        easypaisaNumber: _text(json['easypaisaNumber']),
        easypaisaName: _text(json['easypaisaName']),
        entries: [
          for (final item in (json['entries'] as List? ?? const []))
            if (item is Map) HotelWalletEntry.fromJson(Map<String, dynamic>.from(item)),
        ],
        topups: [
          for (final item in (json['topups'] as List? ?? const []))
            if (item is Map) HotelWalletTopup.fromJson(Map<String, dynamic>.from(item)),
        ],
      );
}

class HotelWalletRepository {
  HotelWalletRepository(this.api);

  final ApiClient api;

  Future<HotelWallet> load() async {
    final response = await api.getJson('/api/v1/hotels/owner/wallet');
    final data = response['data'];
    return HotelWallet.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : const {});
  }

  /// Sends a top-up for the Admin to confirm. Returns the server's message.
  Future<String> topup({
    required double amount,
    String? reference,
    PlatformFile? screenshot,
  }) async {
    final fields = {
      'amount': amount.toStringAsFixed(0),
      if (reference != null && reference.trim().isNotEmpty)
        'senderReference': reference.trim(),
    };
    final response = screenshot == null
        ? await api.uploadFiles('/api/v1/hotels/owner/wallet/topups',
            fieldName: 'file', files: const [], fields: fields)
        : await api.uploadFile('/api/v1/hotels/owner/wallet/topups',
            fieldName: 'file', file: screenshot, fields: fields);
    return '${response['message'] ?? 'Top-up bhej diya.'}';
  }
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

DateTime? _time(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}
