import 'package:file_picker/file_picker.dart';

import '../network/api_client.dart';

/// A document the Admin asked for again.
class HoldDocument {
  const HoldDocument({
    required this.key,
    required this.label,
    required this.uploaded,
  });

  final String key;
  final String label;
  final bool uploaded;

  factory HoldDocument.fromJson(Map<String, dynamic> json) => HoldDocument(
        key: '${json['key'] ?? ''}',
        label: '${json['label'] ?? json['key'] ?? ''}',
        uploaded: json['uploaded'] == true,
      );
}

/// The owner's re-claim against a suspension.
class HoldClaim {
  const HoldClaim({
    required this.type,
    required this.message,
    required this.photos,
    required this.status,
    required this.adminNote,
    required this.createdAt,
  });

  /// `WrongReason` or `Fixed`.
  final String type;
  final String message;
  final int photos;

  /// `Pending`, `Accepted` or `Rejected`.
  final String status;
  final String? adminNote;
  final DateTime createdAt;

  bool get pending => status == 'Pending';
  bool get rejected => status == 'Rejected';

  factory HoldClaim.fromJson(Map<String, dynamic> json) => HoldClaim(
        type: '${json['type'] ?? ''}',
        message: '${json['message'] ?? ''}',
        photos: (json['photos'] as List?)?.length ?? 0,
        status: '${json['status'] ?? ''}',
        adminNote: _text(json['adminNote']),
        createdAt: _time(json['createdAt']) ?? DateTime.now(),
      );
}

/// An open review or suspension on one of the caller's vehicles, hotels or
/// businesses. While it is open no new ride or booking reaches it.
class Hold {
  const Hold({
    required this.id,
    required this.kind,
    required this.entityId,
    required this.title,
    required this.type,
    required this.reason,
    required this.documents,
    required this.createdAt,
    required this.submittedAt,
    required this.claim,
  });

  final String id;

  /// `city`, `tour`, `rent`, `hotels` or `businesses`.
  final String kind;
  final String entityId;
  final String title;

  /// `Review` or `Suspend`.
  final String type;
  final String reason;
  final List<HoldDocument> documents;
  final DateTime createdAt;

  /// When the owner sent the asked-for documents back.
  final DateTime? submittedAt;
  final HoldClaim? claim;

  bool get isReview => type == 'Review';
  bool get isSuspend => type == 'Suspend';
  bool get allUploaded => documents.every((d) => d.uploaded);

  factory Hold.fromJson(Map<String, dynamic> json) => Hold(
        id: '${json['id']}',
        kind: '${json['kind'] ?? ''}',
        entityId: '${json['entityId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        type: '${json['type'] ?? ''}',
        reason: '${json['reason'] ?? ''}',
        documents: [
          for (final item in (json['documents'] as List? ?? const []))
            if (item is Map) HoldDocument.fromJson(Map<String, dynamic>.from(item)),
        ],
        createdAt: _time(json['createdAt']) ?? DateTime.now(),
        submittedAt: _time(json['submittedAt']),
        claim: json['claim'] is Map
            ? HoldClaim.fromJson(Map<String, dynamic>.from(json['claim'] as Map))
            : null,
      );
}

class HoldRepository {
  HoldRepository(this.api);

  final ApiClient api;

  Future<List<Hold>> mine() async {
    final response = await api.getJson('/api/v1/me/holds');
    final data = response['data'];
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map) Hold.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<String> upload(Hold hold, String key, PlatformFile file) async {
    final response = await api.uploadFile(
      '/api/v1/me/holds/${hold.id}/documents/$key',
      fieldName: 'file',
      file: file,
      fields: const {},
    );
    return '${response['message'] ?? 'Upload ho gaya.'}';
  }

  Future<String> submit(Hold hold) async {
    final response =
        await api.postJson('/api/v1/me/holds/${hold.id}/submit', const {});
    return '${response['message'] ?? 'Bhej diya.'}';
  }

  /// [type]: `WrongReason` or `Fixed`.
  Future<String> claim(
    Hold hold, {
    required String type,
    required String message,
    required List<PlatformFile> photos,
  }) async {
    final response = await api.uploadFiles(
      '/api/v1/me/holds/${hold.id}/claim',
      fieldName: 'photos',
      files: photos,
      fields: {'type': type, 'message': message},
    );
    return '${response['message'] ?? 'Request bhej di.'}';
  }
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
