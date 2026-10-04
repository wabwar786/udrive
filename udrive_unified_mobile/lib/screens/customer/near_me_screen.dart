import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/businesses/business_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/demo_tag.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/business_models.dart';
import '../business_owner/business_owner_add_screen.dart';

/// Near me — local businesses around the customer, as one list.
///
/// Businesses list themselves (like hotel owners) and an admin approves them.
/// The screen is deliberately one page: no in-app map and no detail screen.
/// Every business carries one action, the location button, which opens the
/// phone's own Google Maps with directions — free for UDrive, and the app the
/// customer already trusts for the walk or the drive.
class NearMeScreen extends StatefulWidget {
  const NearMeScreen({super.key});

  @override
  State<NearMeScreen> createState() => _NearMeScreenState();
}

/// Towns the customer can browse from when location is off or they are
/// planning ahead. The same list the Tours "where from" sheet uses.
const List<(String, double, double)> _towns = [
  ('Muzaffarabad', 34.3700, 73.4711),
  ('Rawalakot', 33.8578, 73.7604),
  ('Bagh', 33.9810, 73.7760),
  ('Kotli', 33.5180, 73.9020),
  ('Mirpur', 33.1480, 73.7510),
  ('Bhimber', 32.9750, 74.0780),
  ('Athmuqam', 34.5740, 73.9080),
  ('Hattian Bala', 34.1680, 73.7440),
  ('Pallandri', 33.7120, 73.6860),
  ('Dhirkot', 34.0400, 73.5800),
  ('Kohala', 34.0950, 73.4950),
];

class _NearMeScreenState extends State<NearMeScreen> {
  final _query = TextEditingController();

  BusinessRepository? _repository;
  Timer? _searchDebounce;

  BusinessCategory? _category;
  double _radiusKm = AppConfig.nearMeDefaultRadiusKm;
  bool _openOnly = false;

  double _latitude = AppConfig.fallbackLatitude;
  double _longitude = AppConfig.fallbackLongitude;

  /// What the header says the list is around.
  String _place = 'Muzaffarabad';

  /// True when [_latitude]/[_longitude] are the phone's own fix, not a town.
  bool _located = false;

  bool _locating = false;
  bool _loading = true;
  String? _loadError;
  List<BusinessListing> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository ??=
        BusinessRepository(AppControllerScope.of(context).apiClient);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────── location

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
            setState(() {
              _latitude = position.latitude;
              _longitude = position.longitude;
              _place = 'Near ${_nearestTown(_latitude, _longitude)}';
              _located = true;
            });
          }
        }
      }
    } catch (_) {
      // Keep the town already shown; the list still loads around it.
    } finally {
      if (mounted) setState(() => _locating = false);
      await _load();
    }
  }

  static String _nearestTown(double latitude, double longitude) {
    var best = _towns.first.$1;
    var bestDistance = double.infinity;
    for (final town in _towns) {
      final distance =
          Geolocator.distanceBetween(latitude, longitude, town.$2, town.$3);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = town.$1;
      }
    }
    return best;
  }

  Future<void> _choosePlace() async {
    final choice = await showModalBottomSheet<(String, double, double)?>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Show places near',
              style: AppType.h2.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 12),
            _SheetRow(
              icon: Icons.my_location_rounded,
              label: 'My location',
              highlight: true,
              onTap: () => Navigator.pop(context, ('', 0.0, 0.0)),
            ),
            for (final town in _towns)
              _SheetRow(
                icon: Icons.location_city_rounded,
                label: town.$1,
                onTap: () => Navigator.pop(context, town),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.$1.isEmpty) {
      await _locate();
      return;
    }
    setState(() {
      _latitude = choice.$2;
      _longitude = choice.$3;
      _place = choice.$1;
      _located = false;
    });
    await _load();
  }

  // ─────────────────────────────────────────────────────────────── data

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final results = await repository.nearby(
        latitude: _latitude,
        longitude: _longitude,
        radiusKm: _radiusKm,
        category: _category,
        query: _query.text,
      );
      if (!mounted) return;
      setState(() => _items = results);
    } catch (error) {
      // A failure is not an empty neighbourhood: say so, with a retry.
      if (mounted) {
        setState(() => _loadError = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppConfig.searchDebounce, _load);
  }

  void _pickCategory(BusinessCategory? category) {
    if (_category == category) return;
    setState(() => _category = category);
    _load();
  }

  Future<void> _pickRadius() async {
    final radius = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How far?',
                style: AppType.h2.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 12),
              for (final value in AppConfig.nearMeRadiiKm)
                _SheetRow(
                  icon: Icons.straighten_rounded,
                  label: 'Within ${value.toStringAsFixed(0)} km',
                  highlight: value == _radiusKm,
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (radius == null || radius == _radiusKm || !mounted) return;
    setState(() => _radiusKm = radius);
    await _load();
  }

  void _widen() {
    final next = AppConfig.nearMeRadiiKm.firstWhere(
      (value) => value > _radiusKm,
      orElse: () => AppConfig.nearMeRadiiKm.last,
    );
    setState(() => _radiusKm = next);
    _load();
  }

  /// Opens directions in the phone's Google Maps app (or the browser when
  /// it is not installed). Nothing map-related runs inside UDrive.
  Future<void> _openInMaps(BusinessListing listing) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${listing.latitude},${listing.longitude}',
    );
    final opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Maps could not be opened.')),
      );
    }
  }

  List<BusinessListing> get _shown => _openOnly
      ? _items.where((item) => item.openNow == true).toList(growable: false)
      : _items;

  /// The nearest hospital, pharmacy and fuel station, for the strip at the
  /// top. Only on the unfiltered list, where all three kinds were fetched.
  List<(String, BusinessListing, Color, Color, Color)> get _closest {
    if (_category != null || _query.text.trim().isNotEmpty) return const [];
    BusinessListing? first(BusinessCategory category) {
      for (final item in _items) {
        if (item.category == category) return item;
      }
      return null;
    }

    final hospital = first(BusinessCategory.hospital);
    final pharmacy = first(BusinessCategory.medicalStore);
    final fuel = first(BusinessCategory.fuel);
    return [
      if (hospital != null)
        ('Hospital', hospital, AppTint.danger, AppTint.dangerBorder,
            AppTint.dangerText),
      if (pharmacy != null)
        ('Pharmacy', pharmacy, AppTint.info, AppTint.infoBorder,
            AppTint.infoText),
      if (fuel != null)
        ('Fuel', fuel, AppTint.warning, AppTint.warningBorder,
            AppTint.warningText),
    ];
  }

  // ─────────────────────────────────────────────────────────────── view

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final closest = _closest;
    final title = _category == null
        ? 'Around you'
        : '${_category!.shortLabel} nearby';

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            place: _locating ? 'Finding you…' : _place,
            located: _located,
            query: _query,
            onPlace: _choosePlace,
            onQueryChanged: _onQueryChanged,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  SizedBox(
                    height: 92,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      children: [
                        _CategoryTile(
                          label: 'All',
                          icon: Icons.apps_rounded,
                          selected: _category == null,
                          onTap: () => _pickCategory(null),
                        ),
                        for (final category in BusinessCategory.values) ...[
                          const SizedBox(width: 8),
                          _CategoryTile(
                            label: category.shortLabel,
                            icon: category.icon,
                            selected: _category == category,
                            onTap: () => _pickCategory(category),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'Open now',
                          dot: true,
                          selected: _openOnly,
                          onTap: () => setState(() => _openOnly = !_openOnly),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Within ${_radiusKm.toStringAsFixed(0)} km',
                          trailing: Icons.expand_more_rounded,
                          selected: false,
                          onTap: _pickRadius,
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.navy),
                      ),
                    )
                  else if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      child: UdBanner(
                        tone: UdTone.err,
                        icon: Icons.cloud_off_rounded,
                        text: 'Could not load what is nearby. $_loadError',
                        trailing: UdButton.outline(
                          label: 'Retry',
                          size: UdButtonSize.xs,
                          expand: false,
                          onPressed: _load,
                        ),
                      ),
                    )
                  else ...[
                    if (closest.isNotEmpty) ...[
                      const _SectionLabel('CLOSEST TO YOU'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            for (var i = 0; i < closest.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: _ClosestTile(
                                  label: closest[i].$1,
                                  distance: _distanceText(closest[i].$2),
                                  background: closest[i].$3,
                                  border: closest[i].$4,
                                  ink: closest[i].$5,
                                  onTap: () => _openInMaps(closest[i].$2),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppType.h2.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppText.primary,
                              ),
                            ),
                          ),
                          Text(
                            '${shown.length} '
                            '${shown.length == 1 ? 'place' : 'places'}',
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _EmptyCard(
                          radiusKm: _radiusKm,
                          openOnly: _openOnly,
                          onWiden: _radiusKm >= AppConfig.nearMeRadiiKm.last
                              ? null
                              : _widen,
                        ),
                      )
                    else
                      for (final item in shown)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: _BusinessCard(
                            listing: item,
                            distance: _distanceText(item),
                            onLocation: () => _openInMaps(item),
                          ),
                        ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _ListYourBusiness(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BusinessOwnerAddScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "350 m · 4 min walk" up close, "2.4 km · 6 min drive" further out.
  static String _distanceText(BusinessListing listing) {
    final km = listing.distanceKm;
    if (km == null) return '';
    if (km < 1.2) {
      final metres = ((km * 1000) / 10).round() * 10;
      final minutes = (km * 1.25 / 5 * 60).ceil().clamp(1, 99);
      return '${metres < 10 ? 10 : metres} m · $minutes min walk';
    }
    final minutes = (km * 1.4 / 30 * 60).ceil().clamp(1, 999);
    return '${km.toStringAsFixed(1)} km · $minutes min drive';
  }
}

// ───────────────────────────────────────────────────────────── pieces

class _Header extends StatelessWidget {
  const _Header({
    required this.place,
    required this.located,
    required this.query,
    required this.onPlace,
    required this.onQueryChanged,
  });

  final String place;
  final bool located;
  final TextEditingController query;
  final VoidCallback onPlace;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Near me',
            style: AppType.h2.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppText.onInk,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: 'Change where to look: $place',
              excludeSemantics: true,
              child: InkWell(
                onTap: onPlace,
                borderRadius: AppRadii.all(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        located
                            ? Icons.my_location_rounded
                            : Icons.place_rounded,
                        size: 15,
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        place,
                        style: AppType.small.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more_rounded,
                          size: 18, color: AppColors.brand),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadii.all(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 20, color: AppText.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: query,
                    onChanged: onQueryChanged,
                    textInputAction: TextInputAction.search,
                    style: AppType.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppText.primary,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Search food, pharmacy, ATM…',
                      hintStyle: AppType.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppText.caption,
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.navy : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(18),
          side: BorderSide(
            color: selected ? AppColors.navy : AppColors.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder:
              RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
          child: SizedBox(
            width: 70,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? AppColors.brand : AppText.primary,
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dot;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.brandWash : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(12),
          side: BorderSide(
            color: selected ? AppColors.limeLine : AppColors.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder:
              RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dot) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTint.successText,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: AppType.small.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 2),
                    Icon(trailing, size: 18, color: AppText.primary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: AppType.caption.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppText.secondary,
        ),
      ),
    );
  }
}

class _ClosestTile extends StatelessWidget {
  const _ClosestTile({
    required this.label,
    required this.distance,
    required this.background,
    required this.border,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final String distance;
  final Color background;
  final Color border;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final short = distance.split(' · ').first;
    return Semantics(
      button: true,
      label: 'Nearest $label, $short. Opens Google Maps.',
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(16),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder:
              RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
          child: SizedBox(
            height: 74,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: AppType.small.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  Text(
                    short,
                    maxLines: 1,
                    style: AppType.listTitle.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.listing,
    required this.distance,
    required this.onLocation,
  });

  final BusinessListing listing;
  final String distance;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) {
    final category = listing.category;
    final open = listing.openLabel;
    final kind = category?.label ?? 'Business';
    final sub = [kind, if (distance.isNotEmpty) distance].join(' · ');

    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        // The whole card does what its one button does.
        onTap: onLocation,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _Thumb(listing: listing),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listing.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        if (listing.isDemo) ...[
                          const SizedBox(width: 6),
                          const DemoTag(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppText.secondary,
                      ),
                    ),
                    if (open != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        open,
                        style: AppType.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: listing.open24Hours || listing.openNow == true
                              ? AppTint.successText
                              : AppTint.dangerText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Open ${listing.name} in Google Maps',
                excludeSemantics: true,
                child: Material(
                  color: AppColors.brand,
                  borderRadius: AppRadii.all(14),
                  child: InkWell(
                    onTap: onLocation,
                    borderRadius: AppRadii.all(14),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.near_me_rounded,
                          size: 22, color: AppColors.navy),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The owner's photo when there is one, else the category on its tint.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.listing});

  final BusinessListing listing;

  static (Color, Color) _tint(BusinessCategory? category) =>
      switch (category) {
        BusinessCategory.restaurant => (AppTint.warning, AppTint.warningText),
        BusinessCategory.grocery => (AppTint.success, AppTint.successText),
        BusinessCategory.medicalStore => (AppTint.info, AppTint.infoText),
        BusinessCategory.hospital => (AppTint.danger, AppTint.dangerText),
        BusinessCategory.bank => (AppTint.personalWash, AppTint.personal),
        BusinessCategory.fuel => (AppColors.surfaceAlt, AppText.primary),
        BusinessCategory.mosque => (AppColors.brandWash, AppColors.brandInk),
        null => (AppColors.surfaceAlt, AppText.primary),
      };

  @override
  Widget build(BuildContext context) {
    final (background, ink) = _tint(listing.category);
    final fallback = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(14),
      ),
      child: Icon(
        listing.category?.icon ?? Icons.storefront_rounded,
        size: 26,
        color: ink,
      ),
    );
    final photo = listing.photos.isEmpty
        ? ''
        : ApiConfig.absoluteUrl(listing.photos.first);
    if (photo.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: AppRadii.all(14),
      child: Image.network(
        photo,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.radiusKm,
    required this.openOnly,
    required this.onWiden,
  });

  final double radiusKm;
  final bool openOnly;
  final VoidCallback? onWiden;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openOnly
                ? 'Nothing open right now within '
                    '${radiusKm.toStringAsFixed(0)} km'
                : 'No listings within ${radiusKm.toStringAsFixed(0)} km yet',
            style: AppType.listTitle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Businesses here list themselves on UDrive. As they join, they '
            'show up in this list.',
            style: AppType.small.copyWith(
              height: 1.45,
              color: AppText.secondary,
            ),
          ),
          if (onWiden != null) ...[
            const SizedBox(height: 12),
            UdButton.outline(
              label: 'Look further',
              size: UdButtonSize.xs,
              expand: false,
              onPressed: onWiden,
            ),
          ],
        ],
      ),
    );
  }
}

class _ListYourBusiness extends StatelessWidget {
  const _ListYourBusiness({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadii.all(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Own a shop or restaurant?',
                  style: AppType.listTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppText.onInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'List it free. Customers nearby will find you.',
                  style: AppType.small.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppText.onInkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: AppColors.brand,
            borderRadius: AppRadii.all(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadii.all(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text(
                  'List it',
                  style: AppType.small.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
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

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: highlight ? AppColors.brandInk : AppText.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppType.body.copyWith(
                  fontSize: 15,
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  color: AppText.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
