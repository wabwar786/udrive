/// The driver growth system, as the app sees it.
///
/// Every one of these mirrors a DTO the API already sends; none of them invents
/// a field. Anything the server has not configured arrives null or empty and the
/// screen draws nothing for it, which is the whole contract: an install with no
/// campaigns shows a driver no rewards rather than a row of zeroes.
library;

class DriverPresence {
  const DriverPresence({
    required this.isOnline,
    required this.sessionSeconds,
    required this.todaySeconds,
    required this.heartbeatSeconds,
    this.sessionId,
    this.onlineSince,
    this.cityName,
  });

  final bool isOnline;
  final String? sessionId;
  final DateTime? onlineSince;
  final int sessionSeconds;
  final int todaySeconds;
  final int heartbeatSeconds;
  final String? cityName;

  factory DriverPresence.fromJson(Map<String, dynamic> json) => DriverPresence(
        isOnline: json['isOnline'] == true,
        sessionId: json['sessionId']?.toString(),
        onlineSince: _date(json['onlineSince']),
        sessionSeconds: _int(json['sessionSeconds']),
        todaySeconds: _int(json['todaySeconds']),
        heartbeatSeconds: _int(json['heartbeatSeconds'], 60),
        cityName: _text(json['cityName']),
      );

  static const empty = DriverPresence(
    isOnline: false,
    sessionSeconds: 0,
    todaySeconds: 0,
    heartbeatSeconds: 60,
  );
}

class GrowthMilestone {
  const GrowthMilestone({
    required this.title,
    required this.rewardAmount,
    required this.progressValue,
    required this.targetValue,
    required this.status,
    this.description,
    this.creditedAt,
  });

  final String title;
  final String? description;
  final double rewardAmount;
  final double progressValue;
  final double targetValue;

  /// InProgress | Qualified | Credited | OnHold | Expired | Rejected
  final String status;
  final DateTime? creditedAt;

  bool get isCredited => status == 'Credited';
  bool get isQualified => status == 'Qualified';

  double get fraction =>
      targetValue <= 0 ? 0 : (progressValue / targetValue).clamp(0, 1).toDouble();

  factory GrowthMilestone.fromJson(Map<String, dynamic> json) => GrowthMilestone(
        title: _text(json['title']) ?? 'Reward',
        description: _text(json['description']),
        rewardAmount: _double(json['rewardAmount']),
        progressValue: _double(json['progressValue']),
        targetValue: _double(json['targetValue'], 1),
        status: _text(json['status']) ?? 'InProgress',
        creditedAt: _date(json['creditedAt']),
      );
}

class WelcomeBonus {
  const WelcomeBonus({
    required this.title,
    required this.totalAmount,
    required this.unlockedAmount,
    required this.remainingAmount,
    required this.milestones,
    this.nextMilestone,
    this.endsAt,
  });

  final String title;
  final double totalAmount;
  final double unlockedAmount;
  final double remainingAmount;
  final GrowthMilestone? nextMilestone;
  final List<GrowthMilestone> milestones;
  final DateTime? endsAt;

  double get fraction =>
      totalAmount <= 0 ? 0 : (unlockedAmount / totalAmount).clamp(0, 1).toDouble();

  factory WelcomeBonus.fromJson(Map<String, dynamic> json) => WelcomeBonus(
        title: _text(json['title']) ?? 'Welcome bonus',
        totalAmount: _double(json['totalAmount']),
        unlockedAmount: _double(json['unlockedAmount']),
        remainingAmount: _double(json['remainingAmount']),
        nextMilestone: json['nextMilestone'] is Map
            ? GrowthMilestone.fromJson(
                Map<String, dynamic>.from(json['nextMilestone'] as Map))
            : null,
        milestones: _list(json['milestones'])
            .map(GrowthMilestone.fromJson)
            .toList(growable: false),
        endsAt: _date(json['endsAt']),
      );
}

class DriverMission {
  const DriverMission({
    required this.campaignId,
    required this.campaignType,
    required this.title,
    required this.rewardAmount,
    required this.progressValue,
    required this.targetValue,
    required this.status,
    this.description,
    this.zoneName,
    this.windowEndsAt,
  });

  final String campaignId;

  /// DailyMission | PeakHourReward
  final String campaignType;
  final String title;
  final String? description;
  final double rewardAmount;
  final double progressValue;
  final double targetValue;
  final String status;
  final String? zoneName;
  final DateTime? windowEndsAt;

  bool get isPeakHour => campaignType == 'PeakHourReward';

  double get fraction =>
      targetValue <= 0 ? 0 : (progressValue / targetValue).clamp(0, 1).toDouble();

  /// What the progress means in words.
  ///
  /// An online-time mission counts seconds and a ride mission counts rides, and
  /// "4800 / 7200" on a driver's home screen is not a sentence anybody reads.
  /// The unit is inferred from the size of the target because the API sends a
  /// number, not a unit — anything in the thousands is seconds.
  String get progressLabel {
    if (targetValue >= 600) {
      return '${_hm(progressValue.round())} of ${_hm(targetValue.round())}';
    }
    return '${progressValue.round()} of ${targetValue.round()}';
  }

  static String _hm(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  factory DriverMission.fromJson(Map<String, dynamic> json) => DriverMission(
        campaignId: '${json['campaignId'] ?? ''}',
        campaignType: _text(json['campaignType']) ?? 'DailyMission',
        title: _text(json['title']) ?? 'Mission',
        description: _text(json['description']),
        rewardAmount: _double(json['rewardAmount']),
        progressValue: _double(json['progressValue']),
        targetValue: _double(json['targetValue'], 1),
        status: _text(json['status']) ?? 'InProgress',
        zoneName: _text(json['zoneName']),
        windowEndsAt: _date(json['windowEndsAt']),
      );
}

class LaunchStatus {
  const LaunchStatus({
    required this.cityName,
    required this.launchStatus,
    required this.customerCampaignActive,
    required this.verifiedDrivers,
    required this.registeredCustomers,
    required this.requestsThisWeek,
    required this.completedRidesThisWeek,
  });

  final String cityName;
  final String launchStatus;
  final bool customerCampaignActive;
  final int verifiedDrivers;
  final int registeredCustomers;
  final int requestsThisWeek;
  final int completedRidesThisWeek;

  /// The status as a driver would say it.
  String get label => switch (launchStatus) {
        'BuildingNetwork' => 'Building driver network',
        'CampaignSoon' => 'Customer campaign starting soon',
        'CampaignActive' => 'Customer campaign active',
        'PublicLaunch' => 'Public launch live',
        _ => launchStatus,
      };

  /// How far along the four stages are, for the progress strip.
  int get stage => switch (launchStatus) {
        'BuildingNetwork' => 1,
        'CampaignSoon' => 2,
        'CampaignActive' => 3,
        'PublicLaunch' => 4,
        _ => 1,
      };

  factory LaunchStatus.fromJson(Map<String, dynamic> json) => LaunchStatus(
        cityName: _text(json['cityName']) ?? '',
        launchStatus: _text(json['launchStatus']) ?? 'BuildingNetwork',
        customerCampaignActive: json['customerCampaignActive'] == true,
        verifiedDrivers: _int(json['verifiedDrivers']),
        registeredCustomers: _int(json['registeredCustomers']),
        requestsThisWeek: _int(json['requestsThisWeek']),
        completedRidesThisWeek: _int(json['completedRidesThisWeek']),
      );
}

class FoundingDriver {
  const FoundingDriver({
    required this.isFoundingDriver,
    this.sequenceNo,
    this.cityName,
    this.grantedAt,
  });

  final bool isFoundingDriver;
  final int? sequenceNo;
  final String? cityName;
  final DateTime? grantedAt;

  factory FoundingDriver.fromJson(Map<String, dynamic> json) => FoundingDriver(
        isFoundingDriver: json['isFoundingDriver'] == true,
        sequenceNo: json['sequenceNo'] == null ? null : _int(json['sequenceNo']),
        cityName: _text(json['cityName']),
        grantedAt: _date(json['grantedAt']),
      );
}

class DemandZone {
  const DemandZone({
    required this.zoneName,
    required this.level,
    required this.startTime,
    required this.endTime,
    required this.isLive,
    this.reason,
    this.latitude,
    this.longitude,
    this.radiusKm,
  });

  final String zoneName;

  /// High | Medium | Low
  final String level;
  final String? reason;
  final String startTime;
  final String endTime;

  /// True when this came from live traffic rather than an admin's forecast.
  /// The screen must say which, or a driver who crosses town for a guess will
  /// not do it twice.
  final bool isLive;

  final double? latitude;
  final double? longitude;
  final double? radiusKm;

  factory DemandZone.fromJson(Map<String, dynamic> json) => DemandZone(
        zoneName: _text(json['zoneName']) ?? 'Area',
        level: _text(json['level']) ?? 'Low',
        reason: _text(json['reason']),
        startTime: _text(json['startTime']) ?? '',
        endTime: _text(json['endTime']) ?? '',
        isLive: json['isLive'] == true,
        latitude: json['latitude'] == null ? null : _double(json['latitude']),
        longitude: json['longitude'] == null ? null : _double(json['longitude']),
        radiusKm: json['radiusKm'] == null ? null : _double(json['radiusKm']),
      );
}

class DriverUpdate {
  const DriverUpdate({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.publishAt,
    this.actionPath,
  });

  final String id;
  final String category;
  final String title;
  final String body;
  final String? actionPath;
  final DateTime publishAt;

  factory DriverUpdate.fromJson(Map<String, dynamic> json) => DriverUpdate(
        id: '${json['id'] ?? ''}',
        category: _text(json['category']) ?? 'System',
        title: _text(json['title']) ?? '',
        body: _text(json['body']) ?? '',
        actionPath: _text(json['actionPath']),
        publishAt: _date(json['publishAt']) ?? DateTime.now(),
      );
}

/// Everything the driver home screen needs, from one call.
class DriverGrowthHome {
  const DriverGrowthHome({
    required this.presence,
    required this.todayEarnings,
    required this.todayCompletedRides,
    required this.rating,
    required this.walletBalance,
    required this.bonusBalance,
    required this.commissionPercentage,
    required this.demand,
    required this.updates,
    this.acceptanceRate,
    this.activeMission,
    this.welcomeBonus,
    this.launch,
    this.founding,
  });

  final DriverPresence presence;
  final double todayEarnings;
  final int todayCompletedRides;
  final double rating;
  final double? acceptanceRate;
  final double walletBalance;
  final double bonusBalance;
  final double commissionPercentage;
  final DriverMission? activeMission;
  final WelcomeBonus? welcomeBonus;
  final LaunchStatus? launch;
  final FoundingDriver? founding;
  final List<DemandZone> demand;
  final List<DriverUpdate> updates;

  /// The highest demand level anywhere nearby, for the no-ride card.
  DemandZone? get bestDemand {
    const order = {'High': 0, 'Medium': 1, 'Low': 2};
    if (demand.isEmpty) return null;
    final sorted = [...demand]
      ..sort((a, b) => (order[a.level] ?? 3).compareTo(order[b.level] ?? 3));
    return sorted.first;
  }

  factory DriverGrowthHome.fromJson(Map<String, dynamic> json) => DriverGrowthHome(
        presence: json['presence'] is Map
            ? DriverPresence.fromJson(
                Map<String, dynamic>.from(json['presence'] as Map))
            : DriverPresence.empty,
        todayEarnings: _double(json['todayEarnings']),
        todayCompletedRides: _int(json['todayCompletedRides']),
        rating: _double(json['rating']),
        acceptanceRate: json['acceptanceRate'] == null
            ? null
            : _double(json['acceptanceRate']),
        walletBalance: _double(json['walletBalance']),
        bonusBalance: _double(json['bonusBalance']),
        commissionPercentage: _double(json['commissionPercentage'], 10),
        activeMission: json['activeMission'] is Map
            ? DriverMission.fromJson(
                Map<String, dynamic>.from(json['activeMission'] as Map))
            : null,
        welcomeBonus: json['welcomeBonus'] is Map
            ? WelcomeBonus.fromJson(
                Map<String, dynamic>.from(json['welcomeBonus'] as Map))
            : null,
        launch: json['launch'] is Map
            ? LaunchStatus.fromJson(
                Map<String, dynamic>.from(json['launch'] as Map))
            : null,
        founding: json['founding'] is Map
            ? FoundingDriver.fromJson(
                Map<String, dynamic>.from(json['founding'] as Map))
            : null,
        demand: _list(json['demand'])
            .map(DemandZone.fromJson)
            .toList(growable: false),
        updates: _list(json['updates'])
            .map(DriverUpdate.fromJson)
            .toList(growable: false),
      );
}

// ───────────────────────────────────────────────────────────────── parsing

List<Map<String, dynamic>> _list(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false)
    : const [];

double _double(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _int(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
