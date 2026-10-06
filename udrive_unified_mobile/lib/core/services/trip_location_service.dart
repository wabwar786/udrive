import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/auth_models.dart' show ApiException;
import '../booking/trip_operations_repository.dart';
import '../widgets/driver_tracking_suspension.dart';
import 'service_availability_repository.dart';

class TripLocationService {
  /// [yieldToLiveScreen] is set by the app-wide coordinator: its pings stop
  /// the moment the live-ride screen takes over, instead of on the
  /// coordinator's next twenty-second tick. Both used to publish together for
  /// those seconds, two fixes under two seconds apart were refused, and the
  /// refused ones were queued and sent again and again.
  TripLocationService(this.repository, {this.yieldToLiveScreen = false});
  final TripOperationsRepository repository;
  final bool yieldToLiveScreen;
  final Battery _battery = Battery();
  Timer? _timer;
  String? _bookingId;
  String? _status;

  /// v2: the v1 queue held points the server would never take (finished
  /// trips, out-of-order fixes) and is abandoned rather than replayed.
  static const _queueKey = 'phase12_location_queue_v2';
  static const _oldQueueKey = 'phase12_location_queue_v1';

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

  /// Points kept while there is no signal: the last few minutes of the
  /// current trip only, so the trip's history has no gap. Older points and
  /// other trips' points are dropped — the live position is what matters.
  static const int _queueLimit = 30;
  static const Duration _queueMaxAge = Duration(minutes: 10);

  /// Queued points sent per attempt. The old queue was replayed in full —
  /// up to 150 requests — behind every new fix, which used up the per-minute
  /// allowance and got the new fixes refused too.
  static const int _flushBatch = 5;

  static const Set<String> _endedStatuses = {
    'TripCompleted',
    'Cancelled',
    'NoShow',
  };

  /// Interval chosen by the caller, kept across status changes.
  int? _overrideSeconds;

  /// The newest fix from the live screen's own GPS stream.
  Position? _latest;
  DateTime? _latestAt;

  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastSentAt;

  bool _flushing = false;

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
  ///
  /// The first fix goes out before anything queued: the queue used to be
  /// replayed first, request by request, and on a weak signal the live
  /// position did not start for minutes.
  Future<void> start(
    String bookingId,
    String status, {
    int? intervalSeconds,
  }) async {
    if (_endedStatuses.contains(status)) {
      stop();
      await clearQueue();
      return;
    }
    _bookingId = bookingId;
    _status = status;
    if (intervalSeconds != null) _overrideSeconds = intervalSeconds;
    _timer?.cancel();
    int? seconds = _overrideSeconds;
    if (seconds == null) {
      try {
        seconds = await ServiceAvailabilityRepository(repository.client)
            .trackingPingSeconds();
      } catch (_) {
        seconds = null;
      }
    }
    final interval = seconds ?? 10;
    // stop() may have run while the interval was being fetched.
    if (_bookingId != bookingId) return;
    _timer = Timer.periodic(Duration(seconds: interval), (_) => capture());
    await capture(force: true);
    unawaited(flushQueue());
  }

  /// A finished or cancelled trip stops publishing and forgets its queue —
  /// the server refuses those points (409), and a refused point used to stay
  /// queued and be sent again behind every fix of every later ride.
  void updateStatus(String status) {
    if (_endedStatuses.contains(status)) {
      stop();
      unawaited(clearQueue());
      return;
    }
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
    if (yieldToLiveScreen && DriverTrackingSuspension.isSuspended) return;
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

      int? battery;
      try {
        battery = await _battery.batteryLevel;
      } catch (_) {
        battery = null;
      }
      final point = <String, dynamic>{
        'clientEventId': _eventId(),
        'tripId': booking,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'heading': position.heading.isFinite && position.heading >= 0
            ? position.heading
            : null,
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

  /// True when the point should be kept for later: no answer at all (no
  /// signal, timeout) or the server failing. Any answer in the 4xx range —
  /// the trip is over, the point is malformed, the allowance is used up — is
  /// final; keeping it only meant sending it again forever.
  static bool _worthRetrying(Object error) {
    if (error is ApiException) {
      final code = error.statusCode ?? 0;
      return code == 0 || code >= 500;
    }
    return true;
  }

  Future<void> _sendOrQueue(Map<String, dynamic> point) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((x) => x == ConnectivityResult.none)) {
      await _enqueue(point);
      return;
    }
    try {
      await repository.sendLocation(point);
      unawaited(flushQueue());
    } catch (error) {
      if (_worthRetrying(error)) await _enqueue(point);
    }
  }

  Future<void> _enqueue(Map<String, dynamic> point) async {
    final prefs = await SharedPreferences.getInstance();
    final current = _fresh(prefs.getStringList(_queueKey) ?? <String>[]);
    current.add(jsonEncode(point));
    while (current.length > _queueLimit) {
      current.removeAt(0);
    }
    await prefs.setStringList(_queueKey, current);
  }

  /// Queued points still worth sending: this trip's, from the last few
  /// minutes. With no trip running, nothing is.
  List<String> _fresh(List<String> raw) {
    final booking = _bookingId;
    if (booking == null) return <String>[];
    final cutoff = DateTime.now().toUtc().subtract(_queueMaxAge);
    final kept = <String>[];
    for (final item in raw) {
      try {
        final point = Map<String, dynamic>.from(jsonDecode(item) as Map);
        final at = DateTime.tryParse('${point['deviceTimestamp']}');
        if (point['tripId'] == booking && at != null && at.isAfter(cutoff)) {
          kept.add(item);
        }
      } catch (_) {
        // Unreadable: dropped.
      }
    }
    return kept;
  }

  /// Sends a few queued points, oldest first, and stops at the first one that
  /// gets no answer — the signal is gone again, and the rest can wait.
  Future<void> flushQueue() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_oldQueueKey)) await prefs.remove(_oldQueueKey);
      final queue = _fresh(prefs.getStringList(_queueKey) ?? const []);
      if (queue.isEmpty) {
        await prefs.remove(_queueKey);
        return;
      }
      var sent = 0;
      while (queue.isNotEmpty && sent < _flushBatch) {
        final raw = queue.first;
        try {
          final point = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          await repository.sendLocation(point);
          queue.removeAt(0);
          sent++;
        } catch (error) {
          if (_worthRetrying(error)) break;
          queue.removeAt(0);
        }
      }
      await prefs.setStringList(_queueKey, queue);
    } catch (_) {
      // Storage unavailable: nothing queued is lost that matters.
    } finally {
      _flushing = false;
    }
  }

  Future<void> clearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);
      await prefs.remove(_oldQueueKey);
    } catch (_) {}
  }

  String _eventId() {
    final r = Random.secure();
    String h(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }
}
