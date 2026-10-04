import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/explore/explore_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../customer/rental_list_screen.dart';
import '../customer/tour_vehicles_screen.dart';
import '../customer/udrive_route_flow_screen.dart';
import '../hotels/hotel_list_screen.dart';
import 'explore_bits.dart';
import 'explore_map_screen.dart';

/// One place: its photograph, the facts that decide a trip, how to get
/// there, and the four ways UDrive can take the customer — each opening the
/// part of the app that already does it, with this place filled in.
class ExplorePlaceScreen extends StatefulWidget {
  const ExplorePlaceScreen({
    required this.place,
    this.places = const [],
    super.key,
  });

  final ExplorePlace place;

  /// The whole catalogue, so "Close to …" can open its places too.
  final List<ExplorePlace> places;

  @override
  State<ExplorePlaceScreen> createState() => _ExplorePlaceScreenState();
}

class _ExplorePlaceScreenState extends State<ExplorePlaceScreen> {
  ExploreDetails? _details;
  bool _saved = false;
  LatLng? _me;
  bool _summaryOpen = false;
  bool _started = false;

  ExplorePlace get _place => widget.place;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final repo = ExploreRepository(AppControllerScope.of(context).apiClient);
    final saved = await ExploreRepository.saved();
    if (mounted) setState(() => _saved = saved.contains(_place.id));
    try {
      final details = await repo.details(_place.id);
      if (mounted) setState(() => _details = details);
    } catch (_) {
      // The place still shows from the catalogue row; only the extras wait.
    }
    final me = await ExploreLocation.get();
    if (mounted && me != null) setState(() => _me = me);
  }

  Future<void> _toggleSave() async {
    final saved = await ExploreRepository.toggleSaved(_place.id);
    if (!mounted) return;
    setState(() => _saved = saved.contains(_place.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_saved ? 'Saved to your places.' : 'Removed from saved.'),
    ));
  }

  double? get _km {
    final me = _me;
    if (me == null) return null;
    return ExploreLocation.roadKm(me, _place.latitude, _place.longitude);
  }

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  void _bookRide() => _push(
        UDriveRouteFlowScreen(
          serviceType: UDriveServiceType.tours,
          pickupLabel: 'Current location',
          pickupPoint: _me ?? const LatLng(34.3700, 73.4700),
          initialDestinationLabel: _place.name,
          initialDestinationLatitude: _place.latitude,
          initialDestinationLongitude: _place.longitude,
          skipRouteEntry: true,
        ),
      );

  void _openNearby(ExploreNearby near) {
    final matches = widget.places.where((p) => p.id == near.id);
    if (matches.isEmpty) return;
    final match = matches.first;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExplorePlaceScreen(place: match, places: widget.places),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final place = _place;
    final details = _details;
    final km = _km;
    final route = details?.route;
    final nameUr = details?.nameUr.trim() ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 360,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExplorePhoto(url: place.coverImageUrl, iconSize: 72),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 130,
                  child: ColoredBox(
                    color: AppColors.navy.withValues(alpha: .55),
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
                          _RoundButton(
                            icon: Icons.chevron_left_rounded,
                            label: 'Back',
                            onTap: () => Navigator.maybePop(context),
                          ),
                          const Spacer(),
                          _RoundButton(
                            icon: _saved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            label: _saved ? 'Remove from saved' : 'Save place',
                            onTap: _toggleSave,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (place.district.isNotEmpty)
                        Text(
                          '${place.district.toUpperCase()} DISTRICT',
                          style: AppType.caption.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppColors.brand,
                          ),
                        ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 12,
                        children: [
                          Text(
                            place.name,
                            style: AppType.display.copyWith(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.1,
                              height: 1.05,
                              color: AppText.onInk,
                            ),
                          ),
                          if (nameUr.isNotEmpty && nameUr != place.name)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                nameUr,
                                textDirection: TextDirection.rtl,
                                style: AppType.h3.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onInkMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.7,
                  children: [
                    _Fact(label: 'BEST TIME', value: place.seasonShort, lime: true),
                    _Fact(
                        label: 'ROAD SAFETY',
                        value: place.safetyScore > 0
                            ? '${place.safetyScore} / 100'
                            : '—'),
                    _Fact(
                        label: 'FAMILY',
                        value: place.familyScore > 0
                            ? '${place.familyScore} / 100'
                            : '—'),
                    _Fact(
                        label: 'VEHICLE',
                        value: place.recommendedVehicle.isEmpty
                            ? 'Any'
                            : place.recommendedVehicle),
                    _Fact(
                        label: 'SIGNAL',
                        value: place.networkStatus.isEmpty
                            ? '—'
                            : place.networkStatus),
                    _Fact(
                        label: 'FROM YOU',
                        value: km == null ? '—' : ExploreLocation.kmLabel(km)),
                  ],
                ),
                if (place.summary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _summaryOpen = !_summaryOpen),
                    child: Text(
                      place.summary,
                      maxLines: _summaryOpen ? null : 3,
                      overflow: _summaryOpen
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: AppType.body2.copyWith(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
                if (route != null) ...[
                  const SizedBox(height: 18),
                  _RouteCard(route: route, placeName: place.name),
                ],
                const SizedBox(height: 20),
                Text(
                  'How do you want to go?',
                  style: AppType.h3.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    _GoTile(
                      dark: true,
                      icon: Icons.terrain_rounded,
                      title: 'Join a tour',
                      subtitle: details == null
                          ? 'Tours going here'
                          : details.toursCount == 0
                              ? 'None listed yet'
                              : '${details.toursCount} going'
                                  '${details.nextDeparture == null ? '' : ' · next ${DateFormat('EEE d MMM').format(details.nextDeparture!)}'}',
                      onTap: () => _push(
                          TourVehiclesScreen(initialDestination: place.name)),
                    ),
                    _GoTile(
                      icon: Icons.directions_car_rounded,
                      title: place.needsFourByFour ? 'Rent a 4x4' : 'Rent a car',
                      subtitle: 'With driver or self drive',
                      onTap: () => _push(
                          RentalListScreen(fourByFour: place.needsFourByFour)),
                    ),
                    _GoTile(
                      icon: Icons.place_rounded,
                      title: 'Book a ride',
                      subtitle: 'Private car, you name a fare',
                      onTap: _bookRide,
                    ),
                    _GoTile(
                      icon: Icons.apartment_rounded,
                      title: 'Stay nearby',
                      subtitle: details == null
                          ? 'Hotels close by'
                          : details.hotelsNearby == 0
                              ? 'Search hotels'
                              : '${details.hotelsNearby} '
                                  '${details.hotelsNearby == 1 ? 'hotel' : 'hotels'} close by',
                      onTap: () => _push(HotelListScreen(
                        destination: place.district.isNotEmpty
                            ? place.district
                            : place.name,
                      )),
                    ),
                  ],
                ),
                if (details != null && details.nearby.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Close to ${place.name}',
                    style: AppType.h3.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: details.nearby.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final near = details.nearby[i];
                        return InkWell(
                          onTap: () => _openNearby(near),
                          borderRadius: AppRadii.all(16),
                          child: SizedBox(
                            width: 128,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 96,
                                  width: 128,
                                  child: ExplorePhoto(
                                    url: near.coverImageUrl,
                                    radius: 16,
                                    iconSize: 28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  near.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.small.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                                Text(
                                  ExploreLocation.kmLabel(near.distanceKm),
                                  style: AppType.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppText.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Material(
                  color: AppColors.brand,
                  borderRadius: AppRadii.all(18),
                  child: InkWell(
                    onTap: () => _push(ExploreMapScreen(
                      places: widget.places.isEmpty ? [place] : widget.places,
                      focusId: place.id,
                      onOpen: (p) {
                        Navigator.pop(context);
                        if (p.id != place.id) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExplorePlaceScreen(
                                  place: p, places: widget.places),
                            ),
                          );
                        }
                      },
                    )),
                    borderRadius: AppRadii.all(18),
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.map_rounded,
                              size: 21, color: AppColors.navy),
                          const SizedBox(width: 8),
                          Text(
                            'Show on map',
                            style: AppType.button.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
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
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.background,
        borderRadius: AppRadii.all(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 24, color: AppColors.navy),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.lime = false});

  final String label;
  final String value;
  final bool lime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: lime ? AppColors.brandWash : AppColors.surface,
        borderRadius: AppRadii.all(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: lime ? AppColors.brandInk : AppText.secondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.small.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.placeName});

  final ExploreRoute route;
  final String placeName;

  String get _time {
    final h = route.minutes ~/ 60;
    final m = route.minutes % 60;
    if (h == 0) return '~$m min drive';
    return m == 0 ? '~$h h drive' : '~$h h $m drive';
  }

  @override
  Widget build(BuildContext context) {
    final from = route.fromName?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Getting there',
                  style: AppType.listTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ),
              if (from.isNotEmpty)
                Text(
                  'from $from',
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.navy, width: 3),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 26,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.borderStrong,
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      from.isEmpty ? route.name : '$from · via ${route.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      placeName,
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '~${route.distanceKm.round()} km',
                    style: AppType.listTitle.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  Text(
                    _time,
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (route.fourByFour || route.daylightOnly) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (route.fourByFour) const ExploreTag(label: '4x4 needed', dark: true),
                if (route.daylightOnly)
                  const ExploreTag(label: 'Daylight driving only'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GoTile extends StatelessWidget {
  const _GoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dark = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? AppColors.navy : AppColors.surface,
      borderRadius: AppRadii.all(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dark ? AppColors.brand : AppColors.background,
                  borderRadius: AppRadii.all(12),
                ),
                child: Icon(icon, size: 20, color: AppColors.navy),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.listTitle.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: dark ? AppText.onInk : AppText.primary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dark ? AppColors.onInkMuted : AppText.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
