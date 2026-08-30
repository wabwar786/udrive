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
import '../../models/business_models.dart';
import '../business_owner/business_owner_add_screen.dart';

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
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
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
    return Container(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 26),
          children: [
            SizedBox(
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
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: GestureDetector(
                      onTap: _locate,
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.floating,
                        ),
                        child: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded,
                                size: 19, color: AppColors.navy),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _SearchField(
                controller: _query,
                onChanged: _onQueryChanged,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: _category == null,
                    onTap: () {
                      setState(() => _category = null);
                      _load();
                    },
                  ),
                  ...BusinessCategory.values.map(
                    (category) => _CategoryChip(
                      label: category.label,
                      selected: _category == category,
                      onTap: () {
                        setState(() => _category = category);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ...AppConfig.nearMeRadiiKm.map(
                    (radius) => Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _RadiusChip(
                        label: '${radius.toStringAsFixed(0)} km',
                        selected: _radiusKm == radius,
                        onTap: () {
                          setState(() => _radiusKm = radius);
                          _load();
                        },
                      ),
                    ),
                  ),
                  const Spacer(),
                  _SortToggle(
                    sort: _sort,
                    onChanged: (value) {
                      setState(() => _sort = value);
                      _load();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _EmptyState(
                  radiusKm: _radiusKm,
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
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
                  child: _ListingCard(
                    listing: item,
                    onCall: () => _call(item),
                    onDirections: () => _directions(item),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.row),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 19, color: AppText.secondary),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppText.primary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                hintText: 'Search near me',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppText.disabled,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTint.brand : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.secondary : AppColors.border,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.navy : AppText.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppText.secondary,
          ),
        ),
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.sort, required this.onChanged});

  final _NearMeSort sort;
  final ValueChanged<_NearMeSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final byRating = sort == _NearMeSort.rating;
    return GestureDetector(
      onTap: () => onChanged(
        byRating ? _NearMeSort.distance : _NearMeSort.rating,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            byRating ? Icons.star_rounded : Icons.near_me_rounded,
            size: 15,
            color: AppText.secondary,
          ),
          const SizedBox(width: 5),
          Text(
            byRating ? 'Top rated' : 'Nearest',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppText.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (listing.photos.isNotEmpty)
            SizedBox(
              height: 130,
              child: Image.network(
                listing.photos.first,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: AppTint.surface,
                  child: Icon(Icons.storefront_rounded,
                      size: 30, color: AppText.disabled),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
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
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                    if (listing.rating != null) ...[
                      const Icon(Icons.star_rounded,
                          size: 15, color: Color(0xFFF5B942)),
                      const SizedBox(width: 3),
                      Text(
                        listing.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (listing.category != null) listing.category!.label,
                    if (listing.distanceKm != null)
                      '${listing.distanceKm!.toStringAsFixed(1)} km',
                  ].join('  ·  '),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppText.secondary),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (listing.openNow != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: listing.openNow!
                              ? AppTint.success
                              : AppTint.danger,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          listing.openNow! ? 'Open now' : 'Closed',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: listing.openNow!
                                ? AppTint.successText
                                : AppColors.danger,
                          ),
                        ),
                      ),
                    if (listing.address.isNotEmpty) ...[
                      if (listing.openNow != null) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          listing.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppText.secondary),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDirections,
                        icon: const Icon(Icons.directions_rounded, size: 17),
                        label: const Text('Directions'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                        ),
                      ),
                    ),
                    if (listing.phone != null && listing.phone!.isNotEmpty) ...[
                      const SizedBox(width: 9),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCall,
                          icon: const Icon(Icons.call_rounded, size: 17),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.storefront_outlined,
              size: 32, color: AppText.disabled),
          const SizedBox(height: 12),
          Text(
            'No listings within ${radiusKm.toStringAsFixed(0)} km yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Local businesses list themselves on UDrive. As shops in this area '
            'register, they will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5, height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 16),
          if (onWiden != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onWiden,
                child: const Text('Widen the search radius'),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onListBusiness,
              child: const Text(
                'List your business',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
