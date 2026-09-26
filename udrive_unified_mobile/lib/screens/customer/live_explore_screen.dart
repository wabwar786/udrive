import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import 'live_packages_screen.dart';
import 'tourism_booking_screen.dart';

/// C-40 — Explore Kashmir.
///
/// A bottom-nav tab root. It used to carry its own `Scaffold` and a navy
/// `AppBar` with a back arrow and a Home button, which since the shell started
/// drawing a white bar for every tab meant **two bars stacked on one screen** —
/// and a back arrow on a tab root, which has nothing to go back to. The bar is
/// the shell's; this screen is just the page under it.
class LiveExploreScreen extends StatefulWidget {
  const LiveExploreScreen({super.key});

  @override
  State<LiveExploreScreen> createState() => _LiveExploreScreenState();
}

class _LiveExploreScreenState extends State<LiveExploreScreen> {
  late final ApiClient _api;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _busy = true;
  String? _error;
  int _tab = 0;

  bool get _urdu => AppControllerScope.of(context).locale.languageCode == 'ur';
  String _t(String en, String ur) => _urdu ? ur : en;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(SessionStore());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final controller = AppControllerScope.of(context);
      final language = controller.locale.languageCode;
      final results = await Future.wait([
        _api.getJson('/api/v1/catalog/destinations?language=$language',
            authenticated: false),
        controller.refreshPhase9Marketplace(),
      ]);
      final response = results.first as Map<String, dynamic>;
      final raw = response['data'] as List? ?? const [];
      _items =
          raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final q = _search.text.trim().toLowerCase();

    // The filters are untouched: destinations match on name, district, summary
    // and season; packages on title, both cities, driver and vehicle.
    final destinations = _items.where((e) {
      if (q.isEmpty) return true;
      return '${e['name']} ${e['district']} ${e['summary']} ${e['bestSeason']}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final packages = controller.liveMarketplacePackages.where((p) {
      if (q.isEmpty) return true;
      return '${p.title} ${p.startingCity} ${p.destination} ${p.driverName} ${p.vehicle}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final nothingLoaded =
        _items.isEmpty && controller.liveMarketplacePackages.isEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 0, AppSizes.sidePadding, 34),
        children: [
          UdHeroTitle(
            title: _t('Explore Kashmir', 'کشمیر کی سیر کریں'),
            subtitle: _t(
              'Discover verified destinations and book Admin-approved Driver '
                  'packages.',
              'تصدیق شدہ مقامات دیکھیں اور ایڈمن سے منظور شدہ ڈرائیور پیکیجز بک کریں۔',
            ),
            padding: const EdgeInsets.only(bottom: 18),
          ),
          UdTextField(
            controller: _search,
            hint: _t('Search destination or package', 'مقام یا پیکیج تلاش کریں'),
            icon: Icons.search_rounded,
            onChanged: (_) => setState(() {}),
            suffix: _search.text.isEmpty
                ? null
                : UdIconButton(
                    icon: Icons.close_rounded,
                    small: true,
                    variant: UdIconButtonVariant.soft,
                    tooltip: _t('Clear', 'صاف کریں'),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
          const SizedBox(height: 14),
          _SegmentedTabs(
            selected: _tab,
            destinationsCount: destinations.length,
            packagesCount: packages.length,
            onChanged: (value) => setState(() => _tab = value),
            destinationLabel: _t('Destinations', 'سیاحتی مقامات'),
            packageLabel: _t('Driver Packages', 'ڈرائیور پیکیجز'),
          ),
          const SizedBox(height: 20),
          if (_busy && nothingLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.navy),
              ),
            )
          else if (_error != null && nothingLoaded)
            UdBanner(
              tone: UdTone.err,
              icon: Icons.cloud_off_rounded,
              trailing: UdButton.outline(
                label: _t('Retry', 'دوبارہ کوشش کریں'),
                size: UdButtonSize.xs,
                expand: false,
                onPressed: _load,
              ),
              text: _t('Explore data could not be loaded.',
                  'ایکسپلور کا ڈیٹا لوڈ نہیں ہو سکا۔'),
            )
          else if (_tab == 0)
            _destinations(destinations)
          else
            _packages(packages),
        ],
      ),
    );
  }

  Widget _destinations(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return UdEmptyState(
        icon: Icons.landscape_outlined,
        title: _t('No destination found', 'کوئی مقام نہیں ملا'),
        text: _t(
          'Destinations added by Admin will appear here.',
          'ایڈمن کی طرف سے شامل کیے گئے مقامات یہاں نظر آئیں گے۔',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdSectionHeader(
          title: _t('Destinations', 'سیاحتی مقامات'),
          caption: _t('${items.length} verified spots',
              '${items.length} تصدیق شدہ مقامات'),
        ),
        const SizedBox(height: 14),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _DestinationCard(
              item: item,
              urdu: _urdu,
              onBook: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TourismBookingScreen(initialDestination: '${item['name']}'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _packages(List<LiveTourPackage> packages) {
    if (packages.isEmpty) {
      return UdEmptyState(
        icon: Icons.luggage_outlined,
        title: _t('No approved package yet', 'ابھی کوئی منظور شدہ پیکیج نہیں'),
        text: _t(
          'A Driver package appears here only after Admin approval and '
              'activation.',
          'ڈرائیور کا پیکیج ایڈمن کی منظوری اور فعال ہونے کے بعد یہاں نظر آئے گا۔',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdSectionHeader(
          title: _t('Driver Packages', 'ڈرائیور پیکیجز'),
          caption: _t('${packages.length} approved', '${packages.length} منظور شدہ'),
        ),
        const SizedBox(height: 14),
        for (final package in packages)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ExplorePackageCard(
              package: package,
              urdu: _urdu,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LivePackageDetailScreen(package: package),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Two tabs on a grey track, each carrying its own live count.
///
/// Not [UdSegmented]: that one takes plain labels, and the count pill is the
/// point here — it says how much is behind each tab before you switch.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.selected,
    required this.destinationsCount,
    required this.packagesCount,
    required this.onChanged,
    required this.destinationLabel,
    required this.packageLabel,
  });

  final int selected;
  final int destinationsCount;
  final int packagesCount;
  final ValueChanged<int> onChanged;
  final String destinationLabel;
  final String packageLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.all(AppRadii.field),
        ),
        child: Row(
          children: [
            Expanded(
              child: _TabButton(
                selected: selected == 0,
                icon: Icons.landscape_rounded,
                label: destinationLabel,
                count: destinationsCount,
                onTap: () => onChanged(0),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _TabButton(
                selected: selected == 1,
                icon: Icons.luggage_rounded,
                label: packageLabel,
                count: packagesCount,
                onTap: () => onChanged(1),
              ),
            ),
          ],
        ),
      );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints:
                const BoxConstraints(minHeight: AppSizes.buttonSmall),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.surfaceHigh : Colors.transparent,
              borderRadius: AppRadii.all(12),
              boxShadow: selected ? AppShadows.panel : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? AppColors.navy : AppText.secondary),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: AppType.buttonSm.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppText.primary : AppText.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brand : AppColors.surfaceAlt,
                    borderRadius: AppRadii.all(AppRadii.chip),
                  ),
                  child: Text(
                    '$count',
                    style: AppType.overline.copyWith(
                      letterSpacing: 0,
                      color: AppText.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A cover band with the district and the safety score on it, then the
/// destination and what it is like to get there.
class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.item,
    required this.urdu,
    required this.onBook,
  });

  final Map<String, dynamic> item;
  final bool urdu;
  final VoidCallback onBook;

  String _t(String en, String ur) => urdu ? ur : en;

  @override
  Widget build(BuildContext context) {
    final cover = item['coverImageUrl']?.toString();
    final name = '${item['name']}';
    final district = '${item['district'] ?? ''}'.trim();
    final season = '${item['bestSeason'] ?? ''}'.trim();
    final summary = '${item['summary'] ?? ''}'.trim();

    return UdCard(
      tone: UdCardTone.raised,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(url: cover, fallbackIcon: Icons.landscape_rounded),
                  if (district.isNotEmpty)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: UdMapChip(label: district),
                    ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: UdBadge(
                      label: _t(
                        '${item['routeSafetyScore'] ?? 0}/100 safety',
                        '${item['routeSafetyScore'] ?? 0}/100 حفاظت',
                      ),
                      tone: UdTone.lime,
                    ),
                  ),
                ],
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
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.location_on_rounded,
                            size: 19, color: AppColors.brandInk),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          name,
                          style: AppType.h3.copyWith(color: AppText.primary),
                        ),
                      ),
                      if (season.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            _t('Best: $season', 'بہترین: $season'),
                            style: AppType.small
                                .copyWith(color: AppText.secondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body2.copyWith(color: AppText.secondary),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        Icons.directions_car_rounded,
                        '${item['recommendedVehicle'] ?? _t('Any vehicle', 'کوئی بھی گاڑی')}',
                      ),
                      _InfoChip(
                        Icons.language_rounded,
                        '${item['networkStatus'] ?? _t('Unknown', 'نامعلوم')}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  UdButton.primary(
                    label: _t('Plan ride to $name', '$name کے لیے سفر بنائیں'),
                    size: UdButtonSize.small,
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: onBook,
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

/// A marketplace package, seen from Explore. Tapping it opens C-28.
class _ExplorePackageCard extends StatelessWidget {
  const _ExplorePackageCard({
    required this.package,
    required this.urdu,
    required this.onTap,
  });

  final LiveTourPackage package;
  final bool urdu;
  final VoidCallback onTap;

  String _t(String en, String ur) => urdu ? ur : en;

  @override
  Widget build(BuildContext context) {
    final tight = package.bookableSeats <= 2;

    return UdCard(
      tone: UdCardTone.raised,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(
                    url: package.coverImageUrl,
                    fallbackIcon: Icons.luggage_rounded,
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: UdBadge(
                      label: _t('${package.bookableSeats} seats free',
                          '${package.bookableSeats} نشستیں خالی'),
                      tone: tight ? UdTone.warn : UdTone.ok,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: AppRadii.all(AppRadii.tile),
                        boxShadow: AppShadows.floating,
                      ),
                      child: Text(
                        package.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 16,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.brandWash,
                      borderRadius: AppRadii.all(AppRadii.row),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route_rounded,
                            size: 17, color: AppColors.navy),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            package.startingCity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.small.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 16, color: AppColors.navy),
                        ),
                        Flexible(
                          child: Text(
                            package.destination,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.small.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${package.driverName} · ${package.vehicle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.small.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.verified_rounded,
                          size: 18, color: AppColors.brandInk),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 16, color: AppText.secondary),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          DateFormat('dd MMM · hh:mm a')
                              .format(package.departureAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.small.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _t('Per seat', 'فی نشست'),
                            style: AppType.caption
                                .copyWith(color: AppText.secondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PKR ${NumberFormat('#,###').format(package.pricePerSeat)}',
                            style: AppType.priceMd.copyWith(
                              fontSize: 18,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ],
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

/// A cover photo, or the map's own pale wash when there is none.
///
/// The fallback used to be a navy gradient — the last of the dark theme on
/// this screen — which on a white card read as a hole rather than a missing
/// photo.
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.fallbackIcon});

  final String? url;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final address = url?.trim();
    if (address == null || address.isEmpty) return _placeholder();
    return Image.network(
      ApiConfig.absoluteUrl(address),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTint.mapPark, AppTint.mapWater],
          ),
        ),
        child: Center(
          child: Icon(fallbackIcon, size: 52, color: AppColors.borderStrong),
        ),
      );
}

/// A small outlined fact: the vehicle that suits the road, the mobile signal.
class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(AppRadii.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppText.secondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppType.caption.copyWith(
                fontSize: 13.5,
                color: AppText.primary,
              ),
            ),
          ],
        ),
      );
}
