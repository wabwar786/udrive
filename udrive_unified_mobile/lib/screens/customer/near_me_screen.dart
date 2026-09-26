import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/businesses/business_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/maps/ud_map.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/business_models.dart';
import '../business_owner/business_owner_add_screen.dart';
import '../../core/permissions/location_access.dart';

/// Browses nearby third-party listings — restaurants, grocery, medical stores
/// and so on — sourced from UDrive's own business directory.
///
/// Businesses register themselves the same way hotel owners do, so the data is
/// ours rather than a third-party POI feed. Until a given area has listings the
/// screen shows an honest empty state with a route into registration.
class NearMeScreen extends StatefulWidget {
  const NearMeScreen({super.key});

  @override
  State<NearMeScreen> createState() => _NearMeScreenState();
}

enum _NearMeSort { distance, rating }

class _NearMeScreenState extends State<NearMeScreen> {
  final _query = TextEditingController();
  final _mapController = UdMapController();

  BusinessRepository? _repository;
  Timer? _searchDebounce;

  BusinessCategory? _category;
  double _radiusKm = AppConfig.nearMeDefaultRadiusKm;
  _NearMeSort _sort = _NearMeSort.distance;

  LatLng _center =
      const LatLng(AppConfig.fallbackLatitude, AppConfig.fallbackLongitude);
  bool _loading = true;
  bool _locating = false;
  List<BusinessListing> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository ??= BusinessRepository(AppControllerScope.of(context).apiClient);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        // Disclosure before the prompt — see LocationAccess.
        final permission =
            await LocationAccess.ensure(context, LocationPurpose.customer);
        if (LocationAccess.granted(permission)) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
          if (mounted) {
            setState(
              () => _center = LatLng(position.latitude, position.longitude),
            );
            await _mapController.moveTo(_center, zoom: 14);
          }
        }
      }
    } catch (_) {
      // Fall back to the last known centre; the list still loads.
    } finally {
      if (mounted) setState(() => _locating = false);
      await _load();
    }
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await repository.nearby(
        latitude: _center.latitude,
        longitude: _center.longitude,
        radiusKm: _radiusKm,
        category: _category,
        query: _query.text,
        sort: _sort == _NearMeSort.rating ? 'rating' : 'distance',
      );
      if (!mounted) return;
      setState(() => _items = results);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppConfig.searchDebounce, _load);
  }

  Future<void> _call(BusinessListing listing) async {
    final phone = listing.phone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer.')),
      );
    }
  }

  Future<void> _directions(BusinessListing listing) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${listing.latitude},${listing.longitude}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open directions.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 34),
          children: [
            _mapBand(),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.sidePadding),
              child: UdSectionHeader(
                title: 'Near me',
                caption: 'Local businesses around you',
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSizes.sidePadding),
              child: UdTextField(
                controller: _query,
                hint: 'Search near me',
                icon: Icons.search_rounded,
                onChanged: _onQueryChanged,
              ),
            ),
            const SizedBox(height: 16),
            // A wrapping row, not a horizontal scroller. Seven categories on
            // a rail meant four of them were off-screen with nothing to say
            // so; wrapped, the whole filter is visible at once.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSizes.sidePadding),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  UdChip(
                    label: 'All',
                    selected: _category == null,
                    onTap: () {
                      setState(() => _category = null);
                      _load();
                    },
                  ),
                  for (final category in BusinessCategory.values)
                    UdChip(
                      label: category.label,
                      icon: category.icon,
                      selected: _category == category,
                      onTap: () {
                        setState(() => _category = category);
                        _load();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSizes.sidePadding),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final radius in AppConfig.nearMeRadiiKm)
                    _RadiusChip(
                      label: '${radius.toStringAsFixed(0)} km',
                      selected: _radiusKm == radius,
                      onTap: () {
                        setState(() => _radiusKm = radius);
                        _load();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSizes.sidePadding),
              child: _SortRow(
                sort: _sort,
                onChanged: (value) {
                  setState(() => _sort = value);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.navy),
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sidePadding),
                child: _EmptyState(
                  radiusKm: _radiusKm,
                  // Hidden once the radius is already the widest step — the
                  // button had nothing left to widen to.
                  onWiden: _radiusKm >= AppConfig.nearMeRadiiKm.last
                      ? null
                      : () {
                          final next = AppConfig.nearMeRadiiKm.firstWhere(
                            (value) => value > _radiusKm,
                            orElse: () => AppConfig.nearMeRadiiKm.last,
                          );
                          setState(() => _radiusKm = next);
                          _load();
                        },
                  onListBusiness: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BusinessOwnerAddScreen(),
                    ),
                  ),
                ),
              )
            else
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.sidePadding, 0, AppSizes.sidePadding, 14),
                  child: _ListingCard(
                    listing: item,
                    onCall: () => _call(item),
                    onDirections: () => _directions(item),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// The map is the first thing on the screen — no bar above it, the same
  /// pattern Home uses.
  Widget _mapBand() => SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            UdMap(
              controller: _mapController,
              initialCenter: _center,
              zoom: 14,
              markers: _items
                  .map(
                    (item) => UdMarker(
                      id: item.id,
                      position: LatLng(item.latitude, item.longitude),
                      label: item.name,
                    ),
                  )
                  .toList(growable: false),
            ),
            const Positioned(
              left: 16,
              top: 16,
              child: UdMapChip(label: 'You are here'),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: _locating
                  // The float button has no busy state, so while a fix is
                  // being taken the same 46px square holds a spinner.
                  ? Container(
                      width: AppSizes.iconButton,
                      height: AppSizes.iconButton,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: AppRadii.all(15),
                        boxShadow: AppShadows.floating,
                      ),
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.navy,
                        ),
                      ),
                    )
                  : UdIconButton(
                      icon: Icons.my_location_rounded,
                      variant: UdIconButtonVariant.float,
                      tooltip: 'Recentre map',
                      onPressed: _locate,
                    ),
            ),
          ],
        ),
      );
}

/// A distance step. Navy when it is the one in force.
class _RadiusChip extends StatelessWidget {
  const _RadiusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(AppRadii.chip),
          child: Container(
            height: AppSizes.buttonXs,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected ? AppColors.navy : AppColors.background,
              borderRadius: AppRadii.all(AppRadii.chip),
              border: Border.all(
                color: selected ? AppColors.navy : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: AppType.buttonSm.copyWith(
                fontSize: 14,
                color: selected ? AppText.onInk : AppText.primary,
              ),
            ),
          ),
        ),
      );
}

/// The order in force on the left, the other one as a link on the right.
///
/// The toggle this replaces showed only the current state, so "Nearest" had
/// to be read as both a label and a button — and tapping it silently reordered
/// the list with nothing to say it would.
class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onChanged});

  final _NearMeSort sort;
  final ValueChanged<_NearMeSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final byRating = sort == _NearMeSort.rating;
    return Row(
      children: [
        Icon(
          byRating ? Icons.star_rounded : Icons.explore_rounded,
          size: 18,
          color: AppText.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            byRating ? 'Sorted by rating' : 'Sorted by nearest',
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(
            byRating ? _NearMeSort.distance : _NearMeSort.rating,
          ),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  byRating ? Icons.near_me_rounded : Icons.star_outline_rounded,
                  size: 18,
                  color: AppColors.brandInk,
                ),
                const SizedBox(width: 6),
                Text(
                  byRating ? 'Nearest' : 'Top rated',
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One nearby business.
class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.onCall,
    required this.onDirections,
  });

  final BusinessListing listing;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final hasPhone = (listing.phone ?? '').isNotEmpty;
    final meta = [
      if (listing.category != null) listing.category!.label,
      if (listing.distanceKm != null)
        '${listing.distanceKm!.toStringAsFixed(1)} km',
    ].join(' · ');

    return UdCard(
      tone: UdCardTone.raised,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (listing.photos.isNotEmpty)
              SizedBox(
                height: 130,
                child: Image.network(
                  listing.photos.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _PhotoFallback(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          listing.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.h3.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                      if (listing.rating != null) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.star_rounded,
                            size: 18, color: AppTint.star),
                        const SizedBox(width: 3),
                        Text(
                          listing.rating!.toStringAsFixed(1),
                          style: AppType.listTitle.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppText.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                  if (listing.openNow != null || listing.address.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (listing.openNow != null) ...[
                          UdBadge(
                            label: listing.openNow! ? 'Open now' : 'Closed',
                            tone: listing.openNow! ? UdTone.ok : UdTone.err,
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (listing.address.isNotEmpty)
                          Expanded(
                            child: Text(
                              listing.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.small
                                  .copyWith(color: AppText.secondary),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  UdButtonRow(
                    children: [
                      UdButton.outline(
                        label: 'Directions',
                        icon: Icons.route_rounded,
                        size: UdButtonSize.small,
                        onPressed: onDirections,
                      ),
                      // Only when there is a number to ring — unchanged.
                      if (hasPhone)
                        UdButton.outline(
                          label: 'Call',
                          icon: Icons.call_rounded,
                          size: UdButtonSize.small,
                          onPressed: onCall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTint.mapPark, AppTint.mapWater],
          ),
        ),
        child: Center(
          child: Icon(Icons.storefront_rounded,
              size: 40, color: AppColors.borderStrong),
        ),
      );
}

/// Nothing within the chosen radius — with the two things worth doing next.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.radiusKm,
    required this.onWiden,
    required this.onListBusiness,
  });

  final double radiusKm;
  final VoidCallback? onWiden;
  final VoidCallback onListBusiness;

  @override
  // A white card, not the grey one: the empty state's icon tile is grey, and
  // on a grey card it disappears into it.
  Widget build(BuildContext context) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UdEmptyState(
              icon: Icons.storefront_rounded,
              title: 'No listings within ${radiusKm.toStringAsFixed(0)} km yet',
              text: 'Local businesses list themselves on UDrive. As shops in '
                  'this area register, they will appear here.',
            ),
            if (onWiden != null) ...[
              UdButton.outline(
                label: 'Widen the search radius',
                icon: Icons.zoom_out_map_rounded,
                onPressed: onWiden,
              ),
              const SizedBox(height: 10),
            ],
            UdButton.ghost(
              label: 'List your business',
              onPressed: onListBusiness,
            ),
          ],
        ),
      );
}
