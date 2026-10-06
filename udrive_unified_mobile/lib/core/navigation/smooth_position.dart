import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// A position and heading that glide from one fix to the next.
///
/// GPS on the driver's phone arrives about once a second, and the customer's
/// screen hears about the car every five. Drawn as it arrives, the car jumps;
/// drawn through this, it drives. Each new fix starts a straight glide from
/// wherever the car is drawn now to the new point, over roughly the time until
/// the next fix is expected — so the car never stops and never overshoots.
///
/// Repaints are capped at about twenty a second. A map marker is a platform
/// call on Android, and sixty of them a second buys nothing the eye can see on
/// a phone that also has to keep GPS and the network going.
class SmoothPosition extends ChangeNotifier {
  SmoothPosition(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;

  LatLng? _value;
  double _heading = 0;

  LatLng? _from;
  LatLng? _to;
  double _fromHeading = 0;
  double _toHeading = 0;
  Duration _duration = const Duration(seconds: 1);
  Duration _lastNotified = Duration.zero;

  /// Ten redraws a second. Each one rebuilds the map's markers, which the
  /// Google plugin sends across to the native map; at twenty a second a cheap
  /// phone fell behind and the map visibly stalled. The glide still looks
  /// continuous at ten.
  static const Duration _frameGap = Duration(milliseconds: 100);

  /// A jump further than this is a teleport (a GPS fix after a tunnel, the
  /// first fix after a cold start) and is drawn as one rather than as a car
  /// racing across the valley.
  static const double _jumpMeters = 500;

  /// Where the car is drawn right now, or null before the first fix.
  LatLng? get value => _value;

  /// Compass bearing the car is drawn at, 0 = north.
  double get heading => _heading;

  /// Glides to [target] over [duration]. [heading] null keeps the current one,
  /// which is right for a car standing still (its GPS heading is meaningless).
  void moveTo(
    LatLng target, {
    double? heading,
    Duration duration = const Duration(seconds: 1),
  }) {
    final current = _value;
    final nextHeading = heading ?? _heading;

    if (current == null ||
        const Distance().as(LengthUnit.Meter, current, target) > _jumpMeters) {
      _ticker.stop();
      _value = target;
      _heading = _normalise(nextHeading);
      notifyListeners();
      return;
    }

    _from = current;
    _to = target;
    _fromHeading = _heading;
    // The short way round: from 350° to 10° is twenty degrees clockwise, not
    // three hundred and forty anticlockwise.
    var delta = _normalise(nextHeading) - _heading;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    _toHeading = _heading + delta;
    _duration = duration <= Duration.zero ? const Duration(seconds: 1) : duration;
    _lastNotified = Duration.zero;

    _ticker.stop();
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      _ticker.stop();
      return;
    }

    final t = (elapsed.inMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
    _value = LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
    _heading = _normalise(_fromHeading + (_toHeading - _fromHeading) * t);

    final finished = t >= 1.0;
    if (finished || elapsed - _lastNotified >= _frameGap) {
      _lastNotified = elapsed;
      notifyListeners();
    }
    if (finished) _ticker.stop();
  }

  static double _normalise(double degrees) => ((degrees % 360) + 360) % 360;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
