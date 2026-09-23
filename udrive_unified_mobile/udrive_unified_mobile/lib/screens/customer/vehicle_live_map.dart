import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/booking_models.dart';

class VehicleLiveMap extends StatefulWidget {
  const VehicleLiveMap({required this.package, super.key});

  final LiveTourPackage package;

  @override
  State<VehicleLiveMap> createState() => _VehicleLiveMapState();
}

class _VehicleLiveMapState extends State<VehicleLiveMap> {
  final MapController _mapController = MapController();
  LivePackageVehicleLocation? _vehicle;
  Position? _customer;
  String? _error;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final customer = await _readCustomerPosition();
    try {
      final vehicle = await AppControllerScope.of(context)
          .loadPackageVehicleLocation(widget.package.id);
      if (!mounted) return;
      setState(() {
        _vehicle = vehicle;
        _customer = customer;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _error = 'Live vehicle location is not available yet. The map will update automatically every 10 seconds.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Position?> _readCustomerPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  LatLng? get _vehiclePoint {
    final value = _vehicle;
    if (value?.hasLiveCoordinates != true) return null;
    return LatLng(value!.latitude!, value.longitude!);
  }

  LatLng? get _destinationPoint {
    final value = _vehicle;
    if (value?.hasDestinationCoordinates != true) return null;
    return LatLng(value!.destinationLatitude!, value.destinationLongitude!);
  }

  LatLng? get _customerPoint => _customer == null
      ? null
      : LatLng(_customer!.latitude, _customer!.longitude);

  List<LatLng> get _visiblePoints => [
        if (_vehiclePoint != null) _vehiclePoint!,
        if (_customerPoint != null) _customerPoint!,
        if (_destinationPoint != null) _destinationPoint!,
      ];

  void _fitMap() {
    final points = _visiblePoints;
    if (!mounted || points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 13);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(42),
        maxZoom: 15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehiclePoint = _vehiclePoint;
    final destinationPoint = _destinationPoint;
    final customerPoint = _customerPoint;
    final mapCenter = vehiclePoint ?? destinationPoint ?? customerPoint;
    final distanceKm = vehiclePoint != null && customerPoint != null
        ? _distanceKm(vehiclePoint, customerPoint)
        : null;
    final etaMinutes = distanceKm == null
        ? null
        : math.max(1, ((distanceKm / 30) * 60).round());

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 250,
            child: Stack(
              children: [
                Positioned.fill(
                  child: mapCenter == null
                      ? _MapUnavailable(loading: _loading)
                      : FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: mapCenter,
                            initialZoom: vehiclePoint != null ? 14 : 11,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all &
                                  ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.udrive.mobile',
                              maxZoom: 19,
                            ),
                            if (vehiclePoint != null && customerPoint != null)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [vehiclePoint, customerPoint],
                                    strokeWidth: 5,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                if (vehiclePoint != null)
                                  _marker(
                                    vehiclePoint,
                                    Icons.directions_car_filled_rounded,
                                    AppColors.primary,
                                  ),
                                if (customerPoint != null)
                                  _marker(
                                    customerPoint,
                                    Icons.person_pin_circle_rounded,
                                    Colors.blue,
                                  ),
                                if (destinationPoint != null)
                                  _marker(
                                    destinationPoint,
                                    Icons.flag_circle_rounded,
                                    AppColors.success,
                                  ),
                              ],
                            ),
                            const RichAttributionWidget(
                              attributions: [
                                TextSourceAttribution(
                                  'OpenStreetMap contributors',
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _LivePill(
                    live: _vehicle?.isLive == true,
                    stale: _vehicle?.isStale == true,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'Refresh vehicle location',
                      onPressed: _loading ? null : _load,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.package.vehicle} · ${widget.package.registrationNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (etaMinutes != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '≈ $etaMinutes min away',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  vehiclePoint == null
                      ? 'Vehicle GPS will appear when the assigned Driver starts sharing location.'
                      : distanceKm == null
                          ? 'Vehicle location is live. Allow your location to calculate approximate arrival time.'
                          : '${distanceKm.toStringAsFixed(1)} km from you. ETA is approximate and does not include live traffic.',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                if (_vehicle?.lastUpdatedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'GPS updated ${DateFormat('dd MMM · hh:mm:ss a').format(_vehicle!.lastUpdatedAt!.toLocal())}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'Location refreshes automatically every 10 seconds.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color) => Marker(
        point: point,
        width: 46,
        height: 46,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 25),
        ),
      );

  double _distanceKm(LatLng a, LatLng b) {
    const radius = 6371.0;
    final dLat = _radians(b.latitude - a.latitude);
    final dLng = _radians(b.longitude - a.longitude);
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.live, required this.stale});

  final bool live;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final label = live ? 'LIVE GPS' : stale ? 'STALE GPS' : 'GPS WAITING';
    final color = live
        ? AppColors.success
        : stale
            ? AppColors.warning
            : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              const Icon(Icons.map_outlined, size: 44, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(
              loading
                  ? 'Loading live map…'
                  : 'Waiting for the Driver to share live GPS.',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
