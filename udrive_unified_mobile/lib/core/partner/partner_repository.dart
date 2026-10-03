// `ApiException` lives in auth_models, not in api_client — the same import pair
// every other repository in this app carries.
import '../../models/auth_models.dart';
import '../network/api_client.dart';

/// Which city the customer is standing in, and whether UDrive runs there.
///
/// Before this existed the app had no idea where it was. Somebody in Rawalakot
/// saw exactly the home screen somebody in Muzaffarabad saw, and could work all
/// the way through a booking in a city with no drivers — then conclude the app
/// was broken, which was a fair conclusion.
class CityStatus {
  const CityStatus({
    required this.cityId,
    required this.cityName,
    required this.isLive,
    required this.launchStatus,
    required this.onWaitlist,
    required this.waitingCount,
    required this.driverCount,
    required this.partnerWanted,
    required this.cities,
  });

  /// Null when the location is outside every city's circles, or unknown.
  ///
  /// The app asks rather than guessing in that case. A customer told "UDrive is
  /// not available in your city" about a city they are not in is worse off than
  /// one who was simply asked.
  final String? cityId;
  final String? cityName;
  final bool isLive;
  final String? launchStatus;

  final bool onWaitlist;
  final int waitingCount;
  final int driverCount;

  /// The city is not live and nobody holds it.
  final bool partnerWanted;

  final List<CityEntry> cities;

  /// True when the gate has something to say. Everything else is the normal
  /// screen, untouched.
  bool get shouldWarn => cityId != null && !isLive;

  static CityStatus fromJson(Map<String, dynamic> json) => CityStatus(
        cityId: json['cityId'] as String?,
        cityName: json['cityName'] as String?,
        isLive: json['isLive'] == true,
        launchStatus: json['launchStatus'] as String?,
        onWaitlist: json['onWaitlist'] == true,
        waitingCount: _int(json['waitingCount']),
        driverCount: _int(json['driverCount']),
        partnerWanted: json['partnerWanted'] == true,
        cities: _maps(json['cities']).map(CityEntry.fromJson).toList(),
      );

  static const empty = CityStatus(
    cityId: null,
    cityName: null,
    isLive: false,
    launchStatus: null,
    onWaitlist: false,
    waitingCount: 0,
    driverCount: 0,
    partnerWanted: false,
    cities: <CityEntry>[],
  );
}

class CityEntry {
  const CityEntry({
    required this.id,
    required this.name,
    required this.isLive,
    required this.launchStatus,
    required this.waitingCount,
    required this.partnerWanted,
  });

  final String id;
  final String name;
  final bool isLive;
  final String launchStatus;
  final int waitingCount;
  final bool partnerWanted;

  static CityEntry fromJson(Map<String, dynamic> json) => CityEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isLive: json['isLive'] == true,
        launchStatus: json['launchStatus'] as String? ?? '',
        waitingCount: _int(json['waitingCount']),
        partnerWanted: json['partnerWanted'] == true,
      );
}

/// One of the three partner tiers, with its terms as the admin set them.
class PartnerTier {
  const PartnerTier({
    required this.tierKey,
    required this.displayName,
    required this.territoryKind,
    required this.securityDeposit,
    required this.commissionSharePct,
    required this.termMonths,
    required this.description,
    required this.commitments,
  });

  final String tierKey;
  final String displayName;

  /// 'Region', 'City' or 'Tehsil' — and the only areas this tier can be asked
  /// for. The server checks this too; the picker uses it so nobody is offered a
  /// choice that will be refused.
  final String territoryKind;

  final double securityDeposit;
  final double commissionSharePct;
  final int termMonths;
  final String? description;

  /// What this tier owes every month. Shown before anybody applies, because a
  /// partnership somebody did not know was work is an argument later.
  final List<String> commitments;

  static PartnerTier fromJson(Map<String, dynamic> json) => PartnerTier(
        tierKey: json['tierKey'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        territoryKind: json['territoryKind'] as String? ?? '',
        securityDeposit: _double(json['securityDeposit']),
        commissionSharePct: _double(json['commissionSharePct']),
        termMonths: _int(json['termMonths']),
        description: json['description'] as String?,
        commitments: _commitments(json['commitments']),
      );

  static List<String> _commitments(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is Map && item['isActive'] != false) {
        final label = item['label'] as String? ?? '';
        final target = _double(item['targetValue']);
        if (label.isNotEmpty) {
          out.add('$label: ${_plain(target)}');
        }
      }
    }
    return out;
  }
}

/// One area in the tree, and who holds it.
class TerritoryNode {
  const TerritoryNode({
    required this.id,
    required this.kind,
    required this.name,
    required this.path,
    required this.depth,
    required this.isActive,
    required this.partnerName,
    required this.driverCount,
    required this.waitingCount,
  });

  final String id;
  final String kind;
  final String name;
  final String path;
  final int depth;
  final bool isActive;

  /// Null when nobody holds it — which is the only state you can apply for.
  final String? partnerName;

  final int driverCount;
  final int waitingCount;

  bool get isOpen => isActive && partnerName == null;

  static TerritoryNode fromJson(Map<String, dynamic> json) => TerritoryNode(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        depth: _int(json['depth']),
        isActive: json['isActive'] != false,
        partnerName: json['partnerName'] as String?,
        driverCount: _int(json['driverCount']),
        waitingCount: _int(json['waitingCount']),
      );
}

/// Where the person asking stands: applied, refused, or already a partner.
class PartnerSelf {
  const PartnerSelf({
    required this.applicationId,
    required this.applicationStatus,
    required this.applicationTerritory,
    required this.decisionReason,
    required this.partnerStatus,
    required this.partnerTierName,
    required this.partnerTerritory,
    required this.contractAwaitingSignature,
  });

  final String? applicationId;
  final String? applicationStatus;
  final String? applicationTerritory;

  /// Why they were refused. Shown to them word for word — an admin wrote it
  /// knowing it would be read by the applicant.
  final String? decisionReason;

  final String? partnerStatus;
  final String? partnerTierName;
  final String? partnerTerritory;
  final bool contractAwaitingSignature;

  bool get isPending => applicationStatus == 'Pending';
  bool get isPartner => partnerStatus != null;

  static PartnerSelf fromJson(Map<String, dynamic> json) => PartnerSelf(
        applicationId: json['applicationId'] as String?,
        applicationStatus: json['applicationStatus'] as String?,
        applicationTerritory: json['applicationTerritory'] as String?,
        decisionReason: json['decisionReason'] as String?,
        partnerStatus: json['partnerStatus'] as String?,
        partnerTierName: json['partnerTierName'] as String?,
        partnerTerritory: json['partnerTerritory'] as String?,
        contractAwaitingSignature: json['contractAwaitingSignature'] == true,
      );

  static const none = PartnerSelf(
    applicationId: null,
    applicationStatus: null,
    applicationTerritory: null,
    decisionReason: null,
    partnerStatus: null,
    partnerTierName: null,
    partnerTerritory: null,
    contractAwaitingSignature: false,
  );
}

/// What the "Become a partner" screen needs, in one call.
class PartnerOpenings {
  const PartnerOpenings({
    required this.tiers,
    required this.territories,
    required this.mine,
  });

  final List<PartnerTier> tiers;
  final List<TerritoryNode> territories;
  final PartnerSelf mine;
}

/// Raised when the server refuses, carrying the sentence it gave.
class PartnerRefused implements Exception {
  const PartnerRefused(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class PartnerRepository {
  PartnerRepository(this.api);

  final ApiClient api;

  /// The city gate. Anonymous — it is asked before anybody signs in.
  ///
  /// Never throws. A failed city lookup must not stop the home screen from
  /// rendering: the right answer when we cannot tell where somebody is, is the
  /// ordinary screen, not an error.
  Future<CityStatus> cityStatus({double? latitude, double? longitude}) async {
    final query = <String, String>{
      if (latitude != null) 'lat': latitude.toString(),
      if (longitude != null) 'lng': longitude.toString(),
    };

    try {
      final response = await api.getJson(
        '/api/v1/cities/status'
        '${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}',
        authenticated: true,
      );
      final payload = response['data'] ?? response;
      if (payload is Map) {
        return CityStatus.fromJson(Map<String, dynamic>.from(payload));
      }
    } catch (_) {
      // Deliberately swallowed. See above.
    }
    return CityStatus.empty;
  }

  /// Joins the waiting list, or changes whether we tell them when it opens.
  ///
  /// There is no "leave" here on purpose: being counted is what makes the city
  /// worth opening and worth a partner, and the thing somebody actually wants to
  /// turn off is the message. So the switch controls the message.
  Future<void> waitlist(String cityId, {required bool notify}) async {
    try {
      await api.postJson('/api/v1/cities/waitlist', {
        'cityId': cityId,
        'notifyOnOpen': notify,
      });
    } on ApiException catch (error) {
      throw PartnerRefused(error.code ?? '', error.message);
    }
  }

  Future<PartnerOpenings> openings() async {
    final Map<String, dynamic> response;
    try {
      response = await api.getJson('/api/v1/partners/openings');
    } on ApiException catch (error) {
      throw PartnerRefused(error.code ?? '', error.message);
    }

    final payload = response['data'] ?? response;
    if (payload is! Map) {
      throw const PartnerRefused(
          'unexpected_response', 'The server sent something unexpected.');
    }

    final map = Map<String, dynamic>.from(payload);
    final mine = map['mine'];

    return PartnerOpenings(
      tiers: _maps(map['tiers']).map(PartnerTier.fromJson).toList(),
      territories:
          _maps(map['territories']).map(TerritoryNode.fromJson).toList(),
      mine: mine is Map
          ? PartnerSelf.fromJson(Map<String, dynamic>.from(mine))
          : PartnerSelf.none,
    );
  }

  Future<PartnerSelf> mine() async {
    try {
      final response = await api.getJson('/api/v1/partners/me');
      final payload = response['data'] ?? response;
      if (payload is Map) {
        return PartnerSelf.fromJson(Map<String, dynamic>.from(payload));
      }
    } on ApiException catch (error) {
      throw PartnerRefused(error.code ?? '', error.message);
    }
    return PartnerSelf.none;
  }

  Future<void> apply({
    required String tierKey,
    required String territoryId,
    String? note,
    String? contactPhone,
  }) async {
    try {
      await api.postJson('/api/v1/partners/applications', {
        'tierKey': tierKey,
        'territoryId': territoryId,
        'note': note,
        'contactPhone': contactPhone,
      });
    } on ApiException catch (error) {
      throw PartnerRefused(error.code ?? '', error.message);
    }
  }

  Future<void> withdraw(String applicationId) async {
    try {
      await api.postJson(
          '/api/v1/partners/applications/$applicationId/withdraw', const {});
    } on ApiException catch (error) {
      throw PartnerRefused(error.code ?? '', error.message);
    }
  }
}

// ── plumbing ────────────────────────────────────────────────────────────────
//
// Top-level, not statics on a class. The model classes above call these from
// their own `fromJson`, and Dart will not resolve another class's private static
// without qualifying it — the mistake that broke a build in this repository once
// already.

/// The maps inside a JSON array, with anything that is not a map dropped.
///
/// Not generic, and not `List<T> _listOf<T>(...)` as it started out: the repo's
/// own `tool/audit_structure.py` does not recognise a top-level generic function
/// and reported it as undeclared. Mapping at the call site reads just as well
/// and keeps the check clean.
List<Map<String, dynamic>> _maps(Object? raw) {
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is Map) out.add(Map<String, dynamic>.from(item));
  }
  return out;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// `6` rather than `6.0`, which is what a target reads as on a contract.
String _plain(double value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();
