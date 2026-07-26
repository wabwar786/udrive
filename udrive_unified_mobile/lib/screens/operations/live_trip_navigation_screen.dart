import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking/trip_operations_repository.dart';
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
  late String _currentStatus;

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
      _fitMap();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
    final points = <LatLng>[];
    final current = _currentPoint;
    if (current != null) points.add(current);
    final target = _targetPoint;
    if (target != null) points.add(target);
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

  double? get _distanceKm {
    final from = _currentPoint;
    final target = _targetPoint;
    if (from == null || target == null) return null;
    return Distance().as(LengthUnit.Kilometer, from, target);
  }

  int? get _etaMinutes {
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
    final routePoints = [
      if (current != null) current,
      if (target != null) target,
    ];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.udrive.mobile',
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
                    const SizedBox(height: 11),
                    Text(
                      '${_distanceKm?.toStringAsFixed(1) ?? '—'} km to ${_headingToPickup ? 'pickup' : 'destination'} · ${widget.trip.passengerCount} passenger(s)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
                                        ? () => _changeStatus('TripStarted')
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
    super.key,
  });

  final MobileTrip trip;
  final TripOperationsRepository repository;

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

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final tracking = await widget.repository.tracking(widget.trip.bookingId);
      if (!mounted) return;
      setState(() { _tracking = tracking; _error = null; });
      final location = tracking.driverLocation;
      if (location != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(
              LatLng(location.latitude, location.longitude),
              14,
            );
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    final speed = math.max(20.0, t?.driverLocation?.speedKph ?? 28.0);
    final eta = distanceKm == null ? null : math.max(1, (distanceKm / speed * 60).ceil());

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.udrive.mobile',
              ),
              if ([driver, target].whereType<LatLng>().length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [driver, target].whereType<LatLng>().toList(),
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
                        headingToPickup ? 'Driver is on the way · LIVE' : 'Trip in progress · LIVE',
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
                    Text(
                      driver == null
                          ? 'Waiting for the Driver’s next GPS update.'
                          : '${distanceKm?.toStringAsFixed(1)} km to ${headingToPickup ? 'pickup' : 'destination'} · updated every 10 seconds',
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
