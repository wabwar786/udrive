import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/explore/explore_repository.dart';
import '../../core/maps/ud_map.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'explore_bits.dart';

/// Every place on one map. Tap a pin for its card; "Go here" hands the drive
/// to the phone's Google Maps app, so no Routes credit is used.
class ExploreMapScreen extends StatefulWidget {
  const ExploreMapScreen({
    required this.places,
    required this.onOpen,
    this.focusId,
    super.key,
  });

  final List<ExplorePlace> places;
  final ValueChanged<ExplorePlace> onOpen;

  /// Opened from one place: that pin starts selected and centred.
  final String? focusId;

  @override
  State<ExploreMapScreen> createState() => _ExploreMapScreenState();
}

class _ExploreMapScreenState extends State<ExploreMapScreen> {
  final UdMapController _map = UdMapController();
  final TextEditingController _search = TextEditingController();
  ExplorePlace? _picked;
  LatLng? _me;

  List<ExplorePlace> get _mappable => widget.places
      .where((p) => p.latitude != 0 || p.longitude != 0)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    for (final p in _mappable) {
      if (p.id == widget.focusId) _picked = p;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _frame());
    ExploreLocation.get().then((me) {
      if (mounted && me != null) setState(() => _me = me);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _frame() {
    final picked = _picked;
    if (picked != null) {
      _map.fitBounds([LatLng(picked.latitude, picked.longitude)]);
      return;
    }
    final points = [
      for (final p in _mappable) LatLng(p.latitude, p.longitude),
    ];
    if (points.length > 1) _map.fitBounds(points, padding: 60);
  }

  void _find(String text) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return;
    for (final p in _mappable) {
      if (p.name.toLowerCase().contains(q)) {
        setState(() => _picked = p);
        _map.fitBounds([LatLng(p.latitude, p.longitude)]);
        FocusScope.of(context).unfocus();
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No place by that name.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = _mappable;
    final picked = _picked;
    final me = _me;
    final km = picked == null || me == null
        ? null
        : ExploreLocation.roadKm(me, picked.latitude, picked.longitude);
    final centre = places.isEmpty
        ? const LatLng(34.3700, 73.4711)
        : LatLng(places.first.latitude, places.first.longitude);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: UdMap(
              controller: _map,
              initialCenter: centre,
              zoom: 9,
              myLocation: me,
              padding: EdgeInsets.only(top: 70, bottom: picked == null ? 0 : 190),
              markers: [
                for (final p in places)
                  UdMarker(
                    id: p.id,
                    position: LatLng(p.latitude, p.longitude),
                    label: p.name,
                    hue: p.id == picked?.id
                        ? UdMarkerHue.brand
                        : UdMarkerHue.navy,
                    onTap: () => setState(() => _picked = p),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Back',
                      child: Material(
                        color: AppColors.background,
                        elevation: 3,
                        borderRadius: AppRadii.all(14),
                        child: InkWell(
                          onTap: () => Navigator.maybePop(context),
                          borderRadius: AppRadii.all(14),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(Icons.chevron_left_rounded,
                                size: 26, color: AppColors.navy),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Material(
                        color: AppColors.background,
                        elevation: 3,
                        borderRadius: AppRadii.all(14),
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              const Icon(Icons.search_rounded,
                                  size: 19, color: AppColors.navy),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _search,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: _find,
                                  style: AppType.small.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppText.primary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search a place',
                                    hintStyle: AppType.small.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppText.caption,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (picked != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Material(
                  color: AppColors.background,
                  elevation: 8,
                  borderRadius: AppRadii.all(22),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 76,
                              height: 76,
                              child: ExplorePhoto(
                                url: picked.coverImageUrl,
                                radius: 14,
                                iconSize: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    picked.name,
                                    style: AppType.listTitle.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppText.primary,
                                    ),
                                  ),
                                  Text(
                                    '${picked.district} · best ${picked.seasonShort}',
                                    style: AppType.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppText.secondary,
                                    ),
                                  ),
                                  if (km != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${ExploreLocation.kmLabel(km)} · '
                                      '~${(km / 35).toStringAsFixed(km / 35 < 10 ? 1 : 0)} h',
                                      style: AppType.small.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppText.primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _CardButton(
                                label: 'Details',
                                onTap: () => widget.onOpen(picked),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CardButton(
                                label: 'Go here',
                                lime: true,
                                onTap: () => exploreNavigate(
                                  context,
                                  picked.latitude,
                                  picked.longitude,
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
            ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.onTap,
    this.lime = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool lime;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: lime ? AppColors.brand : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(16),
        side: lime
            ? BorderSide.none
            : const BorderSide(color: AppColors.border, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              label,
              style: AppType.small.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
