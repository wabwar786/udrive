import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/offline_maps/offline_aware_tile_layer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/booking/trip_operations_repository.dart';
import '../../core/routing/live_leg.dart';
import '../../core/services/trip_location_service.dart';
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

class _DriverLiveNavigationScreenState
    extends State<DriverLiveNavigationScreen> {
  late final TripLocationService _locationService;
  final MapController _mapController = MapController();
  Timer? _timer;
  TripTracking? _tracking;
  Position? _position;
  String? _error;
  bool _starting = true;
  bool _actionBusy = false;
  String _mapSource = 'ONLINE_OSM';
  late String _currentStatus;

  /// The real road ahead, not a straight line.
  final _leg = LiveLeg();

  /// True once the Driver has moved the map themselves.
  ///
  /// After that the camera stops following. A map that snaps back every ten
  /// seconds cannot be used to look at the junction ahead, which is the only
  /// reason a Driver would touch it while driving.
  bool _cameraHeld = false;

  @override
  void initState() {
    super.initState();
    _locationService = TripLocationService(widget.repository);
    _currentStatus = widget.trip.tripStatus;
    _begin();
  }

  Future<void> _begin() async {
    try {
      if (_currentStatus == 'DriverAccepted') {
        await widget.repository.driverStatus(
          widget.trip.bookingId,
          'DriverEnRoute',
          reason: 'Driver started travelling to the pickup location.',
        );
        _currentStatus = 'DriverEnRoute';
      }
      await _locationService.start(widget.trip.bookingId, _currentStatus);
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _refresh() async {
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {}
      final tracking = await widget.repository.tracking(widget.trip.bookingId);
      if (!mounted) return;
      setState(() {
        _position = position ?? _position;
        _tracking = tracking;
        _currentStatus = tracking.tripStatus;
        _error = null;
      });

      // The road to whichever end of the trip is next. Recomputed only when
      // the Driver has actually moved, so following a route does not mean a
      // paid request every ten seconds.
      final from = _currentPoint;
      final to = _targetPoint;
      if (from != null && to != null) {
        final changed = await _leg.update(from: from, to: to);
        if (changed && mounted) setState(() {});
      }

      _fitMap();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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

  Future<void> _callCustomer() async {
    final phone = widget.trip.customerPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _startTripWithOtp() async {
    if (_actionBusy) return;
    final controller = TextEditingController();
    final otp = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Trip OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask the Customer for the 4-digit code shown in their app.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
              decoration: const InputDecoration(counterText: '', hintText: '0000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (RegExp(r'^\d{4}$').hasMatch(value)) Navigator.pop(dialogContext, value);
            },
            child: const Text('Start Ride'),
          ),
        ],
      ),
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

  Future<void> _changeStatus(String status) async {
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

  void _fitMap() {
    // Once the Driver has panned or zoomed, the camera is theirs. Snapping it
    // back every ten seconds makes the map useless for the one thing they would
    // touch it for while driving — looking at the junction ahead.
    if (_cameraHeld) return;

    final points = <LatLng>[
      ..._leg.points,
    ];
    if (points.isEmpty) {
      final current = _currentPoint;
      if (current != null) points.add(current);
      final target = _targetPoint;
      if (target != null) points.add(target);
    }
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 14);
      } else {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(52),
          ),
        );
      }
    });
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
    final road = _leg.distanceKm;
    if (road != null) return road;

    final from = _currentPoint;
    final target = _targetPoint;
    if (from == null || target == null) return null;
    return const Distance().as(LengthUnit.Kilometer, from, target);
  }

  bool get _distanceIsRoad => _leg.distanceKm != null;

  /// Minutes to arrival, from the routing service where possible.
  ///
  /// The old estimate divided crow-flight distance by an assumed speed. On a
  /// mountain road that told a Driver they were four minutes away when they
  /// were twenty, and a Customer was told the same.
  int? get _etaMinutes {
    final routed = _leg.etaMinutes;
    if (routed != null) return routed;

    final distance = _distanceKm;
    if (distance == null) return null;
    final speed = math.max(20.0, _tracking?.driverLocation?.speedKph ?? 28.0);
    return math.max(1, (distance / speed * 60).ceil());
  }


  @override
  void dispose() {
    _timer?.cancel();
    _locationService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentPoint;
    final pickup = _pickupPoint;
    final destination = _destinationPoint;
    final target = _targetPoint;
    final center = current ?? target ?? const LatLng(33.6844, 73.0479);
    // The road when it is known, a straight line until then. An approximate
    // line for the first second or two is better than an empty map.
    final routePoints = _leg.points.isNotEmpty
        ? _leg.points
        : [
            if (current != null) current,
            if (target != null) target,
          ];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && !_cameraHeld) {
                  setState(() => _cameraHeld = true);
                }
              },
            ),
            children: [
              OfflineAwareTileLayer(
                origin: current ?? pickup ?? center,
                destination: destination ?? target ?? center,
                onSourceChanged: (value) { if (mounted && value != _mapSource) setState(() => _mapSource = value); },
              ),
              if (routePoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 5,
                      color: const Color(0xFF0A8A62),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (current != null)
                    Marker(
                      point: current,
                      width: 54,
                      height: 54,
                      child: const _MapMarker(
                        icon: Icons.directions_car_filled_rounded,
                        color: Color(0xFF0B3B2E),
                      ),
                    ),
                  if (_headingToPickup && pickup != null)
                    Marker(
                      point: pickup,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(
                        icon: Icons.person_pin_circle_rounded,
                        color: Color(0xFF165DFF),
                      ),
                    ),
                  if (!_headingToPickup && destination != null)
                    Marker(
                      point: destination,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(
                        icon: Icons.flag_rounded,
                        color: Color(0xFFE46A25),
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFF18A66A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text('LIVE · 10 sec · ${_mapSource == 'OFFLINE_MAP' ? 'Offline Map' : 'Online Map'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
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
                              const SizedBox(height: 3),
                              Text(
                                _targetLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        if (_etaMinutes != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF8F2),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(
                              '≈ ${_etaMinutes} min',
                              style: const TextStyle(
                                color: Color(0xFF087654),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text('PKR ${widget.trip.fare.toStringAsFixed(0)} · ${widget.trip.bookingType}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
                      IconButton.filledTonal(onPressed: _callCustomer, icon: const Icon(Icons.call_rounded), tooltip: 'Call Customer'),
                    ]),
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
                    // Turn-by-turn is handed to the phone's own navigation app.
                    //
                    // Building spoken directions into this screen would mean
                    // re-implementing lane guidance, rerouting and voice for
                    // roads that Google already covers — and doing it worse, on
                    // mountain roads where being wrong costs a driver an hour.
                    // The route and the arrival time are shown here; the
                    // turn-by-turn is one tap away in the app that does it
                    // properly.
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openExternalNavigation,
                        icon: const Icon(Icons.near_me_rounded, size: 18),
                        label: Text(
                          'Directions to '
                          '${_headingToPickup ? 'pickup' : 'destination'}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 7),
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                    ],
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _actionBusy ? null : () => _changeStatus('Emergency'),
                            icon: const Icon(Icons.sos_rounded),
                            label: const Text('Emergency'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _starting || _actionBusy
                                ? null
                                : _currentStatus == 'DriverEnRoute'
                                    ? () => _changeStatus('DriverArrived')
                                    : _currentStatus == 'DriverArrived'
                                        ? _startTripWithOtp
                                        : _currentStatus == 'TripStarted'
                                            ? () => _changeStatus('TripCompleted')
                                            : null,
                            icon: _actionBusy
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(
                                    _currentStatus == 'DriverArrived'
                                        ? Icons.play_arrow_rounded
                                        : _currentStatus == 'TripStarted'
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.location_on_rounded,
                                  ),
                            label: Text(
                              _currentStatus == 'DriverArrived'
                                  ? 'Customer boarded · Start trip'
                                  : _currentStatus == 'TripStarted'
                                      ? 'Complete trip'
                                      : 'I have arrived',
                            ),
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
              color: Color(0x55000000),
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
    extends State<CustomerFullScreenTrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _timer;
  TripTracking? _tracking;
  String? _error;
  String _mapSource = 'ONLINE_OSM';

  /// The road the Driver is actually taking to reach the Customer.
  final _leg = LiveLeg();

  /// True once the Customer has moved the map themselves.
  ///
  /// The camera used to recentre on the Driver every five seconds, which meant
  /// a Customer could not zoom out to see the whole approach — the map snapped
  /// back before they finished looking.
  bool _cameraHeld = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final tracking = await widget.repository.tracking(widget.trip.bookingId);
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _error = null;
      });

      final location = tracking.driverLocation;
      if (location == null) return;
      final driver = LatLng(location.latitude, location.longitude);

      // Route to whichever end matters now: the pickup while the Driver is on
      // their way, the destination once the Customer is aboard.
      final headingToPickup = tracking.tripStatus != 'TripStarted';
      final target = headingToPickup
          ? (tracking.pickupLatitude == null || tracking.pickupLongitude == null
              ? null
              : LatLng(tracking.pickupLatitude!, tracking.pickupLongitude!))
          : (tracking.destinationLatitude == null ||
                  tracking.destinationLongitude == null
              ? null
              : LatLng(
                  tracking.destinationLatitude!,
                  tracking.destinationLongitude!,
                ));

      if (target != null) {
        final changed = await _leg.update(from: driver, to: target);
        if (changed && mounted) setState(() {});
      }

      if (_cameraHeld) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _cameraHeld) return;
        // Frame the whole approach rather than centring on the car. "Where is
        // it and how far off" is the question; a close-up of the car answers
        // neither half.
        final points = _leg.points.isNotEmpty
            ? _leg.points
            : <LatLng>[driver, if (target != null) target];
        if (points.length < 2) {
          _mapController.move(points.first, 14);
        } else {
          _mapController.fitCamera(
            CameraFit.coordinates(
              coordinates: points,
              padding: const EdgeInsets.fromLTRB(48, 90, 48, 240),
            ),
          );
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _callDriver() async {
    final phone = widget.trip.driverPhone?.trim();
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text('The assigned Driver will be notified immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep Ride')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel Ride')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.customerStatus(widget.trip.bookingId, 'Cancelled', reason: 'Customer cancelled the ride before trip start.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride cancelled.')));
      Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
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
    final center = driver ?? target ?? const LatLng(33.6844, 73.0479);
    final distanceKm = driver != null && target != null
        ? Distance().as(LengthUnit.Kilometer, driver, target)
        : null;
    // Road figures where the routing service has answered. The straight-line
    // fallback stays only for the first second or two: through these mountains
    // it can be a third of the real distance, and a Customer told "4 minutes"
    // who then waits twenty stops believing the app.
    final roadKm = _leg.distanceKm;
    final speed = math.max(20.0, t?.driverLocation?.speedKph ?? 28.0);
    final eta = _leg.etaMinutes ??
        (distanceKm == null
            ? null
            : math.max(1, (distanceKm / speed * 60).ceil()));

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && !_cameraHeld) {
                  setState(() => _cameraHeld = true);
                }
              },
            ),
            children: [
              OfflineAwareTileLayer(
                origin: driver ?? pickup ?? center,
                destination: destination ?? target ?? center,
                onSourceChanged: (value) { if (mounted && value != _mapSource) setState(() => _mapSource = value); },
              ),
              if (_leg.points.isNotEmpty ||
                  [driver, target].whereType<LatLng>().length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _leg.points.isNotEmpty
                          ? _leg.points
                          : [driver, target].whereType<LatLng>().toList(),
                      strokeWidth: 5,
                      color: const Color(0xFF0A8A62),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (driver != null)
                    Marker(
                      point: driver,
                      width: 56,
                      height: 56,
                      child: const _MapMarker(icon: Icons.directions_car, color: Color(0xFF0B3B2E)),
                    ),
                  if (headingToPickup && pickup != null)
                    Marker(
                      point: pickup,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(icon: Icons.person_pin_circle, color: Color(0xFF165DFF)),
                    ),
                  if (!headingToPickup && destination != null)
                    Marker(
                      point: destination,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(icon: Icons.flag, color: Color(0xFFE46A25)),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        '${_customerStatusLabel(t?.tripStatus ?? widget.trip.tripStatus)} · LIVE · ${_mapSource == 'OFFLINE_MAP' ? 'Offline Map' : 'Online Map'}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 24)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.person_rounded)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t?.driverName ?? widget.trip.driverName ?? 'Driver', style: const TextStyle(fontWeight: FontWeight.w900)),
                              Text('${t?.vehicle ?? widget.trip.vehicle ?? ''} · ${t?.registrationNumber ?? widget.trip.registrationNumber ?? ''}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (eta != null)
                          Text('≈ $eta min', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF087654))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              'PKR ${widget.trip.fare.toStringAsFixed(0)} · ${widget.trip.bookingType}',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        if ((widget.trip.driverPhone ?? '').trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton.filledTonal(onPressed: _callDriver, icon: const Icon(Icons.call_rounded), tooltip: 'Call Driver'),
                        ],
                      ],
                    ),
                    if ((widget.tripOtp ?? '').isNotEmpty && (t?.tripStatus ?? widget.trip.tripStatus) != 'TripStarted' && (t?.tripStatus ?? widget.trip.tripStatus) != 'TripCompleted') ...[
                      const SizedBox(height: 9),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFFFD98A))),
                        child: Row(children: [
                          const Icon(Icons.password_rounded, size: 20, color: Color(0xFF9A6700)),
                          const SizedBox(width: 9),
                          const Expanded(child: Text('Trip OTP · Give this code only when you are inside the vehicle', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          Text(widget.tripOtp!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      driver == null
                          ? 'Waiting for the Driver’s next GPS update.'
                          // Road distance once it is known. The straight-line
                          // figure is labelled as such rather than passed off
                          // as a road number it is nowhere near.
                          : roadKm != null
                              ? '${roadKm.toStringAsFixed(1)} km by road to '
                                  '${headingToPickup ? 'pickup' : 'destination'}'
                                  ' · updated every 5 seconds'
                              : '${distanceKm?.toStringAsFixed(1)} km direct to '
                                  '${headingToPickup ? 'pickup' : 'destination'}'
                                  ' · finding the road…',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    if (t?.driverLocation != null)
                      Text(
                        t!.driverLocation!.stale ? 'Location is stale/offline' : 'Driver online',
                        style: TextStyle(
                          color: t.driverLocation!.stale ? Colors.orange : const Color(0xFF087654),
                          fontSize: 11,
                        ),
                      ),
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                    const SizedBox(height: 10),
                    if ((t?.tripStatus ?? widget.trip.tripStatus) == 'TripCompleted')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFEAF8F2), borderRadius: BorderRadius.circular(14)),
                        child: const Row(children: [Icon(Icons.check_circle_rounded, color: Color(0xFF087654)), SizedBox(width: 8), Expanded(child: Text('Trip completed successfully', style: TextStyle(fontWeight: FontWeight.w900)))]),
                      )
                    else if (!const {'TripStarted','Emergency','Cancelled'}.contains(t?.tripStatus ?? widget.trip.tripStatus))
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(onPressed: _cancelRide, icon: const Icon(Icons.close_rounded), label: const Text('Cancel Ride')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
          border: Border.all(color: color, width: 3),
        ),
        child: Icon(icon, color: color, size: 26),
      );
}
