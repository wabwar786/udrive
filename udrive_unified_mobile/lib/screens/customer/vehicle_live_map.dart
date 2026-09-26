import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import '../../core/permissions/location_access.dart';

/// C-29 — the assigned tour vehicle, live, relative to the customer.
///
/// An embedded card, not a screen: it sits at the top of C-28 Package Detail.
/// The design draws it full-page only so the map, the status pill and the info
/// panel can be specified at full size.
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
        _error = 'Live vehicle location is not available yet. The map will '
            'update automatically every 10 seconds.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Position?> _readCustomerPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      // Disclosure before the prompt — see LocationAccess.
      final permission =
          await LocationAccess.ensure(context, LocationPurpose.customer);
      if (!LocationAccess.granted(permission)) {
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

    return UdCard(
      tone: UdCardTone.raised,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.card),
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
                                      // Navy 6px — the v2 active route. This
                                      // was AppColors.primary at 5px.
                                      strokeWidth: 6,
                                      color: AppTint.routeActive,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  if (destinationPoint != null)
                                    _flagMarker(destinationPoint),
                                  if (customerPoint != null)
                                    _customerMarker(customerPoint),
                                  if (vehiclePoint != null)
                                    _vehicleMarker(vehiclePoint),
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
                    child: UdMapChip(
                      label: _gpsLabel,
                      dotColour: _gpsColour,
                      uppercase: true,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: UdIconButton(
                      icon: Icons.refresh_rounded,
                      variant: UdIconButtonVariant.float,
                      tooltip: 'Refresh vehicle location',
                      onPressed: _loading ? null : _load,
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
                          '${widget.package.vehicle} · '
                          '${widget.package.registrationNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle.copyWith(
                            fontSize: 16,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                      if (etaMinutes != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            // Lime carries navy and nothing else.
                            color: AppColors.brand,
                            borderRadius: AppRadii.all(AppRadii.chip),
                          ),
                          child: Text(
                            '≈ $etaMinutes min away',
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppText.onBrand,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    vehiclePoint == null
                        ? 'Vehicle GPS will appear when the assigned Driver '
                            'starts sharing location.'
                        : distanceKm == null
                            ? 'Vehicle location is live. Allow your location '
                                'to calculate approximate arrival time.'
                            : '${distanceKm.toStringAsFixed(1)} km from you. '
                                'ETA is approximate and does not include live '
                                'traffic.',
                    style: AppType.body2.copyWith(
                      fontSize: 14,
                      color: AppText.secondary,
                    ),
                  ),
                  if (_vehicle?.lastUpdatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'GPS updated '
                      '${DateFormat('dd MMM · hh:mm:ss a').format(_vehicle!.lastUpdatedAt!.toLocal())}',
                      style: AppType.caption.copyWith(color: AppText.caption),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    UdBanner(tone: UdTone.gray, text: _error!),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Location refreshes automatically every 10 seconds.',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _gpsLabel => _vehicle?.isLive == true
      ? 'Live GPS'
      : _vehicle?.isStale == true
          ? 'Stale GPS'
          : 'GPS waiting';

  /// The dot is the signal, not decoration: lime-ink while the position is
  /// current, amber once it has gone stale, grey before anything has arrived.
  Color get _gpsColour => _vehicle?.isLive == true
      ? AppColors.brandInk
      : _vehicle?.isStale == true
          ? AppTint.warningText
          : AppText.caption;

  /// The vehicle: a navy disc with a lime glyph, matching the driver marker
  /// used on the ride map.
  Marker _vehicleMarker(LatLng point) => Marker(
        point: point,
        width: 46,
        height: 46,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.background, width: 3),
            boxShadow: AppShadows.floating,
          ),
          child: const Icon(
            Icons.directions_car_filled_rounded,
            color: AppColors.brand,
            size: 22,
          ),
        ),
      );

  /// The customer: a navy dot inside a thick white ring — the design's own
  /// start marker. It used to be `Colors.blue`, which is in no part of this
  /// palette.
  Marker _customerMarker(LatLng point) => Marker(
        point: point,
        width: 26,
        height: 26,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppTint.pinPickupRing,
            shape: BoxShape.circle,
            boxShadow: AppShadows.floating,
          ),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: AppTint.pinPickupFill,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );

  /// The destination: a lime square with a navy border. The border is what
  /// makes it legible — bare lime on a map is 1.3:1.
  Marker _flagMarker(LatLng point) => Marker(
        point: point,
        width: 26,
        height: 26,
        child: Container(
          decoration: BoxDecoration(
            color: AppTint.pinDropFill,
            borderRadius: AppRadii.all(7),
            border: Border.all(color: AppTint.pinDropBorder, width: 3),
            boxShadow: AppShadows.floating,
          ),
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

/// Before the first fix arrives, and when the Driver is not sharing at all.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => ColoredBox(
        // The map's own land colour, so the placeholder reads as a map that
        // has not drawn yet rather than an error panel.
        color: AppTint.mapBackdrop,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.navy,
                  ),
                )
              else
                const UdIconTile(
                  icon: Icons.map_outlined,
                  tone: UdIconTone.neutral,
                  size: UdIconTileSize.lg,
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  loading
                      ? 'Loading live map…'
                      : 'Waiting for the Driver to share live GPS.',
                  textAlign: TextAlign.center,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
