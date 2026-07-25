import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

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
  LivePackageVehicleLocation? _vehicle;
  Position? _customer;
  String? _error;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final vehicle = await AppControllerScope.of(context)
          .loadPackageVehicleLocation(widget.package.id);
      final customer = await _readCustomerPosition();
      if (!mounted) return;
      setState(() {
        _vehicle = vehicle;
        _customer = customer;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
                      : GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: mapCenter,
                            zoom: vehiclePoint != null ? 14 : 11,
                          ),
                          myLocationEnabled: customerPoint != null,
                          myLocationButtonEnabled: true,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          markers: {
                            if (vehiclePoint != null)
                              Marker(
                                markerId: const MarkerId('vehicle'),
                                position: vehiclePoint,
                                infoWindow: InfoWindow(
                                  title: widget.package.vehicle,
                                  snippet: widget.package.registrationNumber,
                                ),
                              ),
                            if (customerPoint != null)
                              Marker(
                                markerId: const MarkerId('customer'),
                                position: customerPoint,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueAzure,
                                ),
                                infoWindow: const InfoWindow(title: 'Your location'),
                              ),
                            if (destinationPoint != null)
                              Marker(
                                markerId: const MarkerId('destination'),
                                position: destinationPoint,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueGreen,
                                ),
                                infoWindow: InfoWindow(
                                  title: widget.package.destination,
                                ),
                              ),
                          },
                          polylines: {
                            if (vehiclePoint != null && customerPoint != null)
                              Polyline(
                                polylineId: const PolylineId('vehicle-to-customer'),
                                points: [vehiclePoint, customerPoint],
                                width: 5,
                                color: AppColors.primary,
                              ),
                          },
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
                      ? 'The destination is shown. Vehicle GPS will appear when the Driver starts sharing location.'
                      : distanceKm == null
                          ? 'Vehicle location is live. Allow location access to calculate arrival time to you.'
                          : '${distanceKm.toStringAsFixed(1)} km from your current location. ETA is approximate and may change with traffic.',
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
                      color: AppColors.danger,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

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
              loading ? 'Loading live map…' : 'Map coordinates are unavailable.',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
