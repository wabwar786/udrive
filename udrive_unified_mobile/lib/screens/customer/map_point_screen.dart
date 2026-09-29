import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/maps/ud_map.dart';
import '../../core/services/place_search_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'place_search_screen.dart';

/// Drag the map, drop a pin, take the address under it.
///
/// Built because a geocoder is not the whole map. Plenty of places in Neelum,
/// Bagh and Hattian have no address a search box will find — a turning off the
/// Neelum road, a guest house past the last named street, the spot the customer
/// is actually standing in — and until now the only way to set a destination
/// was to name it. If the name did not exist, the trip did not either.
///
/// It is the same interaction the pickup pin on Home already uses, given its
/// own screen so the pin gets the whole map instead of a 300px band, and so it
/// can serve both ends of the route.
///
/// Returns a [PlacePickResult], the same type the search screen returns, so a
/// caller can treat "found by name" and "pointed at on the map" identically.
class MapPointScreen extends StatefulWidget {
  const MapPointScreen({
    required this.initialPoint,
    required this.forPickup,
    this.initialLabel = '',
    this.pickupPoint,
    super.key,
  });

  /// Where the camera opens. The current end being edited if there is one,
  /// otherwise the pickup — never an arbitrary default, because a pin the
  /// customer has to drag across a district is not a shortcut.
  final LatLng initialPoint;

  /// Which end this is setting. Only changes wording; the interaction is one.
  final bool forPickup;

  final String initialLabel;

  /// Used for the "N km away" line. Null when setting the pickup itself.
  final LatLng? pickupPoint;

  @override
  State<MapPointScreen> createState() => _MapPointScreenState();
}

class _MapPointScreenState extends State<MapPointScreen> {
  final _controller = UdMapController();
  final _places = PlaceSearchService();
  final _distance = const Distance();

  late LatLng _point = widget.initialPoint;
  late String _label = widget.initialLabel.trim();

  bool _dragging = false;
  bool _resolving = false;

  /// Guards against a lookup on every tiny settle. Same 40 m rule the Home pin
  /// uses — each reverse geocode is billed, and a pin that moved three metres
  /// is in the same place.
  LatLng? _lastResolved;

  /// Rises with every lookup so a slow answer for an old position can never
  /// overwrite the label for the position the customer settled on.
  int _resolveToken = 0;

  @override
  void initState() {
    super.initState();
    // The label may be empty (pin dropped from a blank destination) or stale
    // (the customer opened this to correct it), so resolve what is under the
    // pin as soon as the screen is up rather than showing the old name.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_label.isEmpty) _resolve(_point, force: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _places.dispose();
    super.dispose();
  }

  String get _title =>
      widget.forPickup ? 'Move the pickup' : 'Move the destination';

  void _onDragStart() {
    if (!_dragging && mounted) setState(() => _dragging = true);
  }

  Future<void> _onSettled(LatLng centre) async {
    if (mounted && _dragging) setState(() => _dragging = false);
    await _resolve(centre);
  }

  Future<void> _resolve(LatLng centre, {bool force = false}) async {
    final previous = _lastResolved;
    if (!force && previous != null) {
      final moved = (previous.latitude - centre.latitude).abs() +
          (previous.longitude - centre.longitude).abs();
      if (moved < 0.0004) return; // roughly 40 m
    }
    _lastResolved = centre;

    final token = ++_resolveToken;
    setState(() {
      _point = centre;
      _resolving = true;
    });

    final address = await _places.reverseGeocode(
      centre.latitude,
      centre.longitude,
    );
    if (!mounted || token != _resolveToken) return;

    setState(() {
      // Coordinates are a poor label, but they are an honest one, and they are
      // still a place the driver can be sent to.
      _label = address.isNotEmpty
          ? address
          : '${centre.latitude.toStringAsFixed(5)}, '
              '${centre.longitude.toStringAsFixed(5)}';
      _resolving = false;
    });
  }

  /// How far the pin is from the pickup, in whole kilometres.
  String? get _distanceLine {
    final from = widget.pickupPoint;
    if (from == null || widget.forPickup) return null;
    final km = _distance.as(LengthUnit.Kilometer, from, _point);
    if (km <= 0) return null;
    return km < 1
        ? 'Less than 1 km from your pickup'
        : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km from your pickup';
  }

  void _confirm() {
    Navigator.pop(
      context,
      PlacePickResult(
        label: _label.trim(),
        point: _point,
        forPickup: widget.forPickup,
      ),
    );
  }

  /// Hands the customer back to the search box without losing this screen's
  /// place in the stack: if they find somewhere by name, that answer travels
  /// straight out to whoever opened the map.
  Future<void> _search() async {
    final result = await Navigator.push<PlacePickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceSearchScreen(
          title: widget.forPickup ? 'Set pickup' : 'Set destination',
          editingPickup: widget.forPickup,
          pickupLabel: widget.forPickup ? _label : '',
          destinationLabel: widget.forPickup ? '' : _label,
          bias: widget.pickupPoint ?? _point,
        ),
      ),
    );
    if (result == null || !mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: UdMap(
              controller: _controller,
              initialCenter: widget.initialPoint,
              zoom: AppConfig.pickupZoom,
              minZoom: 5,
              showMyLocation: widget.forPickup,
              onCameraMoveStarted: _onDragStart,
              onCameraIdle: _onSettled,
              markers: [
                // The other end of the trip, so the customer can see which way
                // they are dragging. Not drawn when it would sit under the pin.
                if (!widget.forPickup && widget.pickupPoint != null)
                  UdMarker(
                    id: 'pickup',
                    position: widget.pickupPoint!,
                    label: 'Pickup',
                    hue: UdMarkerHue.navy,
                  ),
              ],
            ),
          ),

          // The pin. Centred, and pointer-transparent so every gesture belongs
          // to the map underneath it — the pin does not move, the map does.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(child: _DropPin(lifted: _dragging)),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _RoundButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: AppRadii.all(AppRadii.field),
                            boxShadow: AppShadows.panel,
                          ),
                          child: Text(_title, style: AppType.barTitle),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Center(child: _Hint()),
                ],
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Sheet(
              caption: widget.forPickup ? 'PICKUP' : 'DESTINATION',
              confirmLabel:
                  widget.forPickup ? 'Confirm pickup' : 'Confirm destination',
              label: _label,
              resolving: _resolving,
              distanceLine: _distanceLine,
              bottomInset: bottomInset,
              onSearch: _search,
              onConfirm: _resolving || _label.trim().isEmpty ? null : _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pin itself: a lime teardrop that lifts off the map while it moves.
class _DropPin extends StatelessWidget {
  const _DropPin({required this.lifted});

  final bool lifted;

  @override
  Widget build(BuildContext context) {
    // Anchored on the tip, not the middle: the tip is the point being chosen,
    // so the column is lifted by half its height and then dropped back by the
    // tip's own half — otherwise the pin marks a spot a pin's height away from
    // the one the map is centred on.
    return FractionalTranslation(
      translation: const Offset(0, -.5),
      child: Transform.translate(
        offset: const Offset(0, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: lifted ? 0 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: AppRadii.all(AppRadii.chip),
                  boxShadow: AppShadows.panel,
                ),
                child: Text(
                  'Drop here',
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onInk,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, lifted ? -8 : 0, 0),
              child: const _Teardrop(),
            ),
            // The shadow stays on the ground while the pin lifts, which is what
            // makes the lift read as height rather than as the pin sliding.
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: lifted ? 16 : 10,
              height: 4,
              decoration: BoxDecoration(
                color: AppTint.shadow,
                borderRadius: AppRadii.all(AppRadii.chip),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Teardrop extends StatelessWidget {
  const _Teardrop();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 54,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // The tail, drawn as a rotated square behind the disc so the two
          // shapes meet without a seam.
          Positioned(
            top: 20,
            child: Transform.rotate(
              angle: 0.785398, // 45°
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.navy, width: 2.5),
                ),
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.navy, width: 2.5),
            ),
            child: const Icon(Icons.add_rounded, size: 20, color: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadii.all(AppRadii.chip),
        boxShadow: AppShadows.panel,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.open_with_rounded, size: 18, color: AppColors.brand),
          const SizedBox(width: 9),
          Text(
            'Drag the map to move the pin',
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.onInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Shadow on the outside, ink on the inside. The other way round paints the
    // shadow inside the button, where it reads as a smudge rather than lift.
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadii.all(AppRadii.field),
        boxShadow: AppShadows.panel,
      ),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.field),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(AppRadii.field),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, size: 22, color: AppColors.navy),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.caption,
    required this.confirmLabel,
    required this.label,
    required this.resolving,
    required this.distanceLine,
    required this.bottomInset,
    required this.onSearch,
    required this.onConfirm,
  });

  final String caption;
  final String confirmLabel;
  final String label;
  final bool resolving;
  final String? distanceLine;
  final double bottomInset;
  final VoidCallback onSearch;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + bottomInset),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.sheetTop(),
        boxShadow: AppShadows.panel,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UdSheetHandle(),
          Text(caption, style: AppType.overline.copyWith(color: AppText.caption)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandWash,
                  borderRadius: AppRadii.all(AppRadii.tile),
                ),
                child: const Icon(Icons.place_outlined,
                    size: 22, color: AppColors.brandInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Height is held steady between states so the sheet does
                    // not jump every time the address is looked up again.
                    resolving
                        ? Text(
                            'Finding this place…',
                            style: AppType.h3.copyWith(color: AppText.secondary),
                          )
                        : Text(
                            label.isEmpty ? 'Move the map' : label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.h3,
                          ),
                    if (distanceLine != null && !resolving) ...[
                      const SizedBox(height: 3),
                      Text(
                        distanceLine!,
                        style: AppType.small.copyWith(color: AppText.secondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          UdButton(
            label: 'Or search for a place instead',
            icon: Icons.search_rounded,
            variant: UdButtonVariant.outline,
            size: UdButtonSize.small,
            onPressed: onSearch,
          ),
          const SizedBox(height: 10),
          UdButton(
            label: confirmLabel,
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'The address updates as you move the map.',
              style: AppType.caption.copyWith(color: AppText.caption),
            ),
          ),
        ],
      ),
    );
  }
}
