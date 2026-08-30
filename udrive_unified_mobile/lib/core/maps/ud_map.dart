import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../offline_maps/offline_aware_tile_layer.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Which renderer [UdMap] is currently using.
enum UdMapSource {
  /// Google Maps SDK — the default whenever the device is online.
  google,

  /// flutter_map backed by a downloaded PMTiles pack, or OSM tiles.
  offline,
}

/// A map marker expressed independently of the underlying renderer.
class UdMarker {
  const UdMarker({
    required this.id,
    required this.position,
    this.label,
    this.hue = UdMarkerHue.brand,
    this.onTap,
  });

  final String id;
  final LatLng position;
  final String? label;
  final UdMarkerHue hue;
  final VoidCallback? onTap;
}

enum UdMarkerHue { brand, navy, danger, info }

/// A polyline expressed independently of the underlying renderer.
class UdPolyline {
  const UdPolyline({
    required this.id,
    required this.points,
    this.color = AppColors.primary,
    this.width = 4,
  });

  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;
}

/// A translucent circle, used for the "vehicles within N km" ring on Home.
class UdCircle {
  const UdCircle({
    required this.id,
    required this.centre,
    required this.radiusMetres,
    this.fill = AppColors.secondary,
    this.fillOpacity = .09,
    this.stroke = AppColors.secondary,
    this.strokeOpacity = .42,
    this.strokeWidth = 1.5,
  });

  final String id;
  final LatLng centre;
  final double radiusMetres;
  final Color fill;
  final double fillOpacity;
  final Color stroke;
  final double strokeOpacity;
  final double strokeWidth;
}

/// Imperative handle so callers can recentre the map without caring which
/// renderer is active.
class UdMapController {
  _UdMapState? _state;

  void _attach(_UdMapState state) => _state = state;
  void _detach(_UdMapState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Whether a map surface is currently mounted and ready for commands.
  bool get isReady => _state != null;

  /// The renderer currently on screen, or null before first build.
  UdMapSource? get source => _state?._source;

  Future<void> moveTo(LatLng target, {double? zoom}) async {
    await _state?._moveTo(target, zoom: zoom);
  }

  /// Zooms out until every point fits, with padding around the edges.
  ///
  /// Used after a destination is chosen so the customer sees the whole trip
  /// rather than staying zoomed in on the pickup.
  Future<void> fitBounds(List<LatLng> points, {double padding = 60}) async {
    await _state?._fitBounds(points, padding: padding);
  }

  void dispose() => _state = null;
}

/// The single map surface used across UDrive.
///
/// Behaviour, as agreed with the product owner:
///
/// * Online  → Google Maps (Maps SDK), the primary experience.
/// * Offline → flutter_map with the existing PMTiles offline pack for the
///   route, falling back to OSM tiles if no pack covers it.
///
/// Switching is automatic and driven by [Connectivity], so a customer driving
/// into a valley with no signal keeps a usable map instead of a blank screen.
/// The offline download manager under `lib/core/offline_maps/` is unchanged —
/// this widget simply consumes it.
class UdMap extends StatefulWidget {
  const UdMap({
    required this.initialCenter,
    this.controller,
    this.zoom = AppConfig.defaultMapZoom,
    this.markers = const [],
    this.polylines = const [],
    this.circles = const [],
    this.routeOrigin,
    this.routeDestination,
    this.showMyLocation = true,
    this.myLocation,
    this.minZoom,
    this.onCameraMoveStarted,
    this.onCameraIdle,
    this.interactive = true,
    this.onTap,
    this.onSourceChanged,
    super.key,
  });

  final LatLng initialCenter;
  final UdMapController? controller;
  final double zoom;
  final List<UdMarker> markers;
  final List<UdPolyline> polylines;
  final List<UdCircle> circles;

  /// Used to pick the right offline pack when connectivity drops. Defaults to
  /// [initialCenter] for both ends when not supplied.
  final LatLng? routeOrigin;
  final LatLng? routeDestination;

  final bool showMyLocation;

  /// Drawn as a blue dot with an accuracy halo when the offline renderer is
  /// active. Google draws its own dot from [showMyLocation], so this is only
  /// used by flutter_map — pass it anyway and both paths look the same.
  final LatLng? myLocation;

  /// Floor for the camera. Home passes a street-level value so the map can
  /// never end up showing half a continent — at that scale road names vanish
  /// and the screen stops being useful.
  final double? minZoom;

  /// Fired when the customer starts dragging, and again when the camera
  /// settles. Together they drive the centre pickup pin.
  final VoidCallback? onCameraMoveStarted;
  final ValueChanged<LatLng>? onCameraIdle;
  final bool interactive;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<UdMapSource>? onSourceChanged;

  @override
  State<UdMap> createState() => _UdMapState();
}

class _UdMapState extends State<UdMap> {

  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  final Completer<gmap.GoogleMapController> _googleController =
      Completer<gmap.GoogleMapController>();
  final fmap.MapController _offlineController = fmap.MapController();

  bool _online = true;

  /// Where the camera currently points. Tracked so the idle callback can report
  /// it — Google gives the position during the move, not at the end.
  LatLng? _cameraTarget;

  late LatLng _center;
  late double _zoom;

  UdMapSource get _source => _online ? UdMapSource.google : UdMapSource.offline;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _zoom = widget.zoom;
    widget.controller?._attach(this);

    Connectivity().checkConnectivity().then(_applyConnectivity);
    _connectivity =
        Connectivity().onConnectivityChanged.listen(_applyConnectivity);
  }

  @override
  void didUpdateWidget(covariant UdMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    widget.controller?._detach(this);
    super.dispose();
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final online = !results.every((value) => value == ConnectivityResult.none);
    if (online == _online) return;
    setState(() => _online = online);
    widget.onSourceChanged?.call(_source);
  }

  Future<void> _moveTo(LatLng target, {double? zoom}) async {
    final nextZoom = zoom ?? _zoom;
    _center = target;
    _zoom = nextZoom;

    if (_online) {
      if (!_googleController.isCompleted) return;
      final controller = await _googleController.future;
      await controller.animateCamera(
        gmap.CameraUpdate.newCameraPosition(
          gmap.CameraPosition(
            target: gmap.LatLng(target.latitude, target.longitude),
            zoom: nextZoom,
          ),
        ),
      );
    } else {
      _offlineController.move(target, nextZoom);
    }
  }

  Future<void> _fitBounds(List<LatLng> points, {double padding = 60}) async {
    if (points.isEmpty) return;
    if (points.length == 1) {
      await _moveTo(points.first, zoom: AppConfig.focusedMapZoom);
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Two points a few hundred metres apart produce a bounds so small that
    // fitting it with padding can swing the camera to an absurd zoom. Below
    // this span, centring is both simpler and more predictable.
    const minimumSpanDegrees = 0.004; // roughly 400 m
    if ((maxLat - minLat) < minimumSpanDegrees &&
        (maxLng - minLng) < minimumSpanDegrees) {
      await _moveTo(_center, zoom: AppConfig.focusedMapZoom);
      return;
    }

    if (_online) {
      if (!_googleController.isCompleted) return;
      final controller = await _googleController.future;
      await controller.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(
          gmap.LatLngBounds(
            southwest: gmap.LatLng(minLat, minLng),
            northeast: gmap.LatLng(maxLat, maxLng),
          ),
          padding,
        ),
      );
    } else {
      _offlineController.fitCamera(
        fmap.CameraFit.bounds(
          bounds: fmap.LatLngBounds(
            LatLng(maxLat, minLng),
            LatLng(minLat, maxLng),
          ),
          padding: EdgeInsets.all(padding),
        ),
      );
    }
  }

  // --------------------------------------------------------------- rendering

  double _googleHue(UdMarkerHue hue) => switch (hue) {
        UdMarkerHue.brand => gmap.BitmapDescriptor.hueGreen,
        UdMarkerHue.navy => gmap.BitmapDescriptor.hueAzure,
        UdMarkerHue.danger => gmap.BitmapDescriptor.hueRed,
        UdMarkerHue.info => gmap.BitmapDescriptor.hueBlue,
      };

  Color _flutterMapColor(UdMarkerHue hue) => switch (hue) {
        UdMarkerHue.brand => AppColors.secondary,
        UdMarkerHue.navy => AppColors.navy,
        UdMarkerHue.danger => AppColors.danger,
        UdMarkerHue.info => AppColors.info,
      };

  Widget _buildGoogle() {
    return gmap.GoogleMap(
      key: const ValueKey('ud-google-map'),
      initialCameraPosition: gmap.CameraPosition(
        target: gmap.LatLng(_center.latitude, _center.longitude),
        zoom: _zoom,
      ),
      onMapCreated: (controller) {
        if (!_googleController.isCompleted) {
          _googleController.complete(controller);
        }
      },
      myLocationEnabled: widget.showMyLocation,
      minMaxZoomPreference: widget.minZoom == null
          ? gmap.MinMaxZoomPreference.unbounded
          : gmap.MinMaxZoomPreference(widget.minZoom, null),
      onCameraMoveStarted: widget.onCameraMoveStarted,
      onCameraMove: (position) => _cameraTarget = LatLng(
        position.target.latitude,
        position.target.longitude,
      ),
      onCameraIdle: () {
        final target = _cameraTarget;
        if (target != null) widget.onCameraIdle?.call(target);
      },
      // The redesign supplies its own floating "locate me" button.
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      liteModeEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onTap: widget.onTap == null
          ? null
          : (position) =>
              widget.onTap!(LatLng(position.latitude, position.longitude)),
      // The map is a platform view. Left to its own devices it can win the
      // gesture arena for drags that started on a Flutter widget above it —
      // which is why dragging the booking sheet used to pan the map underneath.
      // Declaring the recognisers keeps the map to gestures that begin on the
      // map itself and lets Flutter's own widgets claim the rest.
      markers: widget.markers
          .map(
            (marker) => gmap.Marker(
              markerId: gmap.MarkerId(marker.id),
              position:
                  gmap.LatLng(marker.position.latitude, marker.position.longitude),
              icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                _googleHue(marker.hue),
              ),
              infoWindow: marker.label == null
                  ? gmap.InfoWindow.noText
                  : gmap.InfoWindow(title: marker.label),
              onTap: marker.onTap,
            ),
          )
          .toSet(),
      circles: widget.circles
          .map(
            (circle) => gmap.Circle(
              circleId: gmap.CircleId(circle.id),
              center:
                  gmap.LatLng(circle.centre.latitude, circle.centre.longitude),
              radius: circle.radiusMetres,
              fillColor: circle.fill.withValues(alpha: circle.fillOpacity),
              strokeColor:
                  circle.stroke.withValues(alpha: circle.strokeOpacity),
              strokeWidth: circle.strokeWidth.round(),
            ),
          )
          .toSet(),
      polylines: widget.polylines
          .map(
            (line) => gmap.Polyline(
              polylineId: gmap.PolylineId(line.id),
              color: line.color,
              width: line.width.round(),
              points: line.points
                  .map((point) => gmap.LatLng(point.latitude, point.longitude))
                  .toList(growable: false),
            ),
          )
          .toSet(),
    );
  }

  Widget _buildOffline() {
    final origin = widget.routeOrigin ?? _center;
    final destination = widget.routeDestination ?? _center;

    return fmap.FlutterMap(
      mapController: _offlineController,
      options: fmap.MapOptions(
        initialCenter: _center,
        initialZoom: _zoom,
        interactionOptions: fmap.InteractionOptions(
          flags: widget.interactive
              ? fmap.InteractiveFlag.pinchZoom | fmap.InteractiveFlag.drag
              : fmap.InteractiveFlag.none,
        ),
        minZoom: widget.minZoom,
        onPositionChanged: (position, hasGesture) {
          _cameraTarget = position.center;
          if (hasGesture) widget.onCameraMoveStarted?.call();
        },
        onMapEvent: (event) {
          if (event is fmap.MapEventMoveEnd ||
              event is fmap.MapEventFlingAnimationEnd) {
            final target = _cameraTarget;
            if (target != null) widget.onCameraIdle?.call(target);
          }
        },
        onTap: widget.onTap == null
            ? null
            : (_, point) => widget.onTap!(point),
      ),
      children: [
        // Resolves to a downloaded PMTiles pack when one covers this route,
        // otherwise to online OSM tiles.
        OfflineAwareTileLayer(origin: origin, destination: destination),
        if (widget.circles.isNotEmpty)
          fmap.CircleLayer(
            circles: widget.circles
                .map(
                  (circle) => fmap.CircleMarker(
                    point: circle.centre,
                    radius: circle.radiusMetres,
                    useRadiusInMeter: true,
                    color: circle.fill.withValues(alpha: circle.fillOpacity),
                    borderColor:
                        circle.stroke.withValues(alpha: circle.strokeOpacity),
                    borderStrokeWidth: circle.strokeWidth,
                  ),
                )
                .toList(growable: false),
          ),
        if (widget.polylines.isNotEmpty)
          fmap.PolylineLayer(
            polylines: widget.polylines
                .map(
                  (line) => fmap.Polyline(
                    points: line.points,
                    color: line.color,
                    strokeWidth: line.width,
                  ),
                )
                .toList(growable: false),
          ),
        if (widget.showMyLocation && widget.myLocation != null)
          fmap.CircleLayer(
            circles: [
              fmap.CircleMarker(
                point: widget.myLocation!,
                radius: 90,
                useRadiusInMeter: true,
                color: AppColors.info.withValues(alpha: .16),
                borderColor: Colors.transparent,
                borderStrokeWidth: 0,
              ),
            ],
          ),
        if (widget.showMyLocation && widget.myLocation != null)
          fmap.MarkerLayer(
            markers: [
              fmap.Marker(
                point: widget.myLocation!,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
        if (widget.markers.isNotEmpty)
          fmap.MarkerLayer(
            markers: widget.markers
                .map(
                  (marker) => fmap.Marker(
                    point: marker.position,
                    width: 34,
                    height: 34,
                    child: GestureDetector(
                      onTap: marker.onTap,
                      child: Icon(
                        Icons.place_rounded,
                        size: 32,
                        color: _flutterMapColor(marker.hue),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTint.mapBackdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Painted under the platform view so a slow or failed map area reads
          // as part of the dark app rather than a white hole in it.
          const ColoredBox(color: AppTint.mapBackdrop),
          if (_online) _buildGoogle() else _buildOffline(),
          if (!_online)
            const Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _OfflineMapBadge(),
            ),
        ],
      ),
    );
  }
}

class _OfflineMapBadge extends StatelessWidget {
  const _OfflineMapBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTint.warning,
          borderRadius: AppRadii.all(AppRadii.field),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 14, color: AppTint.warningText),
            SizedBox(width: 6),
            Text(
              'Offline map',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTint.warningText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
