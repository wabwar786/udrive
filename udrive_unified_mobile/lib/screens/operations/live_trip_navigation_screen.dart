import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/booking/trip_completion_queue.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/media/alert_sound.dart';
import '../../core/booking/trip_chat_repository.dart';
import '../../core/maps/ud_map.dart';
import '../../core/maps/ud_vehicle_sprites.dart';
import '../../core/navigation/live_route.dart';
import '../../core/navigation/route_tracker.dart';
import '../../core/navigation/smooth_position.dart';
import '../../core/navigation/turn_guide.dart';
import '../../core/network/api_config.dart';
import '../../core/vehicles/vehicle_image_repository.dart';
import '../../core/services/screen_awake.dart';
import '../../core/services/trip_location_service.dart';
import '../../core/widgets/collapsible_map_sheet.dart';
import '../../core/widgets/driver_tracking_suspension.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/state/app_controller.dart';
import '../customer/driver_offers_screen.dart';
import 'trip_chat_screen.dart';
import 'trip_rating_screen.dart';
import '../../models/auth_models.dart' show ApiException;
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';

class DriverLiveNavigationScreen extends StatefulWidget {
  const DriverLiveNavigationScreen({
    required this.trip,
    required this.repository,
    super.key,
  });

  final MobileTrip trip;
  final TripOperationsRepository repository;

  @override
  State<DriverLiveNavigationScreen> createState() =>
      _DriverLiveNavigationScreenState();
}

class _DriverLiveNavigationScreenState extends State<DriverLiveNavigationScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TripLocationService _locationService;
  final UdMapController _map = UdMapController();
  Timer? _timer;
  TripTracking? _tracking;
  Position? _position;
  String? _error;
  bool _starting = true;
  bool _actionBusy = false;
  late String _currentStatus;

  /// The car as drawn: glides between GPS fixes instead of jumping.
  late final SmoothPosition _car = SmoothPosition(this);

  /// The phone's own GPS, about once a second. Nothing here waits on the
  /// network: the car, the line shrinking behind it, the turn banner and the
  /// Urdu voice all run from this stream and the stored route.
  StreamSubscription<Position>? _gps;

  /// The road for this leg — fetched once, then followed offline.
  LiveRoute? _route;
  RouteTracker? _tracker;
  TurnGuide? _guide;
  RouteFix? _fix;
  TurnBanner? _banner;

  /// The road still ahead. Replaced only when the car moves on a segment or
  /// every few seconds, so the map is not handed a new list on every frame.
  List<LatLng> _remaining = const [];
  int _remainingSegment = -1;
  DateTime _remainingAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _routeBusy = false;

  /// Set once the server says no more paid routes today (or none at all) —
  /// the driver keeps the last road and the app stops asking.
  bool _routeCapped = false;

  /// When the car was first seen more than [_offRouteMeters] from the road.
  DateTime? _offRouteSince;
  DateTime _lastRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Earliest time to ask again after asking for the first road failed
  /// (no signal, Google unavailable). The GPS fires every second; without
  /// this a dead connection would be retried every second.
  DateTime _nextRouteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _routeRetryGap = Duration(seconds: 20);

  // A driver who takes another road sees it highlighted within a few
  // seconds: six seconds off the line (was ten) and a GPS fix within fifty
  // metres (was thirty — under these hills a phone rarely reports better, so
  // the check almost never passed and the old road stayed on screen).
  static const double _offRouteMeters = 40;
  static const Duration _offRouteFor = Duration(seconds: 6);
  static const Duration _rerouteGap = Duration(seconds: 20);
  static const double _rerouteAccuracyMeters = 50;

  /// The bearing the camera last turned to, kept while the car stands still.
  double _cameraBearing = 0;

  /// Who the Driver is collecting, from their history on the platform.
  PassengerStanding? _passenger;

  /// Messages from the Customer, and the ones already announced.
  ///
  /// The Driver had no message polling at all: a Customer could write "I am at
  /// the blue gate" and the Driver would never know, because the only place
  /// messages were read was inside the chat screen.
  List<TripMessage> _customerMessages = const [];
  final Set<String> _announcedMessages = <String>{};
  bool _messagesLoadedOnce = false;
  Timer? _messagePoll;

  /// True once the Driver has moved the map themselves.
  ///
  /// After that the camera stops following. A map that snaps back every ten
  /// seconds cannot be used to look at the junction ahead, which is the only
  /// reason a Driver would touch it while driving.
  bool _cameraHeld = false;

  /// Where and how the camera was last pointed, so a car standing still does
  /// not send the map a new camera every second. Each move made Google start
  /// fetching tiles again; on a weak signal they never finished and the map
  /// stayed blank.
  LatLng? _lastCameraAt;
  double _lastCameraBearing = 0;
  double _lastCameraZoom = 0;

  /// True while a status refresh is out, so a slow one is not joined by the
  /// next — they piled up on a weak signal and competed with the map tiles.
  bool _refreshing = false;

  /// Refreshes in a row that failed. Three or more: the weak-signal note.
  int _failedRefreshes = 0;

  /// The phone's last known position, read once at start without the network,
  /// so the map opens where the driver is rather than on a default city.
  LatLng? _lastKnown;

  /// False until the map has somewhere real to open: a GPS fix, the last
  /// known position, the trip, or 1.5 seconds without any of them.
  bool _mapCanOpen = false;

  /// The Google Maps warning is shown once per ride.
  bool _warnedAboutExternalNav = false;

  /// The driver completed the trip with no internet. It is kept on the phone
  /// (TripCompletionQueue) and sent as soon as the connection is back.
  bool _completionPending = false;

  /// Set once this screen is closing because the trip is over, so a refresh
  /// that lands at the same moment does not close it twice.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The screen stays on while the ride is open. A screen that switched off
    // paused the app, and with it the location the customer is watching.
    unawaited(ScreenAwake.hold());
    unawaited(_readLastKnown());
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_mapCanOpen) setState(() => _mapCanOpen = true);
    });
    // This screen publishes the position itself, so the app-wide coordinator
    // steps aside while it is open rather than both of them sending the same
    // fixes.
    DriverTrackingSuspension.suspend();
    _locationService = TripLocationService(widget.repository);
    _currentStatus = widget.trip.tripStatus;
    UrduVoice.instance.prepare().then((_) {
      if (mounted) setState(() {});
    });
    _startGps();
    _begin();
    TripCompletionQueue.isPending(widget.trip.bookingId).then((pending) {
      if (pending && mounted) setState(() => _completionPending = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPassenger();
      _pollMessages();
    });
    _messagePoll =
        Timer.periodic(const Duration(seconds: 10), (_) => _pollMessages());
  }

  /// Starts the live screen.
  ///
  /// The order matters, and it used to be the wrong way round. Three calls ran
  /// one after another before anything was drawn — a status change, a location
  /// service start that itself fetches the ping interval, then a full refresh —
  /// so a Driver pressing "Open live ride" watched a blank screen through all
  /// of them. On a mobile connection that is several seconds of nothing.
  ///
  /// The refresh goes first now, because it is the only one that puts anything
  /// on screen. The status change and the location service follow, and neither
  /// is something the Driver is waiting to see.
  Future<void> _begin() async {
    try {
      await _refresh();
      _ready();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());

      if (_currentStatus == 'DriverAccepted') {
        // On its own: when this failed (a weak signal), the location service
        // below never started, and the customer saw no car for the whole
        // ride. The next refresh still shows the right status.
        try {
          await widget.repository.driverStatus(
            widget.trip.bookingId,
            'DriverEnRoute',
            reason: 'Driver started travelling to the pickup location.',
          );
          _currentStatus = 'DriverEnRoute';
        } catch (error) {
          if (mounted && !_isNoConnection(error)) {
            setState(() => _error = error.toString());
          }
        }
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
    if (!mounted) return;
    try {
      await _locationService.start(
        widget.trip.bookingId,
        _currentStatus,
        intervalSeconds: TripLocationService.activeTripPingSeconds,
      );
    } catch (_) {
      // capture() swallows its own failures; nothing here should stop the
      // screen. The timer is already running.
    }
    unawaited(_ensureRoute());
  }

  /// Reads the phone's last known position. No network, a few milliseconds —
  /// enough to open the map where the driver is.
  Future<void> _readLastKnown() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted || last == null) return;
      setState(() => _lastKnown = LatLng(last.latitude, last.longitude));
    } catch (_) {
      // None stored, or no permission yet: the map opens on the trip instead.
    }
  }

  /// Back from another app or a locked screen.
  ///
  /// Android stops the GPS stream while the app is behind another one, and the
  /// customer's map stops with it. On return the position goes out at once —
  /// not on the next tick — the stream is reopened, and the status refreshed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(ScreenAwake.reapply());
    unawaited(_startGps());
    unawaited(_locationService.capture(force: true));
    unawaited(_locationService.flushQueue());
    unawaited(_refresh());
  }

  /// Clears the blocking overlay as soon as there is a map to look at.
  ///
  /// `_starting` draws a full-screen spinner, and it used to stay up until all
  /// three start-up calls had finished. The map underneath was ready long
  /// before that — the Driver was being shown a spinner over a working screen.
  void _ready() {
    if (mounted && _starting) setState(() => _starting = false);
  }

  /// Status, the customer's details and the trip's own record — every ten
  /// seconds. The map does not wait for this any more; it moves with the GPS
  /// stream in [_onGps].
  Future<void> _refresh() async {
    if (_refreshing || _closing) return;
    _refreshing = true;
    try {
      // A completion saved offline goes out first, now that there may be a
      // signal again.
      if (_completionPending) {
        final sent = await TripCompletionQueue.sendAll(widget.repository);
        if (sent.contains(widget.trip.bookingId)) {
          _finish('Trip completed.');
          return;
        }
      }
      final tracking = await widget.repository
          .tracking(widget.trip.bookingId, path: false)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;

      // Ended elsewhere — UDrive completed it from the admin panel while this
      // phone had no signal, or it was cancelled. Location stops and the
      // screen closes; the driver is free for the next ride.
      if (tracking.tripStatus == 'TripCompleted' ||
          tracking.tripStatus == 'Cancelled') {
        await TripCompletionQueue.forget(widget.trip.bookingId);
        _finish(tracking.tripStatus == 'Cancelled'
            ? 'This trip was cancelled.'
            : _completionPending
                ? 'Trip completed.'
                : 'UDrive has completed this trip. You are free for the next ride.');
        return;
      }
      setState(() {
        _tracking = tracking;
        _currentStatus = tracking.tripStatus;
        _error = null;
        _failedRefreshes = 0;
      });

      // The customer is aboard: the stored road was to the pickup, and the
      // next one goes to the destination. Asked once; the server returns the
      // stored destination road if it already has it.
      final route = _route;
      if (route != null && route.leg != _expectedLeg && _legIsLive) {
        _clearRoute();
        unawaited(_ensureRoute());
      }

      // No GPS yet (indoors, a cold start): put the camera on the last
      // position the server has, so the screen is not a map of nowhere.
      if (_position == null && !_cameraHeld) {
        final at = _currentPoint ?? _targetPoint;
        if (at != null) _map.moveTo(at, zoom: 17.5);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          // No answer at all is shown by the weak-signal note, not as red
          // text under the buttons.
          _error = _isNoConnection(error) ? null : error.toString();
          _failedRefreshes++;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Closes the screen because the trip is over.
  void _finish(String message) {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    _locationService.updateStatus('TripCompleted');
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Completes the trip — straight away when there is a signal, and on the
  /// phone when there is not.
  ///
  /// With no signal this used to spin for 25 seconds, fail with a raw
  /// exception, and leave the trip open: the driver stayed "busy" and got no
  /// further rides until someone noticed.
  Future<void> _completeTrip() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await widget.repository
          .driverStatus(widget.trip.bookingId, 'TripCompleted')
          .timeout(const Duration(seconds: 12));
      await TripCompletionQueue.forget(widget.trip.bookingId);
      _finish('Trip completed.');
    } catch (error) {
      if (_isNoConnection(error)) {
        await TripCompletionQueue.keep(widget.trip.bookingId);
        _locationService.updateStatus('TripCompleted');
        if (mounted) {
          setState(() {
            _completionPending = true;
            _error = null;
          });
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// "Send now" on the pending-completion banner.
  Future<void> _sendPendingCompletion() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final sent = await TripCompletionQueue.sendAll(widget.repository);
      if (sent.contains(widget.trip.bookingId)) {
        _finish('Trip completed.');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Still no internet. It will be sent automatically.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // ─────────────────────────────────────────────────────────── live GPS

  LocationSettings get _gpsSettings {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );
  }

  Future<void> _startGps() async {
    try {
      if (!await _locationService.ensurePermission()) return;
      if (!mounted) return;
      await _gps?.cancel();
      _gps = Geolocator.getPositionStream(locationSettings: _gpsSettings)
          .listen(_onGps, onError: (_) {});
    } catch (_) {
      // No GPS on this device or permission refused; the ten-second refresh
      // still shows the server's last known position.
    }
  }

  void _onGps(Position position) {
    if (!mounted) return;
    _position = position;
    _locationService.feed(position);

    final raw = LatLng(position.latitude, position.longitude);
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final moving = speed > 1.5;

    var display = raw;
    double? heading = moving && position.heading.isFinite && position.heading >= 0
        ? position.heading
        : null;

    final tracker = _tracker;
    if (tracker != null) {
      final fix = tracker.locate(raw);
      _fix = fix;

      // Close to the road: draw the car on it, pointing along it. GPS that
      // wanders ten metres either side would otherwise show the car driving
      // through the houses beside the road.
      if (fix.offRouteMeters < 25) {
        display = fix.snapped;
        if (moving) heading = fix.bearing;
      }

      final now = DateTime.now();
      if (fix.segmentIndex != _remainingSegment ||
          now.difference(_remainingAt) > const Duration(seconds: 3)) {
        _remaining = tracker.remaining(fix);
        _remainingSegment = fix.segmentIndex;
        _remainingAt = now;
      }

      _watchForDetour(fix, position.accuracy);

      final guide = _guide;
      if (guide != null) {
        UrduVoice.instance.say(
          guide.announcements(fix, speedMps: speed, toPickup: _headingToPickup),
        );
        _banner = guide.banner(fix, toPickup: _headingToPickup);
      }
    } else if (!_routeBusy && !_routeCapped) {
      unawaited(_ensureRoute());
    }

    _car.moveTo(display, heading: heading);

    if (heading != null) _cameraBearing = heading;
    if (!_cameraHeld) _followCamera(display, _zoomForSpeed(speed));

    setState(() {});
  }

  /// Moves the camera with the car — but not for a car standing still.
  ///
  /// A move under three metres with the same heading and zoom is skipped:
  /// at a junction or in traffic the camera used to be re-sent every second,
  /// and each time Google began loading tiles again.
  void _followCamera(LatLng at, double zoom) {
    final last = _lastCameraAt;
    if (last != null) {
      final moved = const Distance().as(LengthUnit.Meter, last, at);
      final turned = ((_cameraBearing - _lastCameraBearing + 540) % 360 - 180).abs();
      if (moved < 3 && turned < 8 && zoom == _lastCameraZoom) return;
    }
    _lastCameraAt = at;
    _lastCameraBearing = _cameraBearing;
    _lastCameraZoom = zoom;
    _map.follow(at, zoom: zoom, bearing: _cameraBearing, tilt: 30);
  }

  /// Close — the street the car is on and the next junction. Slightly wider
  /// on an open road so a turn is on screen before it is reached.
  ///
  /// All at 17 or above: Google's map data stops at about that level and is
  /// scaled beyond it, so changing between these never downloads new tiles.
  /// The old 15.6–17.5 range did, every time the speed changed.
  static double _zoomForSpeed(double metresPerSecond) {
    final kph = metresPerSecond * 3.6;
    if (kph < 15) return 18.5;
    if (kph < 40) return 18;
    if (kph < 70) return 17.5;
    return 17;
  }

  // ───────────────────────────────────────────────────────────── route

  String get _expectedLeg => _currentStatus == 'TripStarted' ? 'destination' : 'pickup';

  bool get _legIsLive => const {
        'DriverAssigned',
        'DriverAccepted',
        'DriverEnRoute',
        'DriverArrived',
        'TripStarted',
      }.contains(_currentStatus);

  void _clearRoute() {
    _nextRouteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _route = null;
    _tracker = null;
    _guide = null;
    _fix = null;
    _banner = null;
    _remaining = const [];
    _remainingSegment = -1;
    _offRouteSince = null;
    _routeCapped = false;
  }

  void _setRoute(LiveRoute route) {
    _route = route;
    _tracker = RouteTracker(route.points);
    _guide = TurnGuide(route: route, tracker: _tracker!);
    _remaining = route.points;
    _remainingSegment = -1;
    _offRouteSince = null;

    final position = _position;
    if (position != null) {
      final fix = _tracker!.locate(LatLng(position.latitude, position.longitude));
      _fix = fix;
      _remaining = _tracker!.remaining(fix);
      _remainingSegment = fix.segmentIndex;
      _banner = _guide!.banner(fix, toPickup: _headingToPickup);
    }
  }

  /// Gets the road for this leg. The server answers from its stored copy
  /// unless [reroute] is set and the driver really has left the road, so
  /// calling this freely costs nothing.
  Future<void> _ensureRoute({bool reroute = false}) async {
    if (_routeBusy || !_legIsLive) return;
    if (reroute && _routeCapped) return;
    if (!reroute && DateTime.now().isBefore(_nextRouteAttempt)) return;
    final from = _currentPoint;
    if (from == null) return;

    _routeBusy = true;
    if (reroute) {
      _lastRerouteAt = DateTime.now();
      UrduVoice.instance.say(const ['rerouting']);
    }

    try {
      final position = _position;
      final heading = position != null &&
              position.speed.isFinite &&
              position.speed > 1.5 &&
              position.heading.isFinite &&
              position.heading >= 0
          ? position.heading
          : null;
      final result = await LiveRouteRepository(widget.repository.client)
          .ensure(widget.trip.bookingId, from, reroute: reroute, heading: heading);
      if (!mounted) return;

      final route = result.route;
      if (route == null) _nextRouteAttempt = DateTime.now().add(_routeRetryGap);
      setState(() {
        if (route != null && (route.id != _route?.id || result.leg != _route?.leg)) {
          _setRoute(route);
        }
        if (result.capped || result.reason == 'reroute_limit') {
          _routeCapped = true;
        }
      });
    } catch (_) {
      // No signal. The old road stays on screen and the next detour check
      // tries again once the gap has passed.
      _nextRouteAttempt = DateTime.now().add(_routeRetryGap);
    } finally {
      _routeBusy = false;
      if (reroute) _offRouteSince = null;
    }
  }

  /// Asks for a new road once the car has been off the old one for a while.
  ///
  /// Ten seconds and forty metres, with a fix accurate enough to trust: a
  /// junction taken wide or a GPS jump under a cliff does not count. The
  /// server repeats the check before it spends anything.
  void _watchForDetour(RouteFix fix, double accuracy) {
    if (_routeCapped || _routeBusy) return;
    final trustworthy = accuracy.isFinite && accuracy <= _rerouteAccuracyMeters;
    if (fix.offRouteMeters <= _offRouteMeters || !trustworthy) {
      _offRouteSince = null;
      return;
    }
    final now = DateTime.now();
    _offRouteSince ??= now;
    if (now.difference(_offRouteSince!) >= _offRouteFor &&
        now.difference(_lastRerouteAt) >= _rerouteGap) {
      unawaited(_ensureRoute(reroute: true));
    }
  }

  /// Opens the phone's navigation app at whichever end of the trip is next.
  ///
  /// A geo: URI first, which Android hands to whatever the Driver actually
  /// uses; the Google Maps web URL as the fallback, which works on iOS and in
  /// a browser.
  Future<void> _openExternalNavigation() async {
    final target = _targetPoint;
    if (target == null) return;

    // While another app is in front, Android stops UDrive's GPS — there is no
    // background location — and the customer's map stops with it. Said once
    // per ride, before it happens, rather than discovered by the customer.
    if (!_warnedAboutExternalNav) {
      final go = await showUdSheet<bool>(
        context: context,
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Text(
              'Your customer stops seeing the car',
              style: AppType.h2.copyWith(color: AppText.primary),
            ),
            const SizedBox(height: 6),
            Text(
              'While Google Maps is open, UDrive cannot share your location. '
              'The car stops moving on your customer\'s map until you come '
              'back to UDrive.',
              style: AppType.body2.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 18),
            UdButton(
              label: 'Stay in UDrive',
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
            const SizedBox(height: 10),
            UdButton.ghost(
              label: 'Open Google Maps anyway',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      _warnedAboutExternalNav = true;
    }

    final lat = target.latitude;
    final lng = target.longitude;

    for (final uri in [
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
    ]) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {
        // Try the next form rather than failing the whole action.
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app available.')),
      );
    }
  }

  /// Reads the passenger's standing, once.
  ///
  /// Their history does not change during a trip, so polling it would be pure
  /// noise on a screen that already runs two timers.
  Future<void> _loadPassenger() async {
    final controller = AppControllerScope.of(context);
    final standing = await TripChatRepository(controller.apiClient)
        .passenger(widget.trip.bookingId);
    if (!mounted || standing == null) return;
    setState(() => _passenger = standing);
  }

  /// Opens the conversation, and stands this screen's polling down while it is.
  ///
  /// Nothing on this screen is visible behind the chat, so its refresh and its
  /// own message check are spending requests nobody can see — on top of the
  /// chat's own poll, against a per-IP budget that several phones on one
  /// mobile network share. Spending it produced a rate-limit rejection that
  /// surfaced in the conversation as "Please wait a moment and try again",
  /// seconds after a message that had actually been sent.
  ///
  /// The location service is deliberately *not* paused: the customer is
  /// watching this driver move on a map, and a chat window is no reason to
  /// stop telling them where the car is.
  Future<void> _openChat() async {
    _timer?.cancel();
    _messagePoll?.cancel();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripChatScreen(
          bookingId: widget.trip.bookingId,
          myRole: 'Driver',
          otherPartyName: widget.trip.customerName,
        ),
      ),
    );
    if (!mounted) return;

    // Catch up on what changed while the conversation was open, then resume.
    await _refresh();
    if (!mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _messagePoll =
        Timer.periodic(const Duration(seconds: 10), (_) => _pollMessages());
  }

  Future<void> _callCustomer() async {
    final phone = widget.trip.customerPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _startTripWithOtp() async {
    if (_actionBusy) return;
    final controller = TextEditingController();

    // Why this dialog carries its own error line.
    //
    // It used to validate silently: "Start ride" ran the same regular
    // expression, and on anything that was not four digits it simply did
    // nothing — no message, no shake, nothing. A Driver who typed three
    // digits, or whose keyboard slipped in a space, pressed the button and
    // watched the screen sit there. From the outside the app looks broken and
    // the ride never starts, which is exactly the report that brought us here.
    //
    // So: digits only at the keyboard, a reason shown the moment the button is
    // pressed on a bad value, and the reason cleared as soon as they type.
    final otpFieldKey = GlobalKey<_TripOtpFieldState>();
    final otp = await showUdDialog<String>(
      context: context,
      title: 'Start the trip',
      // Says what the code is for, not just what to type.
      //
      // "Enter Trip OTP" tells a Driver the mechanics and none of the
      // purpose, and a step whose purpose is unclear is one people work
      // around — asking for the code through a car window, or starting
      // the trip with the wrong passenger aboard.
      message: 'Ask the passenger for the 4-digit code in their app.\n\n'
          'It confirms the right person is in your vehicle, and it starts '
          'the fare. Nobody can be charged for a trip they did not take, '
          'and you cannot be blamed for one you did not carry.',
      content: _TripOtpField(key: otpFieldKey, controller: controller),
      actions: [
        Builder(
          builder: (dialogContext) => UdButtonRow(
            children: [
              UdButton.outline(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialogContext),
              ),
              UdButton.primary(
                label: 'Start ride',
                onPressed: () {
                  final value = controller.text.trim();
                  if (RegExp(r'^\d{4}$').hasMatch(value)) {
                    Navigator.pop(dialogContext, value);
                    return;
                  }
                  // Say why nothing happened, instead of nothing happening.
                  otpFieldKey.currentState?.showProblem(
                    value.isEmpty
                        ? 'Enter the 4-digit code from the passenger\'s app.'
                        : 'That is ${value.length} digit'
                            '${value.length == 1 ? '' : 's'} — the code is exactly 4.',
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
    controller.dispose();
    if (otp == null || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await widget.repository.driverStatus(
        widget.trip.bookingId,
        'TripStarted',
        reason: 'Customer boarded and Trip OTP was verified.',
        tripOtp: otp,
      );
      _currentStatus = 'TripStarted';
      _locationService.updateStatus('TripStarted');
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP verified. Ride started.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// Reasons a Driver might have to drop a ride they accepted.
  ///
  /// A fixed list rather than a free text box. A reason nobody can count is a
  /// reason nobody acts on, and these are the ones that should show up in
  /// operations reporting when one driver keeps producing them.
  static const _cancelReasons = <String>[
    'Vehicle problem',
    'Customer is not at the pickup point',
    'Customer asked me to cancel',
    'Pickup point is not reachable',
    'Road closed or blocked',
    'Personal emergency',
  ];

  /// Cancels an accepted ride, with a reason recorded against it.
  ///
  /// The reason is required. A cancellation with no cause attached tells
  /// operations nothing, and it is the Customer who is left standing there.
  Future<void> _cancelWithReason() async {
    if (_actionBusy) return;

    String? chosen;
    final note = TextEditingController();

    final confirmed = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                'Cancel this ride?',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'The customer is told immediately and the request goes back '
                'to other drivers.',
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 16),
              UdListGroup(
                children: [
                  for (final reason in _cancelReasons)
                    UdListRow(
                      title: reason,
                      leading: UdRadio(
                        selected: chosen == reason,
                        onTap: () => setSheet(() => chosen = reason),
                      ),
                      onTap: () => setSheet(() => chosen = reason),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: note,
                label: 'Anything else',
                labelSuffix: '(optional)',
                maxLength: 200,
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 18),
              UdButton(
                label: 'Cancel ride',
                variant: UdButtonVariant.dangerSolid,
                onPressed: chosen == null
                    ? null
                    : () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 10),
              UdButton.ghost(
                label: 'Keep this ride',
                onPressed: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      ),
    );

    final reason = chosen;
    final extra = note.text.trim();
    note.dispose();

    if (confirmed != true || reason == null || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await widget.repository.driverStatus(
        widget.trip.bookingId,
        'Cancelled',
        reason: extra.isEmpty ? reason : '$reason — $extra',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    if (status == 'TripCompleted') return _completeTrip();
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await widget.repository.driverStatus(widget.trip.bookingId, status);
      _currentStatus = status;
      _locationService.updateStatus(status);
      await _refresh();
      if (status == 'DriverArrived' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer notified that you have arrived.')),
        );
      }
      if (status == 'TripCompleted' && mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// Back to following the car after the driver has moved the map.
  void _resumeFollowing() {
    setState(() => _cameraHeld = false);
    final at = _car.value ?? _currentPoint;
    if (at == null) return;
    final speed = _position?.speed ?? 0;
    _lastCameraAt = null;
    _followCamera(at, _zoomForSpeed(speed.isFinite ? speed : 0));
  }

  LatLng? get _currentPoint {
    if (_position != null) {
      return LatLng(_position!.latitude, _position!.longitude);
    }
    final location = _tracking?.driverLocation;
    return location == null ? null : LatLng(location.latitude, location.longitude);
  }

  LatLng? get _pickupPoint {
    final t = _tracking;
    if (t?.pickupLatitude == null || t?.pickupLongitude == null) return null;
    return LatLng(t!.pickupLatitude!, t.pickupLongitude!);
  }

  LatLng? get _destinationPoint {
    final t = _tracking;
    if (t?.destinationLatitude == null || t?.destinationLongitude == null) {
      return null;
    }
    return LatLng(t!.destinationLatitude!, t.destinationLongitude!);
  }

  bool get _headingToPickup =>
      _currentStatus == 'DriverAccepted' ||
      _currentStatus == 'DriverEnRoute' ||
      _currentStatus == 'DriverArrived' ||
      _currentStatus == 'Emergency';

  LatLng? get _targetPoint =>
      _headingToPickup ? _pickupPoint : _destinationPoint;

  String get _targetLabel =>
      _headingToPickup ? widget.trip.pickupLabel : widget.trip.destinationLabel;

  /// Road distance where it is known, straight-line only as a stopgap.
  ///
  /// The two are not close in this terrain, so the fallback is marked as such
  /// in the label rather than passed off as a road figure.
  double? get _distanceKm {
    final fix = _fix;
    if (_route != null && fix != null) return fix.remainingMeters / 1000;

    final from = _currentPoint;
    final target = _targetPoint;
    if (from == null || target == null) return null;
    return const Distance().as(LengthUnit.Kilometer, from, target);
  }

  bool get _distanceIsRoad => _route != null && _fix != null;

  /// Minutes to arrival, from the routing service where possible.
  ///
  /// The old estimate divided crow-flight distance by an assumed speed. On a
  /// mountain road that told a Driver they were four minutes away when they
  /// were twenty, and a Customer was told the same.
  int? get _etaMinutes {
    final route = _route;
    final fix = _fix;
    if (route != null && fix != null) {
      return math.max(1, (fix.remainingMeters / route.plannedSpeed / 60).ceil());
    }

    final distance = _distanceKm;
    if (distance == null) return null;
    final speed = math.max(20.0, _tracking?.driverLocation?.speedKph ?? 28.0);
    return math.max(1, (distance / speed * 60).ceil());
  }


  @override
  void dispose() {
    _messagePoll?.cancel();
    _timer?.cancel();
    _gps?.cancel();
    _car.dispose();
    _map.dispose();
    unawaited(UrduVoice.instance.stop());
    _locationService.stop();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ScreenAwake.release());
    // Hands tracking back to the shell-wide coordinator, which picks it up on
    // its next tick — leaving the ride tracked after the driver closes this
    // screen, which is the whole reason the coordinator exists.
    DriverTrackingSuspension.resume();
    super.dispose();
  }

  /// Reads the Customer's messages, and sounds for any not yet seen.
  Future<void> _pollMessages() async {
    try {
      final controller = AppControllerScope.of(context);
      final messages = await TripChatRepository(controller.apiClient)
          .messages(widget.trip.bookingId);
      if (!mounted) return;

      final fromCustomer = messages
          .where((message) => message.senderRole == 'Customer')
          .toList(growable: false);

      final unseen = fromCustomer
          .where((message) => !_announcedMessages.contains(message.id))
          .toList(growable: false);
      for (final message in unseen) {
        _announcedMessages.add(message.id);
      }

      // Not on the first poll: everything is unseen then, and chiming through
      // a conversation already read is noise.
      if (unseen.isNotEmpty && _messagesLoadedOnce) {
        // `SystemSound` was silent on Android — see AlertSound.
        unawaited(AlertSound.chime());
      }
      _messagesLoadedOnce = true;

      setState(() => _customerMessages = fromCustomer);
    } catch (_) {
      // A failed poll leaves what is already on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentPoint;
    final pickup = _pickupPoint;
    final destination = _destinationPoint;
    final target = _targetPoint;
    final anchor = current ?? _lastKnown ?? target;
    // The map opens once it has somewhere real to open (see initState's
    // timer). Opening it on a default city first meant a weak signal spent
    // itself loading tiles nobody would look at, then had to start again.
    if (anchor != null) _mapCanOpen = true;
    final center = anchor ?? _defaultCentre;
    // The road still ahead when it is known, a straight line until then. An
    // approximate line for the first second or two is better than an empty
    // map.
    final routePoints = _remaining.length > 1
        ? _remaining
        : [
            if (current != null) current,
            if (target != null) target,
          ];
    final screen = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Stack(
        children: [
          // Google's map, kept even when the signal drops — see
          // UdMap.keepGoogleOffline. Any touch that moves the map hands the
          // camera to the driver until they tap re-centre.
          Listener(
            onPointerMove: (event) {
              if (!_cameraHeld && event.delta.distance > 2) {
                setState(() => _cameraHeld = true);
              }
            },
            child: AnimatedBuilder(
              animation: _car,
              builder: (context, _) {
                if (!_mapCanOpen) return const _MapOpening();
                final car = _car.value ?? current;
                return UdMap(
                  controller: _map,
                  initialCenter: center,
                  // Close enough to recognise the street the car is on.
                  zoom: 17.5,
                  keepGoogleOffline: true,
                  showMyLocation: false,
                  // The car sits about two thirds of the way down, with the
                  // road it is about to drive filling the screen above it —
                  // how a navigation app frames a moving car.
                  padding: EdgeInsets.only(
                    top: screen.height * .40,
                    bottom: screen.height * .06,
                  ),
                  polylines: [
                    if (routePoints.length > 1)
                      UdPolyline(
                        id: 'route',
                        points: routePoints,
                        width: 8,
                        color: AppTint.routeActive,
                      ),
                  ],
                  markers: [
                    if (_headingToPickup && pickup != null)
                      UdMarker(
                        id: 'pickup',
                        position: pickup,
                        hue: UdMarkerHue.brand,
                        label: widget.trip.pickupLabel,
                      ),
                    if (!_headingToPickup && destination != null)
                      UdMarker(
                        id: 'destination',
                        position: destination,
                        hue: UdMarkerHue.danger,
                        label: widget.trip.destinationLabel,
                      ),
                    if (car != null)
                      UdMarker(
                        id: 'me',
                        position: car,
                        sprite: _spriteFor(_tracking?.vehicleCategory),
                        headingDegrees: _car.heading,
                      ),
                  ],
                );
              },
            ),
          ),
          // Back to following.
          //
          // Panning stops the camera, which is right — a map that snaps back
          // cannot be used to look ahead. But without a way to resume, one
          // accidental swipe ends live tracking for the rest of the trip, and
          // nothing on screen says why the car has stopped moving.
          if (_cameraHeld)
            Positioned(
              right: 14,
              bottom: 104,
              child: UdFloatButton(
                tooltip: 'Follow the vehicle again',
                onPressed: _resumeFollowing,
                child: const Icon(Icons.my_location_rounded,
                    size: 22, color: AppColors.navy),
              ),
            ),
          if (_failedRefreshes >= 3)
            const Positioned(
              left: 14,
              bottom: 112,
              child: _WeakSignalNote(),
            ),

          // The next turn, in Urdu, under the top bar.
          if (_banner != null || _routeCapped)
            Positioned(
              left: 14,
              right: 14,
              top: MediaQuery.paddingOf(context).top + 66,
              child: _TurnBannerCard(
                banner: _banner,
                muted: UrduVoice.instance.muted,
                note: _routeCapped && _fix != null && _fix!.offRouteMeters > _offRouteMeters
                    ? 'نیا راستہ دستیاب نہیں — منزل کی سمت چلیں'
                    : null,
                onToggleMute: () async {
                  await UrduVoice.instance.setMuted(!UrduVoice.instance.muted);
                  if (mounted) setState(() {});
                },
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UdIconButton(
                    icon: Icons.arrow_back_rounded,
                    variant: UdIconButtonVariant.float,
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  const UdMapChip(
                    dotColour: AppColors.brandInk,
                    label: 'LIVE · GPS',
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              // Collapsed by default. A Driver on the way to a pickup is
              // watching the road on the map, not reading the passenger's
              // history — that is for the moment they arrive, and it is one tap
              // away.
              child: CollapsibleMapSheet(
                collapsed: Row(
                  children: [
                    Icon(Icons.navigation_rounded,
                        size: 18, color: AppColors.secondary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${widget.trip.customerName}  ·  '
                        '${_distanceKm?.toStringAsFixed(1) ?? '—'} km'
                        '${_etaMinutes == null ? '' : '  ·  $_etaMinutes min'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                expanded: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.trip.customerName,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              if (_passenger != null) ...[
                                _PassengerRecord(standing: _passenger!),
                                const SizedBox(height: 5),
                              ],
                              // Who is being carried, in one line. A Driver
                              // pulling up needs to know how many people to
                              // expect and whether the vehicle was hired whole
                              // or by the seat before they open the door.
                              Text(
                                '${widget.trip.passengerCount} passenger'
                                '${widget.trip.passengerCount == 1 ? '' : 's'}'
                                '  ·  ${widget.trip.bookingType}'
                                '  ·  ${widget.trip.paymentStatus}',
                                style: const TextStyle(
                                  color: AppText.secondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _targetLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppText.secondary),
                              ),
                              if ((widget.trip.instructions ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 5),
                                // What the Customer asked for. Buried anywhere
                                // else it may as well not have been written.
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTint.warning,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    widget.trip.instructions!.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1.35,
                                      color: AppTint.warningText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_etaMinutes != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(
                              '≈ ${_etaMinutes} min',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Just the fare here. Message and call moved down into the
                    // action row — two ways to reach the same customer, at
                    // opposite ends of the panel, is one way too many.
                    Text(
                      'PKR ${widget.trip.fare.toStringAsFixed(0)} · ${widget.trip.bookingType}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_distanceKm?.toStringAsFixed(1) ?? '—'} km'
                      '${_distanceIsRoad ? ' by road' : ' direct'}'
                      '${_etaMinutes == null ? '' : ' · ~$_etaMinutes min'}'
                      ' to ${_headingToPickup ? 'pickup' : 'destination'}'
                      ' · ${widget.trip.passengerCount} passenger(s)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    // Urdu turn-by-turn runs on this screen (the banner above
                    // the map). Google Maps stays one tap away for drivers who
                    // keep Google's own offline areas downloaded.
                    UdButton.outline(
                      label: 'Directions to '
                          '${_headingToPickup ? 'pickup' : 'destination'}',
                      icon: Icons.near_me_rounded,
                      size: UdButtonSize.small,
                      onPressed: _openExternalNavigation,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: AppType.caption
                            .copyWith(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 13),
                    // The Customer's last message, where the Driver will see
                    // it. Tapping opens the thread.
                    if (_customerMessages.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: UdBanner(
                          tone: UdTone.info,
                          icon: Icons.chat_bubble_outline_rounded,
                          text: _customerMessages.last.body,
                          onTap: _openChat,
                        ),
                      ),
                    ],

                    // Cancelling before the trip starts. Once the Customer is
                    // aboard this disappears — abandoning someone mid-journey
                    // on a mountain road is not a button, it is an emergency,
                    // and that control is right beside it.
                    if (_currentStatus != 'TripStarted' &&
                        _currentStatus != 'TripCompleted' &&
                        _currentStatus != 'Cancelled') ...[
                      UdButtonRow(
                        children: [
                          UdButton.outline(
                            label: 'Emergency',
                            icon: Icons.sos_rounded,
                            size: UdButtonSize.small,
                            onPressed: _actionBusy
                                ? null
                                : () => _changeStatus('Emergency'),
                          ),
                          UdButton(
                            label: 'Cancel',
                            icon: Icons.close_rounded,
                            variant: UdButtonVariant.danger,
                            size: UdButtonSize.small,
                            onPressed:
                                _actionBusy ? null : _cancelWithReason,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_completionPending) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: UdBanner(
                          tone: UdTone.warn,
                          icon: Icons.cloud_upload_outlined,
                          text: 'Trip completed on your phone. It will be sent '
                              'to UDrive as soon as the internet is back.',
                          onTap: _sendPendingCompletion,
                        ),
                      ),
                    ],
                    // Message, call, then the one action that moves the trip
                    // forward. All three within thumb reach at the bottom of
                    // the map, because that is where a Driver's hand already is
                    // — the contact buttons used to sit at the top of the panel
                    // beside the name, which is the furthest point from it.
                    Row(
                      children: [
                        _DriverAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          tooltip: 'Message the customer',
                          onTap: _actionBusy ? null : _openChat,
                        ),
                        const SizedBox(width: 8),
                        _DriverAction(
                          icon: Icons.call_rounded,
                          tooltip: 'Call the customer',
                          onTap: _actionBusy ? null : _callCustomer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: UdButton.primary(
                            size: UdButtonSize.small,
                            busy: _actionBusy,
                            icon: _completionPending
                                ? Icons.cloud_upload_outlined
                                : _currentStatus == 'DriverArrived'
                                ? Icons.play_arrow_rounded
                                : _currentStatus == 'TripStarted'
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.location_on_rounded,
                            label: _completionPending
                                ? 'Send completion now'
                                : _currentStatus == 'DriverArrived'
                                ? 'Start trip with OTP'
                                : _currentStatus == 'TripStarted'
                                    ? 'Complete trip'
                                    : 'I have arrived',
                            onPressed: _starting || _actionBusy
                                ? null
                                : _completionPending
                                ? _sendPendingCompletion
                                : _currentStatus == 'DriverEnRoute'
                                    ? () => _changeStatus('DriverArrived')
                                    : _currentStatus == 'DriverArrived'
                                        ? _startTripWithOtp
                                        : _currentStatus == 'TripStarted'
                                            ? () => _changeStatus('TripCompleted')
                                            : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_starting)
            const ColoredBox(
              color: AppTint.scrim,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class CustomerFullScreenTrackingScreen extends StatefulWidget {
  const CustomerFullScreenTrackingScreen({
    required this.trip,
    required this.repository,
    this.tripOtp,
    super.key,
  });

  final MobileTrip trip;
  final TripOperationsRepository repository;
  final String? tripOtp;

  @override
  State<CustomerFullScreenTrackingScreen> createState() =>
      _CustomerFullScreenTrackingScreenState();
}

class _CustomerFullScreenTrackingScreenState
    extends State<CustomerFullScreenTrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The last answer for each trip, kept for this app session. Reopening the
  /// screen draws the map and the status at once instead of a blank screen
  /// while a weak signal fetches them again.
  static final Map<String, TripTracking> _lastSeen = <String, TripTracking>{};

  /// True while a poll is out. Polls used to start every five seconds whether
  /// or not the last had answered; on a weak signal four or five waited at
  /// once, took the bandwidth the map's tiles needed, and the status on screen
  /// stayed whatever the last success said — "Ride in progress".
  bool _loading = false;

  /// Polls in a row that failed. Three or more shows the weak-signal note, so
  /// an old status is never presented as current without a word.
  int _failedPolls = 0;

  /// The phone's last known position (no network), for opening the map.
  LatLng? _lastKnown;

  /// False until the map has somewhere real to open.
  bool _mapCanOpen = false;

  /// True while the chat is open over this screen.
  bool _chatOpen = false;

  final UdMapController _map = UdMapController();
  Timer? _timer;
  TripTracking? _tracking;
  String? _error;

  /// The car as drawn. The server hears from the driver every five seconds;
  /// between those fixes the car glides instead of standing and jumping.
  late final SmoothPosition _car = SmoothPosition(this);

  /// The road the driver's phone fetched for this leg, read from the server's
  /// stored copy. Reading it never costs a paid route call.
  LiveRoute? _route;
  RouteTracker? _tracker;
  RouteFix? _fix;
  List<LatLng> _remaining = const [];
  DateTime _routeCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _routeLoading = false;

  /// The driver fix last drawn, so the same one is not glided to twice.
  DateTime? _lastFixAt;

  /// When the camera last followed the car. Throttled to about once a second:
  /// Google animates each move, and asking more often than that interrupts
  /// its own animation.
  DateTime _lastCameraAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// How often the live screens refresh during a ride. The driver publishes
  /// at the same rate (TripLocationService.activeTripPingSeconds).
  static const int _livePollSeconds = TripLocationService.activeTripPingSeconds;

  /// Admin-uploaded vehicle photographs, keyed by setting name.
  Map<String, String> _vehicleImages = const {};

  /// The driver's rating and what recent passengers said about them.
  DriverReputation? _reputation;

  /// Bearer token for the driver photograph, which is an authenticated route.
  String? _token;

  /// How often tracking is polled, in seconds.
  ///
  /// Fixed at the rate the driver publishes during a ride, and also the time
  /// the drawn car takes to glide from one fix to the next.
  final int _trackingSeconds = _livePollSeconds;

  /// Messages already announced, so each chimes once.
  final Set<String> _announcedMessages = <String>{};

  /// True once the return to driver search has begun, so the poll that is
  /// already in flight cannot start it a second time.
  bool _returningToSearch = false;

  /// False until the first poll returns.
  bool _messagesLoadedOnce = false;

  /// The last trip status announced, so arrival is told once.
  String? _announcedStatus;

  /// Messages from the Driver, newest last.
  ///
  /// Shown floating over the map rather than only behind the chat button. A
  /// Driver who writes "I am at the blue gate" needs that read now, not after
  /// the Customer thinks to open a screen — and the Customer standing on a
  /// roadside is looking at the map, not at an icon.
  List<TripMessage> _driverMessages = const [];

  Timer? _messagePoll;

  /// True once the rating screen has been opened for this trip.
  ///
  /// The status poll keeps returning TripCompleted, so without this the rating
  /// screen would be pushed again every five seconds.
  bool _ratingShown = false;

  /// True once the camera has been put on the pickup while waiting for the
  /// driver's first fix, so it is done once rather than on every poll.
  bool _framedPickup = false;

  /// Whether the big countdown belongs on screen.
  ///
  /// Only while the car is on its way to the pickup. Once the customer is
  /// aboard the map is about the journey, and a large number over it would be
  /// answering a question nobody is asking any more.
  bool get _showEtaBanner {
    final status = _tracking?.tripStatus ?? widget.trip.tripStatus;
    return status == 'DriverAccepted' || status == 'DriverEnRoute';
  }

  /// True once the Customer has moved the map themselves.
  ///
  /// The camera used to recentre on the Driver every five seconds, which meant
  /// a Customer could not zoom out to see the whole approach — the map snapped
  /// back before they finished looking.
  bool _cameraHeld = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tracking = _lastSeen[widget.trip.bookingId];
    unawaited(_readLastKnown());
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_mapCanOpen) setState(() => _mapCanOpen = true);
    });
    _car.addListener(_followCar);
    _load();
    // The same rate the driver publishes at during a ride. Polling slower
    // throws away fixes; polling faster returns the same point twice.
    _timer = Timer.periodic(
      Duration(seconds: _trackingSeconds),
      (_) => _load(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pollMessages();
      _loadVehicleImages();
      _loadReputation();
    });
    _messagePoll =
        Timer.periodic(const Duration(seconds: 10), (_) => _pollMessages());
  }

  Future<void> _readLastKnown() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted || last == null) return;
      setState(() => _lastKnown = LatLng(last.latitude, last.longitude));
    } catch (_) {
      // None stored or no permission: the map opens on the trip instead.
    }
  }

  /// Polling stops while the app is in the background and catches up the
  /// moment it is back — a ride that ended meanwhile goes straight to the
  /// rating instead of showing "Ride in progress" for another tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _ratingShown || _returningToSearch) return;
    if (state == AppLifecycleState.resumed) {
      _startPolling(chat: _chatOpen);
      unawaited(_load());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _messagePoll?.cancel();
    }
  }

  /// The status poll, and the message poll unless the chat is open (the chat
  /// reads its own messages). While the chat is open the status is still
  /// checked every ten seconds, so a ride that ends then is not missed.
  void _startPolling({required bool chat}) {
    _timer?.cancel();
    _messagePoll?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: chat ? 10 : _trackingSeconds),
      (_) => _load(),
    );
    if (!chat) {
      _messagePoll =
          Timer.periodic(const Duration(seconds: 10), (_) => _pollMessages());
    }
  }

  /// Closes whatever is open above this screen (the chat), so the screen
  /// that replaces this one does not land under it.
  void _surface() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final tracking = await widget.repository
          .tracking(widget.trip.bookingId, path: false)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _lastSeen[widget.trip.bookingId] = tracking;
      setState(() {
        _tracking = tracking;
        _error = null;
        _failedPolls = 0;
      });

      // The trip is over: the map has nothing left to say, so hand the screen
      // to the rating. Leaving the map up makes rating look optional, which is
      // how a platform ends up with no ratings at all.
      if (tracking.tripStatus == 'TripCompleted' && !_ratingShown) {
        _ratingShown = true;
        _timer?.cancel();
        _messagePoll?.cancel();
        _lastSeen.remove(widget.trip.bookingId);
        _surface();
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TripRatingScreen(
              bookingId: widget.trip.bookingId,
              driverName: tracking.driverName ??
                  widget.trip.driverName ??
                  'your driver',
              vehicle: tracking.vehicle ?? widget.trip.vehicle ?? '',
              fare: widget.trip.fare,
            ),
          ),
        );
        return;
      }

      // The driver walked away. Put the customer back in the queue rather than
      // on a map of a ride that is not happening.
      //
      // The server has already returned their request to the pool and released
      // the offers, so another driver can take it — but the customer was left
      // watching a tracking screen labelled "Ride cancelled", with nothing on
      // it to press and no sign that they were still being looked for. They
      // had to work out for themselves that they should start again.
      //
      // Sent, not offered: the alternative is a dialog on a screen the person
      // may not be looking at, and every second it waits is a second no driver
      // is being asked.
      if (tracking.tripStatus == 'Cancelled' && !_returningToSearch) {
        _returningToSearch = true;
        _timer?.cancel();
        _messagePoll?.cancel();
        _lastSeen.remove(widget.trip.bookingId);
        _surface();
        await _returnToDriverSearch();
        return;
      }

      // "The driver is here" is the one status change a waiting customer must
      // not miss — they may be indoors, and the driver is already outside.
      if (tracking.tripStatus != _announcedStatus) {
        final previous = _announcedStatus;
        _announcedStatus = tracking.tripStatus;
        if (previous != null && tracking.tripStatus == 'DriverArrived') {
          // The heavier buzz is this screen's own: the driver arriving is
          // the one event worth a stronger nudge than a message.
          unawaited(AlertSound.chime(haptics: false));
          HapticFeedback.heavyImpact();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                duration: Duration(seconds: 8),
                content: Text('Your driver has arrived at the pickup point.'),
              ),
            );
          }
        }
      }

      final location = tracking.driverLocation;

      // The road for this leg, from the server's stored copy: when there is
      // none yet, when the leg changes (the customer is aboard), and every
      // thirty seconds in case the driver was rerouted.
      final leg = tracking.tripStatus == 'TripStarted' ? 'destination' : 'pickup';
      final sinceCheck = DateTime.now().difference(_routeCheckedAt);
      final missing = _route == null || _route!.leg != leg;
      // Fifteen seconds, not thirty: a driver who takes another road should
      // see it on the customer's map soon. The check sends the id of the road
      // already held, so an unchanged answer is a few bytes.
      if ((missing && sinceCheck > const Duration(seconds: 8)) ||
          sinceCheck > const Duration(seconds: 15)) {
        unawaited(_refreshRoute());
      }

      // No position published yet. This used to return here and leave the map
      // wherever it opened — which, with no tracking on the first frame, was a
      // hard-coded point in Islamabad. A customer in Muzaffarabad watching a
      // map of another city reads that as a broken app, not as "waiting".
      //
      // So the camera goes to the pickup: the one place that is certainly
      // right, and the place they are standing.
      if (location == null) {
        if (_cameraHeld || _framedPickup) return;
        if (tracking.pickupLatitude == null ||
            tracking.pickupLongitude == null) {
          return;
        }
        _framedPickup = true;
        final pickup =
            LatLng(tracking.pickupLatitude!, tracking.pickupLongitude!);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _cameraHeld) return;
          _map.moveTo(pickup, zoom: 16);
        });
        return;
      }

      // A fix already drawn is not drawn again.
      if (_lastFixAt == location.deviceTimestamp) return;
      _lastFixAt = location.deviceTimestamp;
      _placeCar(LatLng(location.latitude, location.longitude), location);
    } catch (error) {
      if (mounted) {
        setState(() {
          // No answer is shown by the weak-signal note, not as red text.
          _error = _isNoConnection(error)
              ? null
              : error.toString();
          _failedPolls++;
        });
      }
    } finally {
      _loading = false;
    }
  }

  /// Moves the drawn car to a new fix — onto the road when it is close to it,
  /// pointing the way the road goes — gliding over the poll interval so it
  /// arrives just as the next fix does.
  void _placeCar(LatLng driver, TrackingPoint location) {
    var display = driver;
    final speed = location.speedKph ?? 0;
    double? heading = speed > 3 ? location.heading : null;

    final tracker = _tracker;
    if (tracker != null) {
      final fix = tracker.locate(driver);
      _fix = fix;
      _remaining = tracker.remaining(fix);
      if (fix.offRouteMeters < 30) {
        display = fix.snapped;
        if (speed > 3) heading = fix.bearing;
      }
    }

    _car.moveTo(
      display,
      heading: heading,
      duration: Duration(seconds: _trackingSeconds),
    );
    if (mounted) setState(() {});
  }

  Future<void> _refreshRoute() async {
    if (_routeLoading) return;
    _routeLoading = true;
    _routeCheckedAt = DateTime.now();
    try {
      final controller = AppControllerScope.of(context);
      final held = _route;
      final result = await LiveRouteRepository(controller.apiClient).current(
        widget.trip.bookingId,
        known: held != null && held.leg == _legFor(_tracking) ? held.id : null,
      );
      if (!mounted || result.unchanged) return;
      final route = result.route;
      if (route == null) {
        // The leg changed and the driver's phone has not fetched the new road
        // yet: drop the old one rather than draw a road to the wrong place.
        if (_route != null && _route!.leg != result.leg) {
          setState(() {
            _route = null;
            _tracker = null;
            _fix = null;
            _remaining = const [];
          });
        }
        return;
      }
      if (route.id == _route?.id) return;

      final tracker = RouteTracker(route.points);
      final at = _tracking?.driverLocation;
      RouteFix? fix;
      if (at != null) fix = tracker.locate(LatLng(at.latitude, at.longitude));
      setState(() {
        _route = route;
        _tracker = tracker;
        _fix = fix;
        _remaining = fix == null ? route.points : tracker.remaining(fix);
      });
    } catch (_) {
      // Keep whatever road is already drawn.
    } finally {
      _routeLoading = false;
    }
  }

  /// Keeps the camera on the drawn car while it glides, about once a second.
  void _followCar() {
    if (_cameraHeld || !mounted) return;
    final car = _car.value;
    if (car == null) return;
    final now = DateTime.now();
    if (now.difference(_lastCameraAt) < const Duration(milliseconds: 900)) return;
    _lastCameraAt = now;
    _followDriver(car, _targetFor(_tracking));
  }

  String _legFor(TripTracking? tracking) =>
      tracking?.tripStatus == 'TripStarted' ? 'destination' : 'pickup';

  LatLng? _targetFor(TripTracking? tracking) {
    if (tracking == null) return null;
    final headingToPickup = tracking.tripStatus != 'TripStarted';
    final lat = headingToPickup ? tracking.pickupLatitude : tracking.destinationLatitude;
    final lng = headingToPickup ? tracking.pickupLongitude : tracking.destinationLongitude;
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagePoll?.cancel();
    _timer?.cancel();
    _car.removeListener(_followCar);
    _car.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Loads the admin's vehicle photographs, once.
  ///
  /// Cached copy first so the picture is there on the first frame; the refresh
  /// only replaces it if the admin has changed something.
  Future<void> _loadVehicleImages() async {
    final controller = AppControllerScope.of(context);
    final repository = VehicleImageRepository(controller.apiClient);

    final cached = await repository.cached();
    if (cached.isNotEmpty && mounted) {
      setState(() => _vehicleImages = cached);
    }

    final fresh = await repository.refresh();
    if (mounted && fresh.isNotEmpty) {
      setState(() => _vehicleImages = fresh);
    }
  }

  /// The photograph for the vehicle on its way.
  ///
  /// This vehicle's own picture first, the category picture second. A driver
  /// who uploaded photographs of their actual car should not have a stock
  /// image of a different one shown in their place.
  /// The picture of the car that is actually coming, in order of how true it is.
  ///
  /// 1. The Driver's own `VEHICLE_FRONT` photograph, served per booking.
  /// 2. `vehicles.image_url`, which only the demo seed sets.
  /// 3. The category picture an admin uploaded.
  ///
  /// The order used to start at 2, which meant a customer waiting for one
  /// Honda Civic was shown the admin's stock artwork of five different cars.
  /// A picture of the wrong vehicle is worse than no picture at all: the whole
  /// point of showing it is so somebody can recognise the car at the kerb.
  String? get _vehicleImageUrl {
    if (_tracking?.vehicleHasPhoto == true) {
      return '${ApiConfig.baseUrl}/api/v1/bookings/'
          '${widget.trip.bookingId}/vehicle-photo';
    }

    final own = _tracking?.vehicleImageUrl;
    if (own != null && own.trim().isNotEmpty) {
      return own.startsWith('http') ? own : '${ApiConfig.baseUrl}$own';
    }

    final category = _tracking?.vehicleCategory;
    if (category == null || category.trim().isEmpty) return null;
    final key = VehicleImageRepository.settingKeyFor(category);
    if (key == null) return null;
    final url = _vehicleImages[key];
    return (url == null || url.isEmpty) ? null : url;
  }

  /// The driver's initial, for when there is no photograph to show.
  Widget _driverInitial(TripTracking? tracking) => Text(
        (tracking?.driverName ?? widget.trip.driverName ?? 'D')
            .trim()
            .characters
            .first
            .toUpperCase(),
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: AppColors.secondary,
        ),
      );

  /// The driver's own photograph, served from their approved SELFIE.
  String? get _driverPhotoUrl => (_tracking?.driverHasPhoto ?? false)
      ? '${ApiConfig.baseUrl}/api/v1/trips/${widget.trip.bookingId}/driver-photo'
      : null;

  /// Reads the driver's rating and recent reviews, once.
  ///
  /// Their history does not change during a trip, so polling it would be noise
  /// on a screen already running two timers.
  Future<void> _loadReputation() async {
    final controller = AppControllerScope.of(context);
    final token = await controller.accessTokenForMedia();
    if (mounted && token != null) setState(() => _token = token);
    final reputation = await TripChatRepository(controller.apiClient)
        .driver(widget.trip.bookingId);
    if (!mounted || reputation == null) return;
    setState(() => _reputation = reputation);
  }

  /// Reads the Driver's messages so the newest can float over the map.
  ///
  /// Every ten seconds, not every three: this is a glance-at-the-map preview,
  /// and the real thread polls faster once it is open.
  Future<void> _pollMessages() async {
    try {
      final controller = AppControllerScope.of(context);
      final messages = await TripChatRepository(controller.apiClient)
          .messages(widget.trip.bookingId);
      if (!mounted) return;
      final fromDriver = messages
          .where((message) => message.senderRole == 'Driver')
          .toList(growable: false);

      // Sound and a buzz for anything not already seen.
      //
      // The bubbles float over the map, but a customer standing at a kerb is
      // usually not looking at the screen — a message that arrives silently is
      // read minutes later, by which time the driver has given up asking.
      final unseen = fromDriver
          .where((message) => !_announcedMessages.contains(message.id))
          .toList(growable: false);
      for (final message in unseen) {
        _announcedMessages.add(message.id);
      }
      // Not on the first load: everything is unseen then, and chiming for a
      // conversation the customer has already read is noise.
      if (unseen.isNotEmpty && _messagesLoadedOnce) {
        unawaited(AlertSound.chime());
      }
      _messagesLoadedOnce = true;

      setState(() => _driverMessages = fromDriver);
    } catch (_) {
      // A failed poll leaves whatever was already on screen. Blanking the
      // driver's last message over one bad request would be worse than showing
      // it a few seconds stale.
    }
  }

  bool _sharing = false;

  /// Keeps the camera on the car, at a zoom that suits how far away it is.
  ///
  /// It used to frame both ends of the approach. That reads well on paper —
  /// "where is it and how far off" — and badly in practice: with the driver
  /// five kilometres out, both ends fit only at a zoom where the car is a dot
  /// among streets nobody recognises, which is what "it is showing some other
  /// location" means.
  ///
  /// The car is the thing being watched, so the car stays centred. The zoom
  /// carries the distance instead: close in, you see the street it is turning
  /// into; far out, you see enough road to judge the wait.
  ///
  /// Stops the moment the customer pans. A map that snaps back while someone is
  /// looking at something is worse than one that never moves.
  ///
  /// Once the customer is aboard the question changes from "how far off is
  /// it" to "where are we", so the camera stays close on the car.
  void _followDriver(LatLng driver, LatLng? target) {
    final aboard = (_tracking?.tripStatus ?? widget.trip.tripStatus) == 'TripStarted';
    final metres = target == null
        ? 0.0
        : const Distance().as(LengthUnit.Meter, driver, target);

    // Closer than before. Aboard, the customer wants the street they are on;
    // waiting, the last kilometre is street level too, and only a car still
    // far off zooms out enough to show the road between.
    final zoom = aboard
        ? 18.0
        : switch (metres) {
            < 400 => 18.0,
            < 1200 => 17.0,
            < 3000 => 16.0,
            < 8000 => 14.5,
            _ => 13.0,
          };

    _map.follow(driver, zoom: zoom);
  }

  /// Sends a link that lets someone follow this ride without an account.
  ///
  /// The link dies when the trip ends, so it can go in a family group without
  /// leaving a permanent window into where someone is.
  Future<void> _shareTrip() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final token = await widget.repository
          .createTrackingLink(widget.trip.bookingId);
      if (!mounted || token.isEmpty) return;

      final url = '${ApiConfig.baseUrl}/track/$token';
      final driver = _tracking?.driverName ?? widget.trip.driverName ?? 'my driver';

      await SharePlus.instance.share(
        ShareParams(
          text: 'Follow my UDrive ride with $driver: $url\n'
              'The link stops working when the trip ends.',
          subject: 'Follow my ride',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Replaces this screen with the driver search, on the reopened request.
  ///
  /// The server put the request back to `ReceivingOffers` when the driver
  /// cancelled, so it is the customer's one open request again — which is what
  /// [AppController.openRideRequests] holds, and the same list the "resume
  /// search" card on the bookings screen reads.
  ///
  /// If it is not there — the pickup time had already passed, so the server
  /// left it closed — the customer goes back to where they were rather than to
  /// a search that would find nobody, and is told why.
  Future<void> _returnToDriverSearch() async {
    final controller = AppControllerScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await controller.refreshCustomerRideState();
    } catch (_) {
      // Whatever the list already holds is better than nothing.
    }
    if (!mounted) return;

    final open = controller.openRideRequests;
    if (open.isEmpty) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The driver cancelled. Book again when you are ready.'),
        ),
      );
      return;
    }
    final LiveRideRequest reopened = open.first;

    await navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => DriverOffersScreen(
          rideRequestId: reopened.id,
          pickup: reopened.pickupLabel,
          destination: reopened.destinationLabel,
          customerOffer: reopened.customerOffer.round(),
          vehicleName: reopened.vehicleCategory,
          pickupPoint:
              LatLng(reopened.pickupLatitude, reopened.pickupLongitude),
          destinationPoint: LatLng(
            reopened.destinationLatitude,
            reopened.destinationLongitude,
          ),
        ),
      ),
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('That driver cancelled. Looking for another one.'),
      ),
    );
  }

  /// Opens the conversation, and stands this screen's polling down while it is.
  ///
  /// Same reasoning as the driver's side, and it matters more here: this
  /// screen polls tracking every two seconds, which is thirty requests a
  /// minute that buy nothing at all while a chat window covers the map.
  ///
  /// The status is still checked every ten seconds while the chat is open:
  /// it used to stop altogether, so a ride completed during a conversation
  /// went unnoticed until the customer closed the chat. Now the chat closes
  /// and the rating opens.
  Future<void> _openChat() async {
    _chatOpen = true;
    _startPolling(chat: true);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripChatScreen(
          bookingId: widget.trip.bookingId,
          myRole: 'Customer',
          otherPartyName:
              _tracking?.driverName ?? widget.trip.driverName ?? 'Driver',
        ),
      ),
    );
    _chatOpen = false;
    if (!mounted || _ratingShown || _returningToSearch) return;

    await _load();
    if (!mounted || _ratingShown || _returningToSearch) return;
    _startPolling(chat: false);
  }

  Future<void> _callDriver() async {
    final phone = widget.trip.driverPhone?.trim();
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// How long a Customer may cancel without explaining themselves.
  ///
  /// Five minutes. Changing your mind straight after booking costs the Driver
  /// almost nothing; cancelling once they have driven halfway across town does,
  /// and at that point they are owed a reason.
  static const _freeCancelWindow = Duration(minutes: 5);

  Future<void> _cancelRide() async {
    final acceptedAt = _tracking?.driverLocation?.serverTimestamp ??
        widget.trip.lastActivityAt;
    final needsReason =
        DateTime.now().difference(acceptedAt) > _freeCancelWindow;

    final reason = TextEditingController();
    var chosen = '';

    final confirmed = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                'Cancel this ride?',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                needsReason
                    ? 'Your driver has been on the way for a while. Tell them '
                        'why so they are not left guessing.'
                    : 'The driver will be told straight away.',
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),

              if (needsReason) ...[
                const SizedBox(height: 16),
                UdListGroup(
                  children: [
                    for (final option in const [
                      'My plans changed',
                      'The driver is taking too long',
                      'I found another ride',
                      'The pickup point is wrong',
                      'Something else',
                    ])
                      UdListRow(
                        title: option,
                        leading: UdRadio(
                          selected: chosen == option,
                          onTap: () => setSheet(() => chosen = option),
                        ),
                        onTap: () => setSheet(() => chosen = option),
                      ),
                  ],
                ),
                if (chosen == 'Something else') ...[
                  const SizedBox(height: 14),
                  UdTextField(
                    controller: reason,
                    label: 'What happened?',
                    maxLength: 200,
                    minLines: 2,
                    maxLines: 3,
                    onChanged: (_) => setSheet(() {}),
                  ),
                ],
              ],

              const SizedBox(height: 18),
              UdButton(
                label: 'Cancel ride',
                variant: UdButtonVariant.dangerSolid,
                // A reason is required once the window has passed, and
                // "Something else" has to actually say something — an empty
                // free-text box selected and left blank tells the driver
                // exactly as little as no reason at all.
                onPressed: !needsReason ||
                        (chosen.isNotEmpty &&
                            (chosen != 'Something else' ||
                                reason.text.trim().length >= 3))
                    ? () => Navigator.pop(sheetContext, true)
                    : null,
              ),
              const SizedBox(height: 10),
              UdButton.ghost(
                label: 'Keep this ride',
                onPressed: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      ),
    );

    final detail = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;

    final text = !needsReason
        ? 'Customer cancelled within five minutes of booking.'
        : chosen == 'Something else'
            ? detail
            : chosen;

    // Claim the cancellation before the request goes out.
    //
    // The poll that watches for a cancelled trip cannot tell who cancelled it;
    // it only sees trip_status. So a Customer who cancelled their own ride was
    // overtaken by their own request: the POST set the status, the 10-second
    // tick read it back, found _returningToSearch still false and ran the
    // driver-cancelled path — "The driver cancelled. Book again when you are
    // ready." to the person who had just pressed Cancel ride, then a
    // pushReplacement onto the offers screen of whatever other open request
    // happened to be first in the list, because the server only reopens a
    // request when the *Driver* walks away. Then _cancelRide resumed and popped
    // again, so the second pop landed on a route it never opened.
    //
    // Setting the flag and stopping both timers here, before the await, means
    // the tick cannot fire during the request and cannot mistake this for the
    // driver's doing. The navigator is captured for the same reason: after the
    // await, this screen's own context may no longer be the one on top.
    _returningToSearch = true;
    _timer?.cancel();
    _messagePoll?.cancel();

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await widget.repository
          .customerStatus(widget.trip.bookingId, 'Cancelled', reason: text);
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Ride cancelled.')));
      navigator.pop();
    } catch (error) {
      // The ride is still live, so put the watch back — otherwise a Customer
      // whose cancellation failed sits on a screen that has stopped updating.
      if (!mounted) return;
      _returningToSearch = false;
      _timer = Timer.periodic(
        Duration(seconds: _trackingSeconds),
        (_) => _load(),
      );
      _messagePoll =
          Timer.periodic(const Duration(seconds: 10), (_) => _pollMessages());
      messenger.showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }


  String _customerStatusLabel(String? status) {
    switch (status) {
      case 'DriverAccepted':
      case 'DriverEnRoute': return 'Driver is coming to pickup';
      case 'DriverArrived': return 'Driver has arrived';
      case 'TripStarted': return 'Ride in progress';
      case 'TripCompleted': return 'Ride completed';
      case 'Cancelled': return 'Ride cancelled';
      default: return 'Driver confirmed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _tracking;
    final driver = t?.driverLocation == null
        ? null
        : LatLng(t!.driverLocation!.latitude, t.driverLocation!.longitude);
    final pickup = t?.pickupLatitude == null || t?.pickupLongitude == null
        ? null
        : LatLng(t!.pickupLatitude!, t.pickupLongitude!);
    final destination = t?.destinationLatitude == null || t?.destinationLongitude == null
        ? null
        : LatLng(t!.destinationLatitude!, t.destinationLongitude!);
    final headingToPickup = t?.tripStatus == 'DriverEnRoute' ||
        t?.tripStatus == 'DriverArrived' ||
        t?.tripStatus == 'DriverAccepted' ||
        t?.tripStatus == 'Emergency';
    final target = headingToPickup ? pickup : destination;
    final anchor = driver ?? target ?? _lastKnown;
    if (anchor != null) _mapCanOpen = true;
    final center = anchor ?? _defaultCentre;
    final distanceKm = driver != null && target != null
        ? Distance().as(LengthUnit.Kilometer, driver, target)
        : null;
    // Road figures where the routing service has answered. The straight-line
    // fallback stays only for the first second or two: through these mountains
    // it can be a third of the real distance, and a Customer told "4 minutes"
    // who then waits twenty stops believing the app.
    final route = _route;
    final fix = _fix;
    final roadKm = route != null && fix != null ? fix.remainingMeters / 1000 : null;
    final speed = math.max(20.0, t?.driverLocation?.speedKph ?? 28.0);
    final eta = route != null && fix != null
        ? math.max(1, (fix.remainingMeters / route.plannedSpeed / 60).ceil())
        : (distanceKm == null
            ? null
            : math.max(1, (distanceKm / speed * 60).ceil()));
    final routePoints = _remaining.length > 1
        ? _remaining
        : [driver, target].whereType<LatLng>().toList(growable: false);

    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerMove: (event) {
              if (!_cameraHeld && event.delta.distance > 2) {
                setState(() => _cameraHeld = true);
              }
            },
            child: AnimatedBuilder(
              animation: _car,
              builder: (context, _) {
                if (!_mapCanOpen) return const _MapOpening();
                final car = _car.value ?? driver;
                return UdMap(
                  controller: _map,
                  initialCenter: center,
                  // Close, for the same reason as the driver's map: the first
                  // frame should show a street, not a district.
                  zoom: 17,
                  keepGoogleOffline: true,
                  showMyLocation: false,
                  polylines: [
                    if (routePoints.length > 1)
                      UdPolyline(
                        id: 'route',
                        points: routePoints,
                        width: 7,
                        color: AppTint.routeActive,
                      ),
                  ],
                  markers: [
                    if (headingToPickup && pickup != null)
                      UdMarker(
                        id: 'pickup',
                        position: pickup,
                        hue: UdMarkerHue.brand,
                      ),
                    if (!headingToPickup && destination != null)
                      UdMarker(
                        id: 'destination',
                        position: destination,
                        hue: UdMarkerHue.danger,
                      ),
                    // The same top-down car Home draws, turned to the way the
                    // driver is facing. A round icon carries no direction, so a
                    // car approaching and a car driving away looked identical —
                    // which is most of what a waiting customer wants to know.
                    if (car != null)
                      UdMarker(
                        id: 'driver',
                        position: car,
                        sprite: _spriteFor(t?.vehicleCategory),
                        headingDegrees: _car.heading,
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  UdIconButton(
                    icon: Icons.arrow_back_rounded,
                    variant: UdIconButtonVariant.float,
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Spacer(),
                  // A white map chip with the status in it. The dot is the
                  // signal: amber while the driver's position is stale, lime
                  // ink while it is live.
                  Flexible(
                    child: UdMapChip(
                      dotColour: (t?.driverLocation?.stale ?? true)
                          ? AppTint.warningText
                          : AppColors.brandInk,
                      label: _customerStatusLabel(
                          t?.tripStatus ?? widget.trip.tripStatus),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // How long until the car is here, in the size that question deserves.
          //
          // The only figure on this screen was "12 min away" at 13.5px inside a
          // collapsed sheet, next to the driver's name. A customer standing on a
          // roadside holding the phone at arm's length could not read it, and it
          // is the one thing they opened the screen for.
          //
          // It goes as soon as the driver arrives: at that point the number is
          // zero and the instruction is "go outside", not "keep waiting".
          if (_showEtaBanner)
            Positioned(
              left: 14,
              right: 14,
              top: MediaQuery.paddingOf(context).top + 72,
              child: Center(
                child: _EtaBanner(
                  minutes: eta,
                  distanceKm: roadKm ?? distanceKm,
                  waiting: driver == null,
                  stale: t?.driverLocation?.stale ?? false,
                ),
              ),
            ),

          // Arrival gets the same space the countdown had, so the change is
          // impossible to miss on a glance.
          if (t?.tripStatus == 'DriverArrived')
            Positioned(
              left: 14,
              right: 14,
              top: MediaQuery.paddingOf(context).top + 72,
              child: const Center(child: _ArrivedBanner()),
            ),
          // Back to following the car, for the same reason as on the driver's
          // map: one accidental swipe should not end live tracking.
          if (_failedPolls >= 3)
            const Positioned(
              left: 14,
              bottom: 112,
              child: _WeakSignalNote(),
            ),
          if (_cameraHeld)
            Positioned(
              right: 14,
              bottom: 104,
              child: UdFloatButton(
                tooltip: 'Follow the driver again',
                onPressed: () {
                  setState(() => _cameraHeld = false);
                  final at = _car.value ?? driver;
                  if (at != null) _followDriver(at, target);
                },
                child: const Icon(Icons.my_location_rounded,
                    size: 22, color: AppColors.navy),
              ),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The driver's last words, floating over the map just above
                  // the panel.
                  //
                  // Translucent rather than a solid card: it sits on top of the
                  // route, and covering the thing the customer is watching in
                  // order to tell them about it would be a poor trade.
                  //
                  // Stacked in the same column as the panel rather than
                  // positioned over it, so they cannot end up behind it when
                  // the panel grows — an OTP box or a completion banner changes
                  // its height by a lot.
                  //
                  // Only the last two. A pile of old messages over a map stops
                  // being a notice and becomes a wall.
                  for (final message in _driverMessages
                      .skip(math.max(0, _driverMessages.length - 2)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _FloatingMessage(
                          message: message,
                          onTap: _openChat,
                        ),
                      ),
                    ),
              // Collapsed by default, so the map is the screen.
              //
              // A customer waiting is watching one thing: where the car is and
              // how far off. The driver's name, rating, reviews, fare and trip
              // code are all worth having — and all worth having *after* that
              // question is answered, which is one tap away.
              CollapsibleMapSheet(
                collapsed: Row(
                  children: [
                    Icon(Icons.directions_car_rounded,
                        size: 18, color: AppColors.secondary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        eta == null
                            ? (t?.driverName ??
                                widget.trip.driverName ??
                                'Your driver')
                            : '${t?.driverName ?? widget.trip.driverName ?? 'Driver'}'
                                '  ·  $eta min away',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                expanded: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // The driver, at a size you can actually recognise
                        // someone by.
                        //
                        // Initials, not a photograph: the schema has no
                        // driver photo column, and inventing a stock silhouette
                        // for every driver would tell the customer less than a
                        // letter does.
                        Container(
                          width: 62,
                          height: 62,
                          alignment: Alignment.center,
                          clipBehavior: Clip.antiAlias,
                          decoration: const BoxDecoration(
                            color: AppColors.navy,
                            shape: BoxShape.circle,
                          ),
                          child: _driverPhotoUrl != null
                              ? Image.network(
                                  _driverPhotoUrl!,
                                  cacheWidth: 192,
                                  fit: BoxFit.cover,
                                  width: 62,
                                  height: 62,
                                  headers: _token == null
                                      ? null
                                      : {'Authorization': 'Bearer $_token'},
                                  // Initials if the photograph will not load.
                                  // A broken-image glyph where a face should be
                                  // is worse than a letter.
                                  errorBuilder: (_, __, ___) =>
                                      _driverInitial(t),
                                )
                              : _driverInitial(t),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t?.driverName ?? widget.trip.driverName ?? 'Driver',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.h3.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.primary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              if (_reputation != null)
                                _DriverStars(reputation: _reputation!),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  t?.vehicle ?? widget.trip.vehicle ?? '',
                                  t?.registrationNumber ??
                                      widget.trip.registrationNumber ??
                                      '',
                                ].where((part) => part.trim().isNotEmpty).join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.caption.copyWith(
                                  color: AppText.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Small round call and message, top right, where the
                        // eye lands after reading the name.
                        // Sharing sits with call and message because it is the
                        // third thing a waiting customer does, and it belongs
                        // where the eye already is.
                        _RoundAction(
                          icon: Icons.ios_share_rounded,
                          tooltip: 'Share this trip',
                          onTap: _sharing ? () {} : _shareTrip,
                        ),
                        const SizedBox(width: 6),
                        _RoundAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          tooltip: 'Message the driver',
                          onTap: _openChat,
                        ),
                        if ((widget.trip.driverPhone ?? '').trim().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _RoundAction(
                            icon: Icons.call_rounded,
                            tooltip: 'Call the driver',
                            onTap: _callDriver,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 12),

                    // The vehicle itself, wide and unmistakable. A customer
                    // waiting on a roadside is matching what is in front of
                    // them against what the app says is coming, and a
                    // registration plate in 12pt type is a poor way to do that.
                    Container(
                      height: 132,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.all(AppRadii.field),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: _vehicleImageUrl != null
                                  ? Image.network(
                                      _vehicleImageUrl!,
                                      cacheWidth: 1080,
                                      fit: BoxFit.contain,
                                      // The VEHICLE_FRONT route is
                                      // authenticated and Image.network cannot
                                      // go through the API client, so it
                                      // carries the header itself. The category
                                      // picture is public; sending the header
                                      // anyway is harmless and saves branching
                                      // on which kind of URL this is.
                                      headers: _token == null
                                          ? null
                                          : {'Authorization': 'Bearer $_token'},
                                      errorBuilder: (_, __, ___) =>
                                          const _VehicleFallback(),
                                      loadingBuilder: (context, child, progress) =>
                                          progress == null
                                              ? child
                                              : const _VehicleFallback(),
                                    )
                                  : const _VehicleFallback(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (eta != null) ...[
                                  Text(
                                    '$eta',
                                    style: AppType.price.copyWith(
                                      height: 1,
                                      color: AppColors.brandInk,
                                    ),
                                  ),
                                  Text(
                                    'min away',
                                    style: AppType.caption.copyWith(
                                      color: AppText.secondary,
                                    ),
                                  ),
                                ] else
                                  Text(
                                    'On the way',
                                    style: AppType.listTitle.copyWith(
                                      fontSize: 15,
                                      color: AppText.secondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The driver is outside, and the customer may not be.
                    //
                    // A snackbar was not enough: it lasts eight seconds and
                    // vanishes, and the one person who most needs this is the
                    // one who put the phone down. This stays until the trip
                    // starts, and it replaces the ETA — "1 min away" is wrong
                    // once they have arrived.
                    if ((t?.tripStatus ?? widget.trip.tripStatus) ==
                        'DriverArrived') ...[
                      const SizedBox(height: 12),
                      UdBanner(
                        tone: UdTone.ok,
                        icon: Icons.where_to_vote_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                                  Text(
                                    'Your driver is here',
                                    style: AppType.listTitle.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTint.successText,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Look for '
                                    '${t?.registrationNumber ?? widget.trip.registrationNumber ?? 'the vehicle'}'
                                    '. Give the trip code once you are inside.',
                                    style: AppType.small.copyWith(
                                      height: 1.45,
                                      color: AppTint.successText,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 11),
                    UdCard(
                      tone: UdCardTone.tint,
                      radius: AppRadii.row,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'PKR ${widget.trip.fare.toStringAsFixed(0)}'
                              '  ·  ${widget.trip.bookingType}',
                              style: AppType.listTitle.copyWith(
                                fontSize: 15,
                                color: AppText.primary,
                              ),
                            ),
                          ),
                          // Where the car is, in one honest phrase. "0.0 km"
                          // was being shown when the driver's position was not
                          // known at all, which reads as "outside your door".
                          Text(
                            driver == null
                                ? 'Locating driver…'
                                : (t?.driverLocation?.stale ?? false)
                                    ? 'Signal lost'
                                    : roadKm == null
                                        ? 'Finding the road…'
                                        // Under a hundred metres, "0.0 km" is
                                        // a number pretending to be
                                        // information. The car is here.
                                        : roadKm < 0.1
                                            ? 'Arriving now'
                                            : '${roadKm.toStringAsFixed(1)} km by road',
                            style: AppType.caption.copyWith(
                              color: (t?.driverLocation?.stale ?? false)
                                  ? AppTint.warningText
                                  : AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if ((_reputation?.recentReviews ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 11),
                      // What the last few passengers actually said.
                      //
                      // A star average alone is a number; a sentence from
                      // someone who rode with this driver last week is the
                      // thing that tells a customer whether to get in.
                      SizedBox(
                        height: 78,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.zero,
                          itemCount: _reputation!.recentReviews.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => _ReviewCard(
                            review: _reputation!.recentReviews[index],
                          ),
                        ),
                      ),
                    ],

                    // From the server, not only from the booking response.
                    //
                    // The code used to live in whatever the confirmation
                    // returned, so closing the app and coming back through
                    // "Track ride" made the panel vanish and the trip could not
                    // be started at all.
                    if ((t?.tripOtp ?? widget.tripOtp ?? '').isNotEmpty &&
                        (t?.tripStatus ?? widget.trip.tripStatus) != 'TripStarted' &&
                        (t?.tripStatus ?? widget.trip.tripStatus) != 'TripCompleted') ...[
                      const SizedBox(height: 10),
                      UdBanner(
                        tone: UdTone.warn,
                        icon: Icons.password_rounded,
                        text: 'Trip code — read it to the driver only after '
                            'you are in the vehicle. It proves to us that the '
                            'right person got in, and the trip cannot start '
                            'without it.',
                        trailing: Text(
                          t?.tripOtp ?? widget.tripOtp ?? '',
                          style: AppType.h2.copyWith(
                            fontSize: 22,
                            letterSpacing: 4,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: AppType.caption.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],

                    if ((t?.tripStatus ?? widget.trip.tripStatus) ==
                        'TripCompleted') ...[
                      const SizedBox(height: 11),
                      const UdBanner(
                        tone: UdTone.ok,
                        icon: Icons.check_circle_rounded,
                        text: 'Trip completed',
                      ),
                    ] else if (!const {'TripStarted', 'Emergency', 'Cancelled'}
                        .contains(t?.tripStatus ?? widget.trip.tripStatus)) ...[
                      const SizedBox(height: 11),
                      UdButton(
                        label: 'Cancel ride',
                        icon: Icons.close_rounded,
                        variant: UdButtonVariant.danger,
                        size: UdButtonSize.small,
                        onPressed: _cancelRide,
                      ),
                    ],
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who the Driver is about to carry.
///
/// A Driver pulling up to a stranger is entitled to know something about them,
/// and until now the app told them a name and nothing else. This is the same
/// information the Customer already gets about the Driver, pointed the other
/// way: how many trips they have taken, how Drivers have rated them, and how
/// long they have been on the platform.
///
/// Three plain outcomes rather than a tier ladder. "Gold" and "Silver" would
/// imply the platform is ranking people; a Driver deciding whether to open the
/// door needs a fact, not a loyalty grade. "New" is not a warning — everyone is
/// new once, and the word says only that there is nothing to go on yet.
class _PassengerRecord extends StatelessWidget {
  const _PassengerRecord({required this.standing});

  final PassengerStanding standing;

  @override
  Widget build(BuildContext context) {
    final (background, ink) = switch (standing.standing) {
      'Trusted' => (AppTint.success, AppTint.successText),
      'Mixed' => (AppTint.warning, AppTint.warningText),
      'New' => (AppColors.surfaceAlt, AppColors.muted),
      _ => (AppTint.info, AppColors.info),
    };

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  standing.standing.toUpperCase(),
                  style: AppType.overline.copyWith(color: ink),
                ),
              ),
              const SizedBox(width: 8),
              // The trip count is the number that matters most here: somebody
              // on their fortieth ride behaves differently from somebody on
              // their first, whatever anyone has rated them.
              Text(
                '${standing.completedTrips} ride'
                '${standing.completedTrips == 1 ? '' : 's'} on UDrive',
                style: AppType.caption.copyWith(color: ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Shown only when a Driver has actually rated them. A default of
              // five would be a reassurance nobody gave.
              if (standing.rating != null) ...[
                Icon(Icons.star_rounded, size: 13, color: ink),
                const SizedBox(width: 3),
                Text(
                  '${standing.rating!.toStringAsFixed(1)} '
                  'from ${standing.ratingCount} driver'
                  '${standing.ratingCount == 1 ? '' : 's'}',
                  style: AppType.caption.copyWith(color: ink),
                ),
              ] else
                Text(
                  'No driver ratings yet',
                  style: AppType.caption.copyWith(color: ink),
                ),
              if (standing.cancelledTrips > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '${standing.cancelledTrips} cancelled',
                  style: AppType.caption.copyWith(color: ink),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when there is no photograph for the vehicle on its way.
/// The Trip OTP box inside the "Start the trip" dialog.
///
/// Its whole reason for existing is the error line underneath. The dialog's
/// button can only pop or not pop; it has no way to say *why* it did not pop.
/// Holding that one string here, behind a [GlobalKey], lets the button report
/// the problem without dragging dialog state up into the screen.
///
/// The formatter matters as much as the message: with digits-only input a
/// Driver cannot produce most of the invalid values in the first place, and
/// the error is left to the one case that remains — a code of the wrong length.
class _TripOtpField extends StatefulWidget {
  const _TripOtpField({required this.controller, super.key});

  final TextEditingController controller;

  @override
  State<_TripOtpField> createState() => _TripOtpFieldState();
}

class _TripOtpFieldState extends State<_TripOtpField> {
  String? _problem;

  /// Shown under the field. Called by the dialog's "Start ride" button.
  void showProblem(String message) {
    if (!mounted) return;
    setState(() => _problem = message);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        UdTextField(
          controller: widget.controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          hint: '0000',
          // Typing is the Driver correcting themselves; the complaint goes
          // away at the first keystroke rather than sitting there accusingly.
          onChanged: (_) {
            if (_problem != null) setState(() => _problem = null);
          },
        ),
        if (_problem != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _problem!,
                  style: AppType.caption.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _VehicleFallback extends StatelessWidget {
  const _VehicleFallback();

  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(
          Icons.directions_car_rounded,
          size: 44,
          color: AppColors.borderStrong,
        ),
      );
}

/// The driver's star rating, beside their name.
///
/// The count is always shown. An average over three ratings and one over three
/// hundred are different claims, and printing both as "4.7" would flatten that.
class _DriverStars extends StatelessWidget {
  const _DriverStars({required this.reputation});

  final DriverReputation reputation;

  @override
  Widget build(BuildContext context) {
    final rating = reputation.rating;

    if (rating == null) {
      // Not "5.0". A score nobody gave is worse than an honest blank, and a
      // new driver is not a bad one.
      return Text(
        reputation.completedTrips > 0
            ? 'New to ratings · ${reputation.completedTrips} trips'
            : 'New driver',
        style: AppType.caption.copyWith(color: AppText.caption),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - .5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: 15,
            color: AppTint.star,
          ),
        const SizedBox(width: 6),
        Text(
          '${rating.toStringAsFixed(1)}  ·  ${reputation.ratingCount} reviews',
          style: AppType.caption.copyWith(color: AppText.secondary),
        ),
      ],
    );
  }
}

/// One passenger's review of the driver, for the customer to scroll through.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final DriverReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= review.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 13,
                  color: AppTint.star,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  review.reviewerFirstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.overline.copyWith(
                    letterSpacing: 0,
                    color: AppText.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Text(
              review.text ?? 'Rated without a comment.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontStyle:
                    review.text == null ? FontStyle.italic : FontStyle.normal,
                color:
                    review.text == null ? AppText.disabled : AppText.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small round call or message button on the customer's panel.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => UdIconButton(
        icon: icon,
        variant: UdIconButtonVariant.soft,
        small: true,
        tooltip: tooltip,
        onPressed: onTap,
      );
}

/// `.map-chip` — a white pill that sits on top of a map.
/// A square icon button in the Driver's action row.
class _DriverAction extends StatelessWidget {
  const _DriverAction({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => UdIconButton(
        icon: icon,
        variant: UdIconButtonVariant.soft,
        tooltip: tooltip,
        onPressed: onTap,
      );
}

/// A driver's message, shown over the map.
///
/// Translucent so the route stays readable through it, and tappable so a
/// customer who wants to answer does not have to hunt for the chat button —
/// the message they are reading *is* the way in.
class _FloatingMessage extends StatelessWidget {
  const _FloatingMessage({required this.message, required this.onTap});

  final TripMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .8,
      ),
      child: Material(
        color: AppColors.background,
        elevation: 0,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 13, color: AppColors.brandInk),
                    const SizedBox(width: 6),
                    Text(
                      message.senderName.trim().isEmpty
                          ? 'Driver'
                          : message.senderName,
                      style: AppType.overline.copyWith(
                        letterSpacing: 0,
                        color: AppColors.brandInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body2.copyWith(
                    fontSize: 14,
                    height: 1.35,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Tap to reply',
                  style: TextStyle(fontSize: 10, color: AppText.disabled),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The top-down shape for a vehicle category, as Home draws it.
UdVehicleSprite _spriteFor(String? category) {
  final c = (category ?? '').toLowerCase();
  if (c.contains('bike') || c.contains('motor')) return UdVehicleSprite.bike;
  if (c.contains('hiace') ||
      c.contains('coaster') ||
      c.contains('van') ||
      c.contains('bus')) {
    return UdVehicleSprite.van;
  }
  return UdVehicleSprite.car;
}

/// The next turn: a big arrow, the distance, and the instruction in Urdu.
///
/// Navy with a lime arrow so it reads in full sun at arm's length, and laid
/// out right-to-left inside so the Urdu sits where an Urdu reader starts.
class _TurnBannerCard extends StatelessWidget {
  const _TurnBannerCard({
    required this.banner,
    required this.muted,
    required this.onToggleMute,
    this.note,
  });

  final TurnBanner? banner;
  final bool muted;
  final VoidCallback onToggleMute;

  /// A line under the instruction, e.g. when no new road can be fetched.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final b = banner;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              b?.icon ?? Icons.alt_route_rounded,
              size: 34,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (b != null && b.distanceLabel.isNotEmpty)
                    Text(
                      b.distanceLabel,
                      style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (b != null)
                    Text(
                      b.urdu,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  if (note != null)
                    Text(
                      note!,
                      maxLines: 2,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: muted ? 'Turn voice on' : 'Mute voice',
            onPressed: onToggleMute,
            icon: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: muted ? Colors.white54 : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// "8 min away", in the size a person can read at arm's length.
///
/// Three states in one card, because they are the same fact at different
/// certainties and swapping between three separate widgets made the card jump:
///
///   * waiting  — the driver has accepted but has published no position yet.
///     Says so plainly instead of leaving a blank map to be read as a broken
///     app. It is a normal few seconds, not a fault.
///   * live     — minutes, large, with the road distance under it.
///   * stale    — the same number, marked, because a position that stopped
///     updating two minutes ago produces an estimate that is quietly wrong,
///     and a wrong number stated confidently is worse than an honest doubt.
class _EtaBanner extends StatelessWidget {
  const _EtaBanner({
    required this.minutes,
    required this.distanceKm,
    required this.waiting,
    required this.stale,
  });

  final int? minutes;
  final double? distanceKm;
  final bool waiting;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final unknown = waiting || minutes == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.card),
        boxShadow: AppShadows.panel,
        border: stale && !unknown
            ? Border.all(color: AppTint.warningBorder, width: 1.4)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            unknown ? 'Your driver is on the way' : 'Driver arrives in',
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 2),
          if (unknown)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Getting their location…',
                  style: AppType.listTitle.copyWith(color: AppText.primary),
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$minutes',
                  style: AppType.display.copyWith(
                    fontSize: 42,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'min',
                    style: AppType.h3.copyWith(color: AppText.secondary),
                  ),
                ),
              ],
            ),
          if (!unknown && distanceKm != null) ...[
            const SizedBox(height: 2),
            Text(
              stale
                  ? '${distanceKm!.toStringAsFixed(1)} km away · last known position'
                  : '${distanceKm!.toStringAsFixed(1)} km away',
              style: AppType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: stale ? AppTint.warningText : AppText.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Replaces the countdown the moment the car is outside.
class _ArrivedBanner extends StatelessWidget {
  const _ArrivedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: AppRadii.all(AppRadii.card),
        boxShadow: AppShadows.panel,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 24, color: AppColors.navy),
          const SizedBox(width: 10),
          Text(
            'Your driver is here',
            style: AppType.h3.copyWith(color: AppText.onBrand),
          ),
        ],
      ),
    );
  }
}

/// Where a map opens when nothing better is known: Muzaffarabad, not a city
/// outside the area UDrive serves.
const LatLng _defaultCentre = LatLng(34.3700, 73.4711);

/// Shown for the second or so before the map has a real place to open.
class _MapOpening extends StatelessWidget {
  const _MapOpening();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTint.mapBackdrop,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

/// Said when the last few updates did not arrive, so a status or a car
/// position that is no longer current is never shown without a word.
class _WeakSignalNote extends StatelessWidget {
  const _WeakSignalNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTint.warning,
        borderRadius: AppRadii.all(AppRadii.field),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_cellular_connected_no_internet_4_bar_rounded,
              size: 14, color: AppTint.warningText),
          SizedBox(width: 6),
          Text(
            'Weak internet — updating…',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTint.warningText,
            ),
          ),
        ],
      ),
    );
  }
}

/// True when a request got no answer — no signal, too slow, or the server
/// failing — as opposed to a refusal the person needs to read.
bool _isNoConnection(Object error) =>
    error is TimeoutException ||
    (error is ApiException &&
        (error.statusCode == null || error.statusCode! >= 500));
