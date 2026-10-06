import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'map_styles.dart';
import 'ud_vehicle_sprites.dart';

/// Which renderer [UdMap] is currently using.
enum UdMapSource {
  /// Google Maps SDK — the default whenever the device is online.
  google,

  /// flutter_map drawing OpenStreetMap tiles. Used when the device is offline
  /// or no Maps SDK key was supplied at build time.
  osm,
}

/// A map marker expressed independently of the underlying renderer.
class UdMarker {
  const UdMarker({
    required this.id,
    required this.position,
    this.label,
    this.hue = UdMarkerHue.brand,
    this.sprite,
    this.headingDegrees,
    this.onTap,
  });

  final String id;
  final LatLng position;
  final String? label;
  final UdMarkerHue hue;

  /// Draw a top-down vehicle lying on the map instead of a teardrop pin.
  ///
  /// Used for the live vehicles around the customer. A pin says something is
  /// here; a car pointing down the road says a driver is here and which way
  /// they are facing, which is the question actually being asked.
  final UdVehicleSprite? sprite;

  /// Compass bearing for a [sprite], 0 = north.
  ///
  /// Null leaves the sprite unrotated. A stationary phone reports no heading,
  /// and pointing every parked car north would be inventing information.
  final double? headingDegrees;

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
    this.onTap,
  });

  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;

  /// Tapping the line selects it. Used for choosing between alternative
  /// routes the way a taxi app does — the customer points at the road they
  /// want rather than reading a list.
  final VoidCallback? onTap;
}

/// A translucent circle, used for the "vehicles within N km" ring on Home.
class UdCircle {
  UdCircle({
    required this.id,
    required this.centre,
    required this.radiusMetres,
    this.fill,
    this.fillOpacity = .09,
    this.stroke,
    this.strokeOpacity = .42,
    this.strokeWidth = 1.5,
  });

  final String id;
  final LatLng centre;
  final double radiusMetres;

  /// Null means the app's accent, resolved when the circle is drawn.
  ///
  /// It cannot be defaulted to `AppColors.secondary` here. Every default
  /// parameter value in Dart must be a compile-time constant — const
  /// constructor or not — and the accent is a runtime getter now, because the
  /// customer can change it.
  final Color? fill;

  final double fillOpacity;

  /// Null means the app's accent. See [fill].
  final Color? stroke;

  final double strokeOpacity;
  final double strokeWidth;

  /// The colours to paint with, with the accent filled in.
  Color get fillColour => fill ?? AppColors.secondary;
  Color get strokeColour => stroke ?? AppColors.secondary;
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

  /// Points the camera the way a navigation app does: centred on [target],
  /// turned so [bearing] is up, and tilted by [tilt] degrees.
  ///
  /// Used by the live-ride screens, once per fix. Google animates the move,
  /// so the map glides with the car rather than stepping after it.
  Future<void> follow(
    LatLng target, {
    required double zoom,
    double bearing = 0,
    double tilt = 0,
  }) async {
    await _state?._follow(target, zoom: zoom, bearing: bearing, tilt: tilt);
  }

  void dispose() => _state = null;
}

/// The single map surface used across UDrive.
///
/// Behaviour, as agreed with the product owner:
///
/// * Online  → Google Maps (Maps SDK), the primary experience.
/// * Otherwise → flutter_map drawing OpenStreetMap tiles.
///
/// Switching is automatic and driven by [Connectivity]. Both renderers need a
/// network: UDrive carries no offline map data, so a customer in a valley with
/// no signal sees whatever tiles the phone already cached and a badge telling
/// them the connection is gone.
class UdMap extends StatefulWidget {
  const UdMap({
    required this.initialCenter,
    this.controller,
    this.zoom = AppConfig.defaultMapZoom,
    this.markers = const [],
    this.polylines = const [],
    this.circles = const [],
    this.showMyLocation = true,
    this.myLocation,
    this.minZoom,
    this.onCameraMoveStarted,
    this.onCameraIdle,
    this.interactive = true,
    this.darkStyle = false,
    this.onTap,
    this.onSourceChanged,
    this.keepGoogleOffline = false,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final LatLng initialCenter;
  final UdMapController? controller;
  final double zoom;
  final List<UdMarker> markers;
  final List<UdPolyline> polylines;
  final List<UdCircle> circles;

  final bool showMyLocation;

  /// Drawn as a blue dot with an accuracy halo when the OSM renderer is active.
  /// Google draws its own dot from [showMyLocation], so this is only used by
  /// flutter_map — pass it anyway and both paths look the same.
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

  /// Use the dark palette instead of the light one.
  ///
  /// Off by default, because the customer's map is the common case and it is
  /// light. The driver screens, which sit on dark chrome, pass true.
  final bool darkStyle;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<UdMapSource>? onSourceChanged;

  /// Stay on Google's map when the connection drops, instead of switching to
  /// OpenStreetMap.
  ///
  /// The live-ride screens set this. Switching renderers mid-ride throws away
  /// the Google tiles already on the phone and replaces them with OSM tiles
  /// that cannot load either, so the driver ends up with a blank map exactly
  /// where they most need one. Staying put keeps every tile Google already
  /// drew, and the GPS car, the stored route and the Urdu voice carry on over
  /// them with no network at all.
  final bool keepGoogleOffline;

  /// Space the map should treat as covered at its edges.
  ///
  /// Google centres the camera inside what is left, so a large top padding
  /// puts the followed car low on the screen with the road ahead of it in
  /// view — the way a navigation app frames it. Ignored on the OSM fallback.
  final EdgeInsets padding;

  @override
  State<UdMap> createState() => _UdMapState();
}

class _UdMapState extends State<UdMap> {

  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  final Completer<gmap.GoogleMapController> _googleController =
      Completer<gmap.GoogleMapController>();
  final fmap.MapController _osmController = fmap.MapController();

  bool _online = true;

  /// Google Maps is used on mobile only.
  ///
  /// `google_maps_flutter_web` renders the map as a DOM element composited
  /// alongside Flutter's canvas, and that arrangement proved unreliable here:
  /// blank tiles, a tile grid showing through, a route drawn as straight
  /// segments, and styling that applied on one load and not the next. Days went
  /// into it and each fix moved the symptom rather than removing it.
  ///
  /// flutter_map draws everything on Flutter's own canvas. No platform view, no
  /// separate compositing layer, and a polyline that is guaranteed to follow the
  /// points it is given. On Android and iOS the Google SDK is native and has
  /// none of these problems, so it stays.
  ///
  /// The trade-off is that web shows OpenStreetMap rather than Google's
  /// cartography. Web is the testing surface; customers will be on Android.
  bool get _useGoogle => !kIsWeb && (_online || widget.keepGoogleOffline);

  /// Where the camera currently points. Tracked so the idle callback can report
  /// it — Google gives the position during the move, not at the end.
  LatLng? _cameraTarget;

  /// A camera move requested before the map existed.
  ///
  /// Both renderers refuse camera commands until they are ready, and dropping
  /// the request left the map at its initial position — which is how a route
  /// could be drawn while the camera sat somewhere else entirely.
  ({LatLng target, double zoom})? _pendingCamera;

  /// flutter_map only accepts camera commands after `onMapReady`.
  bool _osmReady = false;

  /// Rasterised vehicle sprites for the Google renderer, by shape.
  ///
  /// Built once when the map first needs them and reused after that. Google
  /// takes a bitmap rather than a widget, and rasterising one per vehicle per
  /// presence poll is the sort of work that shows as stutter on a cheap phone.
  final Map<UdVehicleSprite, gmap.BitmapDescriptor> _spriteBitmaps =
      <UdVehicleSprite, gmap.BitmapDescriptor>{};

  bool _loadingSprites = false;

  late LatLng _center;
  late double _zoom;

  UdMapSource get _source =>
      _online || (widget.keepGoogleOffline && !kIsWeb)
          ? UdMapSource.google
          : UdMapSource.osm;

  /// Google polylines built from the last [UdMap.polylines] list.
  ///
  /// The live-ride screens rebuild this widget many times a second while the
  /// car glides, and a mountain route can be thousands of points. Converting
  /// all of them on every frame is exactly the garbage that shows as stutter,
  /// so the conversion is redone only when the caller hands over a new list.
  List<UdPolyline>? _polylineSource;
  Set<gmap.Polyline> _googlePolylines = const <gmap.Polyline>{};

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureSprites();
  }

  @override
  void didUpdateWidget(covariant UdMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    _ensureSprites();
  }

  /// Rasterises any vehicle sprite this map needs and has not built yet.
  ///
  /// Only the shapes actually asked for: a screen showing cars should not pay
  /// to draw a coach it will never display.
  Future<void> _ensureSprites() async {
    if (_loadingSprites || !_useGoogle) return;

    final wanted = <UdVehicleSprite>{
      for (final marker in widget.markers)
        if (marker.sprite != null) marker.sprite!,
    }..removeWhere(_spriteBitmaps.containsKey);
    if (wanted.isEmpty) return;

    _loadingSprites = true;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    try {
      for (final sprite in wanted) {
        final bytes =
            await UdVehicleSprites.bytes(sprite, pixelRatio: ratio);
        if (!mounted) return;
        _spriteBitmaps[sprite] = gmap.BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: ratio,
        );
      }
    } catch (_) {
      // A sprite that will not rasterise is not worth losing the map over.
      // Those markers keep the teardrop pin.
    } finally {
      _loadingSprites = false;
    }

    if (mounted) setState(() {});
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
    // Refuse coordinates that cannot be real. A null island (0, 0) or a NaN
    // slipping through a calculation puts the camera in the Atlantic, which is
    // what the flat grey-and-cyan map was.
    if (!target.latitude.isFinite ||
        !target.longitude.isFinite ||
        (target.latitude.abs() < 0.01 && target.longitude.abs() < 0.01)) {
      return;
    }

    var nextZoom = zoom ?? _zoom;
    if (!nextZoom.isFinite) nextZoom = AppConfig.defaultMapZoom;
    nextZoom = nextZoom.clamp(widget.minZoom ?? 3.0, 21.0);
    _center = target;
    _zoom = nextZoom;

    if (_useGoogle) {
      if (!_googleController.isCompleted) {
        // Remember it and apply once the map reports itself created.
        _pendingCamera = (target: target, zoom: nextZoom);
        return;
      }
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
      if (!_osmReady) {
        _pendingCamera = (target: target, zoom: nextZoom);
        return;
      }
      try {
        _osmController.move(target, nextZoom);
      } catch (_) {
        // The controller can still refuse if the map is mid-teardown. Holding
        // the request is better than losing it silently, which is how the map
        // ended up sitting at its initial camera showing open ocean.
        _pendingCamera = (target: target, zoom: nextZoom);
      }
    }
  }

  Future<void> _follow(
    LatLng target, {
    required double zoom,
    required double bearing,
    required double tilt,
  }) async {
    if (!target.latitude.isFinite ||
        !target.longitude.isFinite ||
        (target.latitude.abs() < 0.01 && target.longitude.abs() < 0.01)) {
      return;
    }

    final nextZoom = (zoom.isFinite ? zoom : AppConfig.defaultMapZoom)
        .clamp(widget.minZoom ?? 3.0, 21.0)
        .toDouble();
    final nextBearing = bearing.isFinite ? bearing % 360 : 0.0;
    final nextTilt = tilt.isFinite ? tilt.clamp(0.0, 60.0).toDouble() : 0.0;
    _center = target;
    _zoom = nextZoom;

    if (_useGoogle) {
      if (!_googleController.isCompleted) {
        _pendingCamera = (target: target, zoom: nextZoom);
        return;
      }
      final controller = await _googleController.future;
      try {
        await controller.animateCamera(
          gmap.CameraUpdate.newCameraPosition(
            gmap.CameraPosition(
              target: gmap.LatLng(target.latitude, target.longitude),
              zoom: nextZoom,
              bearing: nextBearing,
              tilt: nextTilt,
            ),
          ),
        );
      } catch (_) {
        // The map can be mid-teardown when the screen closes; the next fix
        // tries again.
      }
      return;
    }

    if (!_osmReady) {
      _pendingCamera = (target: target, zoom: nextZoom);
      return;
    }
    try {
      // flutter_map turns the map, not the camera: heading-up is the
      // negative of the bearing.
      _osmController.moveAndRotate(target, nextZoom, -nextBearing);
    } catch (_) {
      _pendingCamera = (target: target, zoom: nextZoom);
    }
  }

  Set<gmap.Polyline> _buildGooglePolylines() {
    if (_samePolylines(_polylineSource, widget.polylines)) {
      return _googlePolylines;
    }
    _polylineSource = widget.polylines;
    _googlePolylines = widget.polylines
        .map(
          (line) => gmap.Polyline(
            polylineId: gmap.PolylineId(line.id),
            color: line.color,
            width: line.width.round(),
            startCap: gmap.Cap.roundCap,
            endCap: gmap.Cap.roundCap,
            jointType: gmap.JointType.round,
            consumeTapEvents: line.onTap != null,
            onTap: line.onTap,
            points: _thin(line.points)
                .map((point) => gmap.LatLng(point.latitude, point.longitude))
                .toList(growable: false),
          ),
        )
        .toSet();
    return _googlePolylines;
  }

  /// Whether two polyline lists draw the same thing.
  ///
  /// The live screens hand over a new list literal on every frame of the car's
  /// glide, so the old `identical` check on the list never matched and an
  /// intercity road of thousands of points was converted — and diffed by the
  /// map plugin — ten to twenty times a second. Comparing each line's own
  /// point list by identity matches whenever the road itself has not changed.
  static bool _samePolylines(List<UdPolyline>? a, List<UdPolyline> b) {
    if (a == null) return false;
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          !identical(x.points, y.points) ||
          x.color != y.color ||
          x.width != y.width ||
          !identical(x.onTap, y.onTap)) {
        return false;
      }
    }
    return true;
  }

  /// A long road with points closer together than the eye can tell apart
  /// removed (Douglas–Peucker, two metres). A mountain road from Google's
  /// high-quality line can carry thousands of points; the map draws the same
  /// shape from a few hundred, with far less work on a cheap phone.
  static List<LatLng> _thin(List<LatLng> points) {
    if (points.length <= 400) return points;
    const toleranceMetres = 2.0;
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;

    final cos = math.cos(points.first.latitude * math.pi / 180);
    const metresPerDegree = 111320.0;
    double x(LatLng p) => p.longitude * metresPerDegree * cos;
    double y(LatLng p) => p.latitude * metresPerDegree;

    final stack = <List<int>>[
      [0, points.length - 1]
    ];
    while (stack.isNotEmpty) {
      final range = stack.removeLast();
      final first = range[0];
      final last = range[1];
      if (last - first < 2) continue;
      final ax = x(points[first]), ay = y(points[first]);
      final bx = x(points[last]), by = y(points[last]);
      final dx = bx - ax, dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      var worst = -1.0;
      var worstIndex = -1;
      for (var i = first + 1; i < last; i++) {
        final px = x(points[i]) - ax, py = y(points[i]) - ay;
        double distance;
        if (lengthSquared == 0) {
          distance = math.sqrt(px * px + py * py);
        } else {
          final t = ((px * dx + py * dy) / lengthSquared).clamp(0.0, 1.0);
          final ex = px - t * dx, ey = py - t * dy;
          distance = math.sqrt(ex * ex + ey * ey);
        }
        if (distance > worst) {
          worst = distance;
          worstIndex = i;
        }
      }
      if (worst > toleranceMetres && worstIndex > 0) {
        keep[worstIndex] = true;
        stack
          ..add([first, worstIndex])
          ..add([worstIndex, last]);
      }
    }

    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i]
    ];
  }

  /// Frames a set of points by computing the camera directly.
  ///
  /// Google's `newLatLngBounds` is not used. It has to be given a viewport it
  /// can satisfy, it interacts badly with a zoom floor, and on web a request it
  /// cannot fulfil leaves the camera in a state that renders no tiles — which
  /// is what produced the blank map. Working out the zoom from the span and the
  /// widget's own size is deterministic and behaves identically on both
  /// renderers.
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

    final centre = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    _center = centre;

    // Two points a few hundred metres apart do not need framing; centring is
    // simpler and avoids an absurd zoom.
    const minimumSpanDegrees = 0.004; // roughly 400 m
    if ((maxLat - minLat) < minimumSpanDegrees &&
        (maxLng - minLng) < minimumSpanDegrees) {
      await _moveTo(centre, zoom: AppConfig.focusedMapZoom);
      return;
    }

    final size = context.size ?? const Size(360, 320);
    // Leave room around the route so it does not touch the edges.
    final usableWidth = math.max(size.width - padding * 2, 64.0);
    final usableHeight = math.max(size.height - padding * 2, 64.0);

    // At zoom z the world is 256 * 2^z pixels wide. Find the largest zoom at
    // which the span still fits both axes. Longitude is compared against a
    // 360-degree world; latitude against 180, with a cosine correction for the
    // Mercator stretch away from the equator.
    final latSpan = math.max(maxLat - minLat, 1e-6);
    final lngSpan = math.max(maxLng - minLng, 1e-6);
    final latRadians = centre.latitude * math.pi / 180;
    final mercatorFactor = math.max(math.cos(latRadians).abs(), 0.05);

    final zoomForLng = _log2(usableWidth * 360 / (256 * lngSpan));
    final zoomForLat =
        _log2(usableHeight * 360 * mercatorFactor / (256 * latSpan));

    final zoom = math.min(zoomForLng, zoomForLat).clamp(
          widget.minZoom ?? 3.0,
          AppConfig.focusedMapZoom,
        );

    await _moveTo(centre, zoom: zoom);
  }

  static double _log2(double value) =>
      value <= 0 ? 0 : math.log(value) / math.ln2;

  /// The tappable polyline closest to [point], if one is within reach.
  ///
  /// Measures the distance to each *segment*, not to the vertices. A long
  /// straight stretch of motorway has vertices kilometres apart, so comparing
  /// against vertices alone made the middle of that stretch untappable — which
  /// is exactly where someone aims.
  ///
  /// The tolerance is in screen pixels converted to degrees at the live zoom,
  /// so it stays the same physical target whether the map shows a street or a
  /// whole valley.
  UdPolyline? _polylineNear(LatLng point) {
    final tappable =
        widget.polylines.where((line) => line.onTap != null).toList();
    if (tappable.isEmpty) return null;

    // Read the zoom from the map rather than the cached field: the customer may
    // have pinched since the last programmatic move.
    var zoom = _zoom;
    if (!_useGoogle) {
      try {
        zoom = _osmController.camera.zoom;
      } catch (_) {
        // Controller not attached yet; the cached value is close enough.
      }
    }

    // 22 logical pixels — a comfortable thumb target, and roughly what map
    // apps allow for tapping a route.
    final tolerance = 22 * 360 / (256 * math.pow(2, zoom));
    // Longitude degrees shrink towards the poles; without this a tap north of
    // the equator needs to be more accurate horizontally than vertically.
    final lngScale = math.max(math.cos(point.latitude * math.pi / 180), 0.1);

    UdPolyline? best;
    var bestDistance = double.infinity;

    for (final line in tappable) {
      for (var i = 0; i < line.points.length - 1; i++) {
        final distance = _distanceToSegment(
          point,
          line.points[i],
          line.points[i + 1],
          lngScale,
        );
        if (distance < bestDistance) {
          bestDistance = distance;
          best = line;
        }
      }
    }

    return bestDistance <= tolerance ? best : null;
  }

  /// Perpendicular distance from [p] to the segment [a]–[b], in degrees.
  static double _distanceToSegment(
    LatLng p,
    LatLng a,
    LatLng b,
    double lngScale,
  ) {
    final px = (p.longitude - a.longitude) * lngScale;
    final py = p.latitude - a.latitude;
    final bx = (b.longitude - a.longitude) * lngScale;
    final by = b.latitude - a.latitude;

    final lengthSquared = bx * bx + by * by;
    // Degenerate segment: fall back to the distance to the point itself.
    if (lengthSquared == 0) return math.sqrt(px * px + py * py);

    // Where along the segment the perpendicular lands, clamped to its ends so
    // a tap beyond either end measures to that end rather than to the
    // infinite line.
    final t = ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
    final dx = px - t * bx;
    final dy = py - t * by;
    return math.sqrt(dx * dx + dy * dy);
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
      // Light by default. The map is the one part of the screen a person is
      // reading rather than looking at — street names, junctions, which side
      // of the road a pin is on — and a dark tint costs legibility in daylight.
      style: widget.darkStyle ? MapStyles.dark : MapStyles.light,
      initialCameraPosition: gmap.CameraPosition(
        target: gmap.LatLng(_center.latitude, _center.longitude),
        zoom: _zoom,
      ),
      onMapCreated: (controller) {
        if (!_googleController.isCompleted) {
          _googleController.complete(controller);
        }
        // Apply anything requested while the map was still being created.
        final pending = _pendingCamera;
        if (pending != null) {
          _pendingCamera = null;
          controller.moveCamera(
            gmap.CameraUpdate.newCameraPosition(
              gmap.CameraPosition(
                target: gmap.LatLng(
                  pending.target.latitude,
                  pending.target.longitude,
                ),
                zoom: pending.zoom,
              ),
            ),
          );
        }
      },
      myLocationEnabled: widget.showMyLocation,
      padding: widget.padding,
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
            (marker) {
              final sprite = marker.sprite;
              // Sprites are rasterised off the build, so the first frame after
              // a presence poll may not have one yet. Falling back to the pin
              // for that frame is better than dropping the vehicle entirely
              // and making the map flicker.
              final bitmap = sprite == null ? null : _spriteBitmaps[sprite];

              return gmap.Marker(
                markerId: gmap.MarkerId(marker.id),
                position: gmap.LatLng(
                  marker.position.latitude,
                  marker.position.longitude,
                ),
                icon: bitmap ??
                    gmap.BitmapDescriptor.defaultMarkerWithHue(
                      _googleHue(marker.hue),
                    ),
                // A vehicle lies flat on the road and turns with it. A pin
                // stands up and always faces the reader.
                flat: bitmap != null,
                rotation: bitmap == null ? 0 : (marker.headingDegrees ?? 0),
                anchor: bitmap == null
                    ? const Offset(.5, 1)
                    : const Offset(.5, .5),
                // No bubble on a vehicle. The real app shows none, and a
                // caption over every car buries the map it is drawn on.
                infoWindow: marker.label == null || bitmap != null
                    ? gmap.InfoWindow.noText
                    : gmap.InfoWindow(title: marker.label),
                onTap: marker.onTap,
              );
            },
          )
          .toSet(),
      circles: widget.circles
          .map(
            (circle) => gmap.Circle(
              circleId: gmap.CircleId(circle.id),
              center:
                  gmap.LatLng(circle.centre.latitude, circle.centre.longitude),
              radius: circle.radiusMetres,
              fillColor: circle.fillColour.withValues(alpha: circle.fillOpacity),
              strokeColor:
                  circle.strokeColour.withValues(alpha: circle.strokeOpacity),
              strokeWidth: circle.strokeWidth.round(),
            ),
          )
          .toSet(),
      polylines: _buildGooglePolylines(),
    );
  }

  Widget _buildOsm() {
    return fmap.FlutterMap(
      mapController: _osmController,
      options: fmap.MapOptions(
        initialCenter: _center,
        initialZoom: _zoom,
        interactionOptions: fmap.InteractionOptions(
          flags: widget.interactive
              // Double tap and the two-finger gestures were missing, which is
              // why double tapping did nothing: flutter_map only honours the
              // flags it is given, and these were never listed.
              ? fmap.InteractiveFlag.pinchZoom |
                  fmap.InteractiveFlag.drag |
                  fmap.InteractiveFlag.doubleTapZoom |
                  fmap.InteractiveFlag.doubleTapDragZoom |
                  fmap.InteractiveFlag.scrollWheelZoom |
                  fmap.InteractiveFlag.flingAnimation
              : fmap.InteractiveFlag.none,
        ),
        // No minZoom, maxZoom or cameraConstraint here.
        //
        // Each limit added during debugging caused a failure rather than
        // preventing one: a zoom floor made long routes impossible to frame,
        // and a camera constraint repositioned the map on its own. The only
        // remaining protection is in _moveTo, which refuses coordinates that
        // cannot be real.
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
        onMapReady: () {
          _osmReady = true;
          final pending = _pendingCamera;
          if (pending != null) {
            _pendingCamera = null;
            _osmController.move(pending.target, pending.zoom);
          }
        },
        onTap: widget.onTap == null
            ? null
            : (_, point) => widget.onTap!(point),
      ),
      children: [
        fmap.TileLayer(
          // Tiles stop being fetched past zoom 17; beyond that the
          // ones already held are scaled up.
          //
          // OpenStreetMap serves to 19, and every extra level is a fresh
          // set of 256px PNGs — about 400 KB for one screenful. The app's
          // own zooms stop at 16.2 (the pickup view), so nothing it does
          // by itself is softened; only a customer pinching in past 17
          // sees slightly smoother tiles instead of waiting for new ones
          // on a connection that cannot spare them.
          maxNativeZoom: 17,
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.wabwar.udrive',
        ),
        if (widget.circles.isNotEmpty)
          fmap.CircleLayer(
            circles: widget.circles
                .map(
                  (circle) => fmap.CircleMarker(
                    point: circle.centre,
                    radius: circle.radiusMetres,
                    useRadiusInMeter: true,
                    color: circle.fillColour.withValues(alpha: circle.fillOpacity),
                    borderColor:
                        circle.strokeColour.withValues(alpha: circle.strokeOpacity),
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
                    // A dark border keeps the route legible over pale streets,
                    // the same job the casing does on the Google renderer.
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 2,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                )
                .toList(growable: false),
          ),
        // Attribution, as small as the terms allow.
        //
        // Google's terms require it to be visible on Map Tiles imagery, so it
        // cannot be removed — but `SimpleAttributionWidget` painted a black bar
        // across the map reading "flutter_map | © Google · © OpenStreetMap".
        // Two thirds of that is not required by anyone: "flutter_map" is the
        // name of a library, and OpenStreetMap is only the fallback source.
        //
        // A plain label in the corner, the way Google's own SDK does it.
        const Align(
          alignment: Alignment.bottomLeft,
          child: IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(left: 7, bottom: 3),
              child: Text(
                'Google',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: .2,
                  color: AppText.disabled,
                ),
              ),
            ),
          ),
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
            markers: widget.markers.map((marker) {
              final sprite = marker.sprite;
              if (sprite == null) {
                return fmap.Marker(
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
                );
              }

              // Same shapes as the online map, painted rather than rasterised.
              // Two maps that disagree about what a car looks like would be a
              // strange thing for a customer to discover offline.
              final size = UdVehicleSprites.size;
              return fmap.Marker(
                point: marker.position,
                width: size.width,
                height: size.height,
                child: GestureDetector(
                  onTap: marker.onTap,
                  child: Transform.rotate(
                    angle: (marker.headingDegrees ?? 0) * math.pi / 180,
                    child: CustomPaint(
                      painter: UdVehicleSpritePainter(sprite),
                      size: size,
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
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
          if (_useGoogle) _buildGoogle() else _buildOsm(),
          if (!_online)
            const Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _NoConnectionBadge(),
            ),
        ],
      ),
    );
  }
}

/// Shown whenever [Connectivity] reports no network.
///
/// It used to read "Offline map", from when UDrive shipped downloadable map
/// packs. It no longer does, so the honest message is that the map is stale,
/// not that an offline map is in use.
class _NoConnectionBadge extends StatelessWidget {
  const _NoConnectionBadge();

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
              'No internet connection',
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
