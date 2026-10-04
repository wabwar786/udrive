import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../booking/trip_operations_repository.dart';
import 'service_availability_repository.dart';

class TripLocationService {
  TripLocationService(this.repository);
  final TripOperationsRepository repository;
  final Battery _battery = Battery();
  Timer? _timer;
  String? _bookingId;
  String? _status;
  static const _queueKey = 'phase12_location_queue_v1';

  /// How often the live-ride screen publishes, whatever the admin setting.
  ///
  /// Five seconds is what the customer's screen polls at, so every fix sent is
  /// one the customer sees. Combined with [_stationaryGap] a car standing at a
  /// junction sends one fix every thirty seconds instead of six.
  static const int activeTripPingSeconds = 5;

  /// A fix this close to the last one sent is not worth sending...
  static const double _stationaryMeters = 10;

  /// ...unless this long has passed, so the customer still sees the car is
  /// alive. The server applies the same rule and would discard it anyway.
  static const Duration _stationaryGap = Duration(seconds: 30);

  /// Interval chosen by the caller, kept across status changes.
  int? _overrideSeconds;

  /// The newest fix from the live screen's own GPS stream.
  Position? _latest;
  DateTime? _latestAt;

  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastSentAt;

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// Starts publishing this Driver's position.
  ///
  /// The interval comes from the server, so an admin can turn it without a
  /// release — unless [intervalSeconds] is given, which the live-ride screen
  /// does with [activeTripPingSeconds]. It stops the moment the trip ends.
  Future<void> start(
    String bookingId,
    String status, {
    int? intervalSeconds,
  }) async {
    _bookingId = bookingId;
    _status = status;
    if (intervalSeconds != null) _overrideSeconds = intervalSeconds;
    _timer?.cancel();
    await flushQueue();
    final seconds = _overrideSeconds ??
        await ServiceAvailabilityRepository(repository.client)
            .trackingPingSeconds();
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => capture());
    await capture(force: true);
  }

  void updateStatus(String status) {
    if (_bookingId != null && _status != status) start(_bookingId!, status);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _bookingId = null;
    _status = null;
    _overrideSeconds = null;
  }

  /// Hands over a fix from a GPS stream the caller already runs.
  ///
  /// The live-ride screen listens to GPS continuously to move the car on its
  /// own map. Asking the GPS again here for every ping doubled the work and
  /// still produced an older position than the one already on screen.
  void feed(Position position) {
    _latest = position;
    _latestAt = DateTime.now();
  }

  /// Takes one fix and publishes it.
  ///
  /// The fed fix is used when it is fresh; otherwise one is requested with
  /// `bestForNavigation` and a short time limit, because a fix arriving after
  /// the next one was due is worse than no fix at all.
  Future<void> capture({bool force = false}) async {
    final booking = _bookingId;
    if (booking == null) return;
    try {
      Position position;
      final latest = _latest;
      final latestAt = _latestAt;
      if (latest != null &&
          latestAt != null &&
          DateTime.now().difference(latestAt) < const Duration(seconds: 4)) {
        position = latest;
      } else {
        if (!await ensurePermission()) return;
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            timeLimit: Duration(seconds: 6),
          ),
        );
      }

      if (!force && _isStationary(position)) return;

      final battery = await _battery.batteryLevel;
      final point = <String, dynamic>{
        'clientEventId': _eventId(),
        'tripId': booking,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'heading': position.heading.isFinite ? position.heading : null,
        'speedKph':
            position.speed.isFinite ? max(0, position.speed * 3.6) : null,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
        'batteryLevel': battery,
        'permissionStatus': 'granted',
        'source': 'flutter-mobile',
      };
      _lastSentLat = position.latitude;
      _lastSentLng = position.longitude;
      _lastSentAt = DateTime.now();
      await _sendOrQueue(point);
    } catch (_) {}
  }

  bool _isStationary(Position position) {
    final lat = _lastSentLat;
    final lng = _lastSentLng;
    final at = _lastSentAt;
    if (lat == null || lng == null || at == null) return false;
    if (DateTime.now().difference(at) >= _stationaryGap) return false;
    final moved = Geolocator.distanceBetween(
        lat, lng, position.latitude, position.longitude);
    return moved < _stationaryMeters;
  }

  Future<void> _sendOrQueue(Map<String, dynamic> point) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((x) => x == ConnectivityResult.none)) {
      await _enqueue(point);
      return;
    }
    try {
      await repository.sendLocation(point);
      await flushQueue();
    } catch (_) {
      await _enqueue(point);
    }
  }

  Future<void> _enqueue(Map<String, dynamic> point) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_queueKey) ?? <String>[]);
    current.add(jsonEncode(point));
    while (current.length > 150) {
      current.removeAt(0);
    }
    await prefs.setStringList(_queueKey, current);
  }

  Future<void> flushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = List<String>.from(prefs.getStringList(_queueKey) ?? const []);
    if (queue.isEmpty) return;
    final remaining = <String>[];
    for (final raw in queue) {
      try {
        final point = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        await repository.sendLocation(point);
      } catch (_) {
        remaining.add(raw);
      }
    }
    await prefs.setStringList(_queueKey, remaining);
  }

  String _eventId() {
    final r = Random.secure();
    String h(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }
}
