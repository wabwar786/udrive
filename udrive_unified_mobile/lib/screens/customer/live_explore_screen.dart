import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/explore/explore_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../explore/explore_bits.dart';
import '../explore/explore_map_screen.dart';
import '../explore/explore_place_screen.dart';
import '../hotels/hotel_list_screen.dart';
import 'rental_list_screen.dart';
import 'tour_vehicles_screen.dart';

/// Explore Kashmir — read like a travel magazine.
///
/// A big photograph of a place that is in season right now, districts to
/// narrow by, what is close to the customer, then every place. Everything on
/// it comes from the destination catalogue the admin keeps in the portal.
class LiveExploreScreen extends StatefulWidget {
  const LiveExploreScreen({super.key});

  @override
  State<LiveExploreScreen> createState() => _LiveExploreScreenState();
}

class _LiveExploreScreenState extends State<LiveExploreScreen> {
  List<ExplorePlace> _places = const [];
  Set<String> _saved = const {};
  LatLng? _me;
  bool _busy = true;
  String? _error;
  bool _started = false;

  /// Selected district, '★' for saved, or null for All.
  String? _district;
  final PageController _hero = PageController();
  int _heroIndex = 0;

  static const _savedKey = '★';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _hero.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = AppControllerScope.of(context);
    try {
      final places = await ExploreRepository(controller.apiClient)
          .places(language: controller.locale.languageCode);
      final saved = await ExploreRepository.saved();
      if (!mounted) return;
      setState(() {
        _places = places;
        _saved = saved;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Places could not be loaded. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Distances are a nicety: the screen does not wait for them.
    final me = await ExploreLocation.get();
    if (mounted && me != null) setState(() => _me = me);
  }

  double? _km(ExplorePlace p) {
    final me = _me;
    if (me == null || (p.latitude == 0 && p.longitude == 0)) return null;
    return ExploreLocation.roadKm(me, p.latitude, p.longitude);
  }

  List<ExplorePlace> get _featured {
    final month = DateTime.now().month;
    final inSeason = _places.where((p) => p.inSeason(month)).toList()
      ..sort((a, b) => b.familyScore.compareTo(a.familyScore));
    final pool = inSeason.isEmpty ? [..._places] : inSeason;
    return pool.take(3).toList(growable: false);
  }

  List<String> get _districts {
    final seen = <String>{};
    final out = <String>[];
    for (final p in _places) {
      final d = p.district;
      if (d.isEmpty || !seen.add(d.toLowerCase())) continue;
      out.add(d);
    }
    return out;
  }

  List<ExplorePlace> get _filtered => _places.where((p) {
        final d = _district;
        if (d == null) return true;
        if (d == _savedKey) return _saved.contains(p.id);
        return p.district.toLowerCase() == d.toLowerCase();
      }).toList(growable: false);

  List<ExplorePlace> get _nearOrPopular {
    final list = [..._places];
    if (_me != null) {
      list.sort((a, b) =>
          (_km(a) ?? double.infinity).compareTo(_km(b) ?? double.infinity));
    } else {
      list.sort((a, b) => b.familyScore.compareTo(a.familyScore));
    }
    return list.take(6).toList(growable: false);
  }

  Future<void> _open(ExplorePlace place) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExplorePlaceScreen(place: place, places: _places),
      ),
    );
    final saved = await ExploreRepository.saved();
    if (mounted) setState(() => _saved = saved);
  }

  void _openMap() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExploreMapScreen(places: _places, onOpen: _open),
        ),
      );

  Future<void> _search() async {
    final picked = await showModalBottomSheet<ExplorePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(places: _places),
    );
    if (picked != null && mounted) await _open(picked);
  }

  Future<void> _planTrip() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _PlanSheet(onPick: (v) => Navigator.pop(sheet, v)),
    );
    if (!mounted || choice == null) return;
    final Widget screen = switch (choice) {
      'tour' => const TourVehiclesScreen(),
      'rent' => const RentalListScreen(),
      _ => const HotelListScreen(),
    };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _places.isEmpty) {
      return const ColoredBox(
        color: AppColors.background,
        child: Center(child: CircularProgressIndicator(color: AppColors.navy)),
      );
    }
    if (_error != null && _places.isEmpty) {
      return ColoredBox(
        color: AppColors.background,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 40),
          children: [
            UdEmptyState(
              icon: Icons.cloud_off_rounded,
              tone: UdTone.err,
              title: 'Could not load places',
              text: _error,
              action: UdButton.outline(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: _load,
              ),
            ),
          ],
        ),
      );
    }

    final featured = _featured;
    final filtered = _filtered;
    final near = _nearOrPopular;
    final districts = _districts;
    final selected = _district;

    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            color: AppColors.navy,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 110),
              children: [
                if (featured.isNotEmpty)
                  SizedBox(
                    height: 430,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: _hero,
                          itemCount: featured.length,
                          onPageChanged: (i) => setState(() => _heroIndex = i),
                          itemBuilder: (context, i) => _HeroPage(
                            place: featured[i],
                            km: _km(featured[i]),
                            onTap: () => _open(featured[i]),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 0,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'DISCOVER KASHMIR',
                                          style: AppType.caption.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.4,
                                            color: AppColors.brand,
                                          ),
                                        ),
                                        Text(
                                          'Good to visit this month',
                                          style: AppType.small.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: AppText.onInk,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Semantics(
                                    button: true,
                                    label: 'Search places',
                                    child: Material(
                                      color: AppColors.background,
                                      borderRadius: AppRadii.all(14),
                                      child: InkWell(
                                        onTap: _search,
                                        borderRadius: AppRadii.all(14),
                                        child: const SizedBox(
                                          width: 44,
                                          height: 44,
                                          child: Icon(Icons.search_rounded,
                                              size: 22, color: AppColors.navy),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (featured.length > 1)
                          Positioned(
                            right: 18,
                            bottom: 26,
                            child: Row(
                              children: [
                                for (var i = 0; i < featured.length; i++)
                                  Container(
                                    margin: const EdgeInsets.only(left: 5),
                                    width: i == _heroIndex ? 18 : 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: i == _heroIndex
                                          ? AppColors.brand
                                          : AppColors.onInkMuted,
                                      borderRadius: AppRadii.all(3),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                // Districts
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                    children: [
                      _Pill(
                        label: 'All',
                        selected: selected == null,
                        onTap: () => setState(() => _district = null),
                      ),
                      if (_saved.isNotEmpty)
                        _Pill(
                          label: 'Saved',
                          icon: Icons.bookmark_rounded,
                          selected: selected == _savedKey,
                          onTap: () => setState(() => _district = _savedKey),
                        ),
                      for (final d in districts)
                        _Pill(
                          label: d,
                          selected: selected == d,
                          onTap: () => setState(() => _district = d),
                        ),
                    ],
                  ),
                ),

                _SectionTitle(
                  title: _me == null ? 'Popular' : 'Near you',
                  action: 'See on map',
                  onAction: _openMap,
                ),
                SizedBox(
                  height: 252,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: near.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => _TallCard(
                      place: near[i],
                      km: _km(near[i]),
                      onTap: () => _open(near[i]),
                    ),
                  ),
                ),

                _SectionTitle(
                  title: selected == null
                      ? 'All places'
                      : selected == _savedKey
                          ? 'Saved'
                          : selected,
                  trailing: '${filtered.length} '
                      '${filtered.length == 1 ? 'place' : 'places'}',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (final place in filtered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PlaceRow(
                            place: place,
                            onTap: () => _open(place),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _PlanBar(onPlan: _planTrip, onMap: _openMap),
          ),
        ],
      ),
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.place, required this.km, required this.onTap});

  final ExplorePlace place;
  final double? km;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final facts = [
      if (km != null) '${ExploreLocation.kmLabel(km!)} from you',
      if (place.needsFourByFour) '4x4 needed',
    ];
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExplorePhoto(url: place.coverImageUrl, iconSize: 72),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 190,
            child: ColoredBox(
              color: AppColors.navy.withValues(alpha: .55),
            ),
          ),
          Positioned(
            left: 18,
            right: 60,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    _HeroChip(
                        label: 'Best: ${place.seasonShort}', lime: true),
                    if (place.district.isNotEmpty)
                      _HeroChip(label: '${place.district} district'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.display.copyWith(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    height: 1.02,
                    color: AppText.onInk,
                  ),
                ),
                if (place.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    place.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.small.copyWith(
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onInkMuted,
                    ),
                  ),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    facts.join('  ·  '),
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppText.onInk,
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
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, this.lime = false});

  final String label;
  final bool lime;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lime ? AppColors.brand : AppColors.navy.withValues(alpha: .6),
        borderRadius: AppRadii.all(8),
      ),
      child: Text(
        label,
        style: AppType.caption.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: lime ? AppColors.navy : AppText.onInk,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.navy : AppColors.background,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.navy : AppColors.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: selected ? AppColors.brand : AppColors.navy),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: AppType.small.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppText.onInk : AppText.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppType.h3.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppText.primary,
              ),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action!,
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandInk,
                ),
              ),
            ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                trailing!,
                style: AppType.small.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppText.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TallCard extends StatelessWidget {
  const _TallCard({required this.place, required this.km, required this.onTap});

  final ExplorePlace place;
  final double? km;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(20),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExplorePhoto(url: place.coverImageUrl, radius: 20),
                  if (km != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: AppRadii.all(8),
                        ),
                        child: Text(
                          ExploreLocation.kmLabel(km!),
                          style: AppType.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.listTitle.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
            Text(
              place.district,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppText.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onTap});

  final ExplorePlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tags = exploreTags(
      fourByFour: place.needsFourByFour,
      weakSignal: place.weakSignal,
      familyScore: place.familyScore,
    );
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: ExplorePhoto(
                    url: place.coverImageUrl, radius: 14, iconSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    Text(
                      '${place.district} · best ${place.seasonShort}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppText.secondary,
                      ),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final t in tags) ExploreTag(label: t),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBar extends StatelessWidget {
  const _PlanBar({required this.onPlan, required this.onMap});

  final VoidCallback onPlan;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navy,
      elevation: 8,
      shadowColor: AppColors.navy.withValues(alpha: .4),
      borderRadius: AppRadii.all(20),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPlan,
                borderRadius: AppRadii.all(20),
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan a trip',
                        style: AppType.listTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppText.onInk,
                        ),
                      ),
                      Text(
                        'Tour · car rental · hotel',
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: AppColors.brand,
                borderRadius: AppRadii.all(14),
                child: InkWell(
                  onTap: onMap,
                  borderRadius: AppRadii.all(14),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.map_rounded,
                            size: 17, color: AppColors.navy),
                        const SizedBox(width: 6),
                        Text(
                          'Map',
                          style: AppType.small.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    Widget row(String id, IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: AppColors.surface,
            borderRadius: AppRadii.all(16),
            child: InkWell(
              onTap: () => onPick(id),
              borderRadius: AppRadii.all(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: AppRadii.all(12),
                      ),
                      child: Icon(icon, size: 21, color: AppColors.navy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: AppType.listTitle.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppText.primary,
                              )),
                          Text(sub,
                              style: AppType.caption.copyWith(
                                color: AppText.secondary,
                              )),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.navy),
                  ],
                ),
              ),
            ),
          ),
        );

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plan a trip',
              style: AppType.h3.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 14),
            row('tour', Icons.terrain_rounded, 'Join a tour',
                'Seats or a whole vehicle'),
            row('rent', Icons.directions_car_rounded, 'Rent a car',
                'With driver or self drive'),
            row('hotel', Icons.apartment_rounded, 'Find a hotel',
                'Rooms for your dates'),
          ],
        ),
      ),
    );
  }
}

/// Type a name, pick a place.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.places});

  final List<ExplorePlace> places;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _text.text.trim().toLowerCase();
    final hits = widget.places
        .where((p) =>
            q.isEmpty ||
            '${p.name} ${p.district} ${p.summary}'.toLowerCase().contains(q))
        .toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * .8,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.all(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: AppType.body2.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search a place',
                        hintStyle: AppType.body2.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppText.caption,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: hits.length,
                itemBuilder: (context, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 48,
                    height: 48,
                    child: ExplorePhoto(
                      url: hits[i].coverImageUrl,
                      radius: 12,
                      iconSize: 20,
                    ),
                  ),
                  title: Text(
                    hits[i].name,
                    style: AppType.listTitle.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  subtitle: Text(
                    hits[i].district,
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                  onTap: () => Navigator.pop(context, hits[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
