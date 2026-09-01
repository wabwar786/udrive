import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/offline_maps/offline_aware_tile_layer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/booking/trip_operations_repository.dart';
import '../../core/booking/trip_chat_repository.dart';
import '../../core/maps/ud_vehicle_sprites.dart';
import '../../core/network/api_config.dart';
import '../../core/vehicles/vehicle_image_repository.dart';
import '../../core/routing/live_leg.dart';
import '../../core/services/trip_location_service.dart';
import '../../core/state/app_controller.dart';
import 'trip_chat_screen.dart';
import 'trip_rating_screen.dart';
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

  /// Who the Driver is collecting, from their history on the platform.
  PassengerStanding? _passenger;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPassenger());
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

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripChatScreen(
          bookingId: widget.trip.bookingId,
          myRole: 'Driver',
          otherPartyName: widget.trip.customerName,
        ),
      ),
    );
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

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cancel this ride?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The customer is told immediately and the request goes back '
                  'to other drivers.',
                  style: TextStyle(fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 14),
                for (final reason in _cancelReasons)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: reason,
                    groupValue: chosen,
                    onChanged: (value) => setSheet(() => chosen = value),
                    title: Text(
                      reason,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Anything else (optional)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  onPressed: chosen == null
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child: const Text('Cancel ride'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Keep this ride'),
                ),
              ],
            ),
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
                      color: const Color(0xFF0E4F4F),
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
                        color: Color(0xFF06201F),
                      ),
                    ),
                  if (_headingToPickup && pickup != null)
                    Marker(
                      point: pickup,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(
                        icon: Icons.person_pin_circle_rounded,
                        color: Color(0xFF4C9AFF),
                      ),
                    ),
                  if (!_headingToPickup && destination != null)
                    Marker(
                      point: destination,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(
                        icon: Icons.flag_rounded,
                        color: Color(0xFFE5484D),
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
                              color: Color(0xFF148A5A),
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
                              const SizedBox(height: 2),
                              if (_passenger != null) ...[
                                _PassengerChip(standing: _passenger!),
                                const SizedBox(height: 4),
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
                                  color: Colors.black54,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _targetLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              if ((widget.trip.instructions ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 5),
                                // What the Customer asked for. Buried anywhere
                                // else it may as well not have been written.
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF6E5),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    widget.trip.instructions!.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1.35,
                                      color: Color(0xFF7A5200),
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
                              color: const Color(0xFFE4F2F0),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(
                              '≈ ${_etaMinutes} min',
                              style: const TextStyle(
                                color: Color(0xFF0E4F4F),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text('PKR ${widget.trip.fare.toStringAsFixed(0)} · ${widget.trip.bookingType}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
                      IconButton.filledTonal(onPressed: _openChat, icon: const Icon(Icons.chat_bubble_outline_rounded), tooltip: 'Message Customer'),
                      const SizedBox(width: 6),
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
                    // Cancelling before the trip starts. Once the Customer is
                    // aboard this disappears — abandoning someone mid-journey
                    // on a mountain road is not a button, it is an emergency,
                    // and that control is right beside it.
                    if (_currentStatus != 'TripStarted' &&
                        _currentStatus != 'TripCompleted' &&
                        _currentStatus != 'Cancelled') ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _actionBusy ? null : _cancelWithReason,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: Color(0x33E5484D)),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text(
                            'Cancel this ride',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
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

  /// Admin-uploaded vehicle photographs, keyed by setting name.
  Map<String, String> _vehicleImages = const {};

  /// The driver's rating and what recent passengers said about them.
  DriverReputation? _reputation;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pollMessages();
      _loadVehicleImages();
      _loadReputation();
    });
    _messagePoll =
        Timer.periodic(const Duration(seconds: 10), (_) => _pollMessages());
  }

  Future<void> _load() async {
    try {
      final tracking = await widget.repository.tracking(widget.trip.bookingId);
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _error = null;
      });

      // The trip is over: the map has nothing left to say, so hand the screen
      // to the rating. Leaving the map up makes rating look optional, which is
      // how a platform ends up with no ratings at all.
      if (tracking.tripStatus == 'TripCompleted' && !_ratingShown) {
        _ratingShown = true;
        _timer?.cancel();
        _messagePoll?.cancel();
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
    _messagePoll?.cancel();
    _timer?.cancel();
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

  /// The photograph for the vehicle on its way, if the admin has set one.
  String? get _vehicleImageUrl {
    final category = _tracking?.vehicleCategory;
    if (category == null || category.trim().isEmpty) return null;
    final key = VehicleImageRepository.settingKeyFor(category);
    if (key == null) return null;
    final url = _vehicleImages[key];
    return (url == null || url.isEmpty) ? null : url;
  }

  /// Reads the driver's rating and recent reviews, once.
  ///
  /// Their history does not change during a trip, so polling it would be noise
  /// on a screen already running two timers.
  Future<void> _loadReputation() async {
    final controller = AppControllerScope.of(context);
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
      setState(() => _driverMessages = messages
          .where((message) => message.senderRole == 'Driver')
          .toList(growable: false));
    } catch (_) {
      // A failed poll leaves whatever was already on screen. Blanking the
      // driver's last message over one bad request would be worse than showing
      // it a few seconds stale.
    }
  }

  bool _sharing = false;

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

  void _openChat() {
    Navigator.push(
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
                      color: const Color(0xFF0E4F4F),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (driver != null)
                    Marker(
                      point: driver,
                      width: UdVehicleSprites.size.width,
                      height: UdVehicleSprites.size.height,
                      // The same top-down car Home draws, turned to the way the
                      // driver is actually facing. A circular icon carries no
                      // direction, so a car approaching and a car driving away
                      // looked identical — which is most of what a waiting
                      // customer wants to know.
                      child: Transform.rotate(
                        angle: (t?.driverLocation?.heading ?? 0) * math.pi / 180,
                        child: CustomPaint(
                          painter: const UdVehicleSpritePainter(
                            UdVehicleSprite.car,
                          ),
                          size: UdVehicleSprites.size,
                        ),
                      ),
                    ),
                  if (headingToPickup && pickup != null)
                    Marker(
                      point: pickup,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(icon: Icons.person_pin_circle, color: Color(0xFF4C9AFF)),
                    ),
                  if (!headingToPickup && destination != null)
                    Marker(
                      point: destination,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(icon: Icons.flag, color: Color(0xFFE5484D)),
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppText.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Spacer(),
                  // Dark pill, light text. It was white on white — the words
                  // were there and invisible — and it also carried "Online Map"
                  // and "LIVE", neither of which is the customer's problem.
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: (t?.driverLocation?.stale ?? true)
                                  ? AppColors.warning
                                  : AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _customerStatusLabel(
                                  t?.tripStatus ?? widget.trip.tripStatus),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: AppText.primary,
                              ),
                            ),
                          ),
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
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  // The app's own surface, not white. A white sheet on a dark
                  // teal map read as a different application pasted over this
                  // one, and the muted greys inside it were mixed for a light
                  // background so the driver's name was barely legible.
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 28),
                  ],
                ),
                child: Column(
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
                          decoration: BoxDecoration(
                            color: AppTint.brand,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.secondary, width: 2),
                          ),
                          child: Text(
                            (t?.driverName ?? widget.trip.driverName ?? 'D')
                                .trim()
                                .characters
                                .first
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppColors.secondary,
                            ),
                          ),
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
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
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
                                style: const TextStyle(
                                  color: AppText.secondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
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
                          onTap: _sharing ? () {} : _shareTrip,
                        ),
                        const SizedBox(width: 7),
                        _RoundAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          onTap: _openChat,
                        ),
                        if ((widget.trip.driverPhone ?? '').trim().isNotEmpty) ...[
                          const SizedBox(width: 7),
                          _RoundAction(
                            icon: Icons.call_rounded,
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
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: _vehicleImageUrl != null
                                  ? Image.network(
                                      _vehicleImageUrl!,
                                      fit: BoxFit.contain,
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
                                    style: const TextStyle(
                                      fontSize: 34,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                  const Text(
                                    'min away',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppText.secondary,
                                    ),
                                  ),
                                ] else
                                  const Text(
                                    'On the way',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppText.secondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'PKR ${widget.trip.fare.toStringAsFixed(0)}'
                              '  ·  ${widget.trip.bookingType}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
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
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: (t?.driverLocation?.stale ?? false)
                                  ? AppColors.warning
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

                    if ((widget.tripOtp ?? '').isNotEmpty &&
                        (t?.tripStatus ?? widget.trip.tripStatus) != 'TripStarted' &&
                        (t?.tripStatus ?? widget.trip.tripStatus) != 'TripCompleted') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: AppTint.warning,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Trip OTP · give this only once you are inside '
                                'the vehicle',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                  color: AppTint.warningText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.tripOtp!,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                color: AppText.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 11),
                      ),
                    ],

                    if ((t?.tripStatus ?? widget.trip.tripStatus) ==
                        'TripCompleted') ...[
                      const SizedBox(height: 11),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTint.success,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: AppTint.successText),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Trip completed',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppTint.successText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (!const {'TripStarted', 'Emergency', 'Cancelled'}
                        .contains(t?.tripStatus ?? widget.trip.tripStatus)) ...[
                      const SizedBox(height: 11),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _cancelRide,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: Color(0x33E5484D)),
                            minimumSize: const Size.fromHeight(46),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Cancel ride'),
                        ),
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

/// The passenger's history, in one line the Driver can read at a glance.
///
/// Three plain outcomes rather than a tier ladder. "Gold" and "Silver" would
/// imply the platform is ranking people; a Driver deciding whether to take a
/// fare needs a fact, not a loyalty grade.
///
/// "New" is not a warning. Everyone is new once, and the word says only that
/// there is nothing to go on yet.
class _PassengerChip extends StatelessWidget {
  const _PassengerChip({required this.standing});

  final PassengerStanding standing;

  @override
  Widget build(BuildContext context) {
    final (background, ink) = switch (standing.standing) {
      'Trusted' => (const Color(0xFFE7F7EF), const Color(0xFF0B6B4A)),
      'Mixed' => (const Color(0xFFFFF1E6), const Color(0xFF8A4B12)),
      'New' => (const Color(0xFFEDF1F5), const Color(0xFF44525E)),
      _ => (const Color(0xFFEAF2FF), const Color(0xFF1B4E9B)),
    };

    // The rating is only shown when someone actually gave one. A default of
    // five would be a reassurance nobody earned.
    final parts = <String>[
      standing.standing,
      if (standing.rating != null)
        '${standing.rating!.toStringAsFixed(1)}★ (${standing.ratingCount})',
      '${standing.completedTrips} trip'
          '${standing.completedTrips == 1 ? '' : 's'}',
      if (standing.cancelledTrips > 0) '${standing.cancelledTrips} cancelled',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        parts.join('  ·  '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
    );
  }
}

/// One of the two actions on the tracking panel.
///
/// Full-width halves rather than small circular icon buttons: on a phone held
/// one-handed at a roadside, "message the driver" should not be a target the
/// size of a fingernail.
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
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppText.disabled,
        ),
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
            size: 14,
            color: AppColors.secondary,
          ),
        const SizedBox(width: 6),
        Text(
          '${rating.toStringAsFixed(1)}  ·  ${reputation.ratingCount} reviews',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppText.secondary,
          ),
        ),
      ],
    );
  }
}

/// One passenger's review, in a card the customer can scroll through.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final DriverReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
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
                  size: 12,
                  color: AppColors.secondary,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  review.reviewerFirstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
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
                color: review.text == null
                    ? AppText.disabled
                    : AppText.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small round call or message button.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: AppColors.secondary),
        ),
      ),
    );
  }
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
        color: AppColors.surface.withValues(alpha: .82),
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
                    const Icon(Icons.chat_bubble_rounded,
                        size: 11, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      message.senderName.trim().isEmpty
                          ? 'Driver'
                          : message.senderName,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
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

/// Shown when there is no photograph for the vehicle on its way.
class _VehicleFallback extends StatelessWidget {
  const _VehicleFallback();

  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(
          Icons.directions_car_rounded,
          size: 44,
          color: AppText.disabled,
        ),
      );
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
