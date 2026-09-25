import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../core/services/service_availability_repository.dart';
import '../../core/services/trip_location_service.dart';
import '../../core/widgets/collapsible_map_sheet.dart';
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
  late String _currentStatus;

  /// The real road ahead, not a straight line.
  final _leg = LiveLeg();

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

  @override
  void initState() {
    super.initState();
    _locationService = TripLocationService(widget.repository);
    _currentStatus = widget.trip.tripStatus;
    _begin();
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
        await widget.repository.driverStatus(
          widget.trip.bookingId,
          'DriverEnRoute',
          reason: 'Driver started travelling to the pickup location.',
        );
        _currentStatus = 'DriverEnRoute';
      }
      await _locationService.start(widget.trip.bookingId, _currentStatus);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Clears the blocking overlay as soon as there is a map to look at.
  ///
  /// `_starting` draws a full-screen spinner, and it used to stay up until all
  /// three start-up calls had finished. The map underneath was ready long
  /// before that — the Driver was being shown a spinner over a working screen.
  void _ready() {
    if (mounted && _starting) setState(() => _starting = false);
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
        title: const Text('Start the trip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Says what the code is for, not just what to type.
            //
            // "Enter Trip OTP" tells a Driver the mechanics and none of the
            // purpose, and a step whose purpose is unclear is one people work
            // around — asking for the code through a car window, or starting
            // the trip with the wrong passenger aboard.
            const Text(
              'Ask the passenger for the 4-digit code in their app.\n\n'
              'It confirms the right person is in your vehicle, and it starts '
              'the fare. Nobody can be charged for a trip they did not take, '
              'and you cannot be blamed for one you did not carry.',
              style: TextStyle(height: 1.5),
            ),
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

    final current = _currentPoint;
    final target = _targetPoint;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // The Driver's own position, centred, zoomed by how far is left.
      //
      // Fitting the whole leg put the car at the edge of the screen with the
      // road ahead of it off-frame — the opposite of what a map is for while
      // driving. Their position stays in the middle and the zoom carries the
      // distance, so the junction they are about to reach is always visible.
      if (current != null) {
        final metres = target == null
            ? 0.0
            : const Distance().as(LengthUnit.Meter, current, target);

        _mapController.move(
          current,
          switch (metres) {
            < 400 => 17.0,
            < 1200 => 16.0,
            < 3000 => 15.0,
            < 8000 => 13.5,
            _ => 12.0,
          },
        );
        return;
      }

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
    _messagePoll?.cancel();
    _timer?.cancel();
    _locationService.stop();
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
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.mediumImpact();
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
              // Close enough to recognise the street the car is on.
              //
              // 13 showed a district. On the first frame — before any tracking
              // has arrived — the screen opened on a wide view of somewhere the
              // customer could not place, and only tightened once a position
              // came in. Opening close and widening if the car turns out to be
              // far is the better way round.
              initialZoom: 16,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && !_cameraHeld) {
                  setState(() => _cameraHeld = true);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.wabwar.udrive',
              ),
              if (routePoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 5,
                      color: AppColors.inkTile,
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
                        color: AppColors.inkDeep,
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
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
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
              child: Material(
                color: AppColors.background,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  onTap: () {
                    setState(() => _cameraHeld = false);
                    _fitMap();
                  },
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.my_location_rounded,
                        size: 20, color: AppColors.secondary),
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const Spacer(),
                  Material(
                    color: AppColors.surface,
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
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Text('LIVE · 10 sec', style: TextStyle(fontWeight: FontWeight.w800)),
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
                    // The Customer's last message, where the Driver will see
                    // it. Tapping opens the thread.
                    if (_customerMessages.isNotEmpty) ...[
                      InkWell(
                        onTap: _openChat,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 11),
                          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                          decoration: BoxDecoration(
                            color: AppTint.info,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.chat_bubble_rounded,
                                  size: 15, color: AppColors.info),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _customerMessages.last.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: AppColors.info,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _actionBusy
                                  ? null
                                  : () => _changeStatus('Emergency'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              icon: const Icon(Icons.sos_rounded, size: 17),
                              label: const Text('Emergency',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _actionBusy ? null : _cancelWithReason,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTint.dangerText,
                                side: const BorderSide(color: AppTint.dangerBorder),
                                minimumSize: const Size.fromHeight(44),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 17),
                              label: const Text('Cancel',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                          onTap: _actionBusy ? null : _openChat,
                        ),
                        const SizedBox(width: 8),
                        _DriverAction(
                          icon: Icons.call_rounded,
                          onTap: _actionBusy ? null : _callCustomer,
                        ),
                        const SizedBox(width: 8),
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

  /// The road the Driver is actually taking to reach the Customer.
  final _leg = LiveLeg();

  /// Admin-uploaded vehicle photographs, keyed by setting name.
  Map<String, String> _vehicleImages = const {};

  /// The driver's rating and what recent passengers said about them.
  DriverReputation? _reputation;

  /// Bearer token for the driver photograph, which is an authenticated route.
  String? _token;

  /// Messages already announced, so each chimes once.
  final Set<String> _announcedMessages = <String>{};

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
    // The server's interval, matching how often the driver publishes.
    //
    // Polling slower than the driver reports throws away fixes that were paid
    // for in battery; polling faster returns the same point twice. They should
    // be the same number, and now they read it from the same place.
    _timer = Timer.periodic(
      Duration(seconds: ServiceAvailabilityRepository.defaultPingSeconds),
      (_) => _load(),
    );
    _applyServerPingInterval();
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

      // "The driver is here" is the one status change a waiting customer must
      // not miss — they may be indoors, and the driver is already outside.
      if (tracking.tripStatus != _announcedStatus) {
        final previous = _announcedStatus;
        _announcedStatus = tracking.tripStatus;
        if (previous != null && tracking.tripStatus == 'DriverArrived') {
          SystemSound.play(SystemSoundType.alert);
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
        _followDriver(driver, target);
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

  /// The photograph for the vehicle on its way.
  ///
  /// This vehicle's own picture first, the category picture second. A driver
  /// who uploaded photographs of their actual car should not have a stock
  /// image of a different one shown in their place.
  String? get _vehicleImageUrl {
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
  /// Re-times the poll to whatever the admin has set.
  ///
  /// Started at the default and corrected a moment later, rather than waiting
  /// on a network call before the map updates at all. A screen that shows
  /// nothing for a second because it is asking how often to show things is a
  /// poor trade.
  Future<void> _applyServerPingInterval() async {
    final controller = AppControllerScope.of(context);
    final seconds = await ServiceAvailabilityRepository(controller.apiClient)
        .trackingPingSeconds();
    if (!mounted ||
        seconds == ServiceAvailabilityRepository.defaultPingSeconds) {
      return;
    }

    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _load());
  }

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
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.mediumImpact();
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
  void _followDriver(LatLng driver, LatLng? target) {
    final metres = target == null
        ? 0.0
        : const Distance().as(LengthUnit.Meter, driver, target);

    final zoom = switch (metres) {
      < 400 => 17.0,
      < 1200 => 16.0,
      < 3000 => 15.0,
      < 8000 => 13.5,
      _ => 12.0,
    };

    _mapController.move(driver, zoom);
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

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cancel this ride?',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  needsReason
                      ? 'Your driver has been on the way for a while. Tell them '
                          'why so they are not left guessing.'
                      : 'The driver will be told straight away.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppText.secondary,
                  ),
                ),

                if (needsReason) ...[
                  const SizedBox(height: 16),
                  for (final option in const [
                    'My plans changed',
                    'The driver is taking too long',
                    'I found another ride',
                    'The pickup point is wrong',
                    'Something else',
                  ])
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: option,
                      groupValue: chosen,
                      onChanged: (value) => setSheet(() => chosen = value ?? ''),
                      title: Text(
                        option,
                        style: const TextStyle(
                            fontSize: 13.5, color: AppText.primary),
                      ),
                    ),
                  if (chosen == 'Something else')
                    TextField(
                      controller: reason,
                      maxLength: 200,
                      style: const TextStyle(color: AppText.primary),
                      decoration: const InputDecoration(
                        labelText: 'What happened?',
                        counterText: '',
                      ),
                    ),
                ],

                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
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

    final detail = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;

    final text = !needsReason
        ? 'Customer cancelled within five minutes of booking.'
        : chosen == 'Something else'
            ? detail
            : chosen;

    try {
      await widget.repository
          .customerStatus(widget.trip.bookingId, 'Cancelled', reason: text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ride cancelled.')));
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
        );
      }
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
              // Close, for the same reason as the driver's map: the first
              // frame should show a street, not a district.
              initialZoom: 16,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && !_cameraHeld) {
                  setState(() => _cameraHeld = true);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.wabwar.udrive',
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
                      color: AppColors.inkTile,
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
                      child: const _MapMarker(icon: Icons.flag, color: AppColors.danger),
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
          // Back to following the car, for the same reason as on the driver's
          // map: one accidental swipe should not end live tracking.
          if (_cameraHeld)
            Positioned(
              right: 14,
              bottom: 104,
              child: Material(
                color: AppColors.background,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  onTap: () {
                    setState(() => _cameraHeld = false);
                    final at = t?.driverLocation;
                    if (at != null) {
                      _followDriver(
                        LatLng(at.latitude, at.longitude),
                        target,
                      );
                    }
                  },
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.my_location_rounded,
                        size: 20, color: AppColors.secondary),
                  ),
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
                          decoration: BoxDecoration(
                            color: AppTint.brand,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.secondary, width: 2),
                          ),
                          child: _driverPhotoUrl != null
                              ? Image.network(
                                  _driverPhotoUrl!,
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
                                    style: TextStyle(
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTint.success,
                          borderRadius: AppRadii.all(AppRadii.panel),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.where_to_vote_rounded,
                                size: 26, color: AppTint.successText),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Your driver is here',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: AppTint.successText,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Look for '
                                    '${t?.registrationNumber ?? widget.trip.registrationNumber ?? 'the vehicle'}'
                                    '. Give the trip code once you are inside.',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: AppTint.successText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

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
                                'Trip code — read it to the driver only after '
                                'you are in the vehicle. It proves to us that '
                                'the right person got in, and the trip cannot '
                                'start without it.',
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
                              t?.tripOtp ?? widget.tripOtp ?? '',
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
                            foregroundColor: AppTint.dangerText,
                            side: const BorderSide(color: AppTint.dangerBorder),
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
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
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The trip count is the number that matters most here: somebody
              // on their fortieth ride behaves differently from somebody on
              // their first, whatever anyone has rated them.
              Text(
                '${standing.completedTrips} ride'
                '${standing.completedTrips == 1 ? '' : 's'} on UDrive',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
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
                  style: TextStyle(fontSize: 11.5, color: ink),
                ),
              ] else
                Text(
                  'No driver ratings yet',
                  style: TextStyle(fontSize: 11.5, color: ink),
                ),
              if (standing.cancelledTrips > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '${standing.cancelledTrips} cancelled',
                  style: TextStyle(fontSize: 11.5, color: ink),
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

/// One passenger's review of the driver, for the customer to scroll through.
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

/// A square icon button in the Driver's action row.
class _DriverAction extends StatelessWidget {
  const _DriverAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 52,
          height: 50,
          child: Icon(icon, size: 20, color: AppColors.secondary),
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
                    Icon(Icons.chat_bubble_rounded,
                        size: 11, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      message.senderName.trim().isEmpty
                          ? 'Driver'
                          : message.senderName,
                      style: TextStyle(
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
