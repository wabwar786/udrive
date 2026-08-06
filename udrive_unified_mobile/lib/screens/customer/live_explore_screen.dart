import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import 'live_packages_screen.dart';
import 'tourism_booking_screen.dart';

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
    if (mounted) setState(() { _busy = true; _error = null; });
    try {
      final controller = AppControllerScope.of(context);
      final language = controller.locale.languageCode;
      final results = await Future.wait([
        _api.getJson('/api/v1/catalog/destinations?language=$language', authenticated: false),
        controller.refreshPhase9Marketplace(),
      ]);
      final response = results.first as Map<String, dynamic>;
      final raw = response['data'] as List? ?? const [];
      _items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final q = _search.text.trim().toLowerCase();
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

    return Scaffold(
      backgroundColor: const Color(0xFF111311),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111311),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(_t('Explore Kashmir', 'کشمیر کی سیر کریں'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _Hero(
            title: _t('Explore Kashmir', 'کشمیر کی سیر کریں'),
            subtitle: _t(
              'Discover verified destinations and book Admin-approved Driver packages.',
              'تصدیق شدہ مقامات دیکھیں اور ایڈمن سے منظور شدہ ڈرائیور پیکیجز بک کریں۔',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _t('Search destination or package', 'مقام یا پیکیج تلاش کریں'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: _t('Clear', 'صاف کریں'),
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _SegmentedTabs(
            selected: _tab,
            destinationsCount: destinations.length,
            packagesCount: packages.length,
            onChanged: (value) => setState(() => _tab = value),
            destinationLabel: _t('Destinations', 'سیاحتی مقامات'),
            packageLabel: _t('Driver Packages', 'ڈرائیور پیکیجز'),
          ),
          const SizedBox(height: 16),
          if (_busy && _items.isEmpty && controller.liveMarketplacePackages.isEmpty)
            const Padding(
              padding: EdgeInsets.all(56),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _items.isEmpty && controller.liveMarketplacePackages.isEmpty)
            PremiumCard(
              child: Column(
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.muted),
                  const SizedBox(height: 10),
                  Text(_t('Explore data could not be loaded.', 'ایکسپلور کا ڈیٹا لوڈ نہیں ہو سکا۔')),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_t('Retry', 'دوبارہ کوشش کریں')),
                  ),
                ],
              ),
            ),
          if (!_busy || _items.isNotEmpty || controller.liveMarketplacePackages.isNotEmpty)
            if (_tab == 0)
              _buildDestinations(destinations)
            else
              _buildPackages(packages),
        ],
      ),
      ),
    );
  }

  Widget _buildDestinations(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return _EmptyState(
        icon: Icons.landscape_outlined,
        title: _t('No destination found', 'کوئی مقام نہیں ملا'),
        copy: _t(
          'Destinations added by Admin will appear here.',
          'ایڈمن کی طرف سے شامل کیے گئے مقامات یہاں نظر آئیں گے۔',
        ),
      );
    }

    return Column(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _DestinationCard(
          item: item,
          urdu: _urdu,
          onBook: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TourismBookingScreen(initialDestination: '${item['name']}'),
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildPackages(List<LiveTourPackage> packages) {
    if (packages.isEmpty) {
      return _EmptyState(
        icon: Icons.luggage_outlined,
        title: _t('No approved package yet', 'ابھی کوئی منظور شدہ پیکیج نہیں'),
        copy: _t(
          'A Driver package appears here only after Admin approval and activation.',
          'ڈرائیور کا پیکیج ایڈمن کی منظوری اور فعال ہونے کے بعد یہاں نظر آئے گا۔',
        ),
      );
    }

    return Column(
      children: packages.map((package) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _ExplorePackageCard(
          package: package,
          urdu: _urdu,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LivePackageDetailScreen(package: package)),
          ),
        ),
      )).toList(),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF073E31), Color(0xFF0C8A65)],
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(color: Colors.white70, height: 1.35, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

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
    decoration: BoxDecoration(color: const Color(0xFFEDF5F2), borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        Expanded(child: _TabButton(selected: selected == 0, icon: Icons.landscape_rounded, label: destinationLabel, count: destinationsCount, onTap: () => onChanged(0))),
        Expanded(child: _TabButton(selected: selected == 1, icon: Icons.luggage_rounded, label: packageLabel, count: packagesCount, onTap: () => onChanged(1))),
      ],
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.selected, required this.icon, required this.label, required this.count, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        boxShadow: selected ? const [BoxShadow(color: Color(0x14063F32), blurRadius: 12, offset: Offset(0, 4))] : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: selected ? AppColors.primaryDark : AppColors.muted),
          const SizedBox(width: 5),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: selected ? AppColors.primaryDark : AppColors.muted))),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: selected ? const Color(0xFFDFF5EC) : Colors.white, borderRadius: BorderRadius.circular(99)),
            child: Text('$count', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
          ),
        ],
      ),
    ),
  );
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.item, required this.urdu, required this.onBook});
  final Map<String, dynamic> item;
  final bool urdu;
  final VoidCallback onBook;
  String _t(String en, String ur) => urdu ? ur : en;

  @override
  Widget build(BuildContext context) => PremiumCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 155,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                child: item['coverImageUrl'] == null
                    ? const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF08151C), Color(0xFF10212B)])), child: Center(child: Icon(Icons.landscape_rounded, color: Colors.white70, size: 62)))
                    : Image.network(ApiConfig.absoluteUrl(item['coverImageUrl']?.toString()), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF08151C), Color(0xFF10212B)])), child: Center(child: Icon(Icons.landscape_rounded, color: Colors.white70, size: 62)))),
              ),
              const DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(23)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]))),
              Positioned(
                left: 15,
                right: 15,
                bottom: 13,
                child: Row(
                  children: [
                    Expanded(child: Text('${item['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(99)),
                      child: Text('${item['routeSafetyScore'] ?? 0}/100', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 10)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(child: Text('${item['district'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                Text('${item['bestSeason'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
              const SizedBox(height: 8),
              Text('${item['summary'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _InfoChip(Icons.directions_car_rounded, '${item['recommendedVehicle'] ?? _t('Any vehicle', 'کوئی بھی گاڑی')}'),
                  _InfoChip(Icons.network_cell_rounded, '${item['networkStatus'] ?? _t('Unknown', 'نامعلوم')}'),
                ],
              ),
              const SizedBox(height: 13),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(onPressed: onBook, icon: const Icon(Icons.route_rounded), label: Text(_t('Plan ride to ${item['name']}', '${item['name']} کے لیے سفر بنائیں'))),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ExplorePackageCard extends StatelessWidget {
  const _ExplorePackageCard({required this.package, required this.urdu, required this.onTap});
  final LiveTourPackage package;
  final bool urdu;
  final VoidCallback onTap;
  String _t(String en, String ur) => urdu ? ur : en;

  @override
  Widget build(BuildContext context) => PremiumCard(
    onTap: onTap,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 145,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (package.coverImageUrl != null && package.coverImageUrl!.isNotEmpty)
                ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(23)), child: Image.network(package.coverImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0C6049), Color(0xFF16A978)])))))
              else
                const DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(23)), gradient: LinearGradient(colors: [Color(0xFF0C6049), Color(0xFF16A978)]))),
              const DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(23)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]))),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(color: package.bookableSeats <= 2 ? const Color(0xFFFFE8C4) : const Color(0xFFD9F7E9), borderRadius: BorderRadius.circular(99)),
                  child: Text(_t('${package.bookableSeats} seats free', '${package.bookableSeats} نشستیں خالی'), style: TextStyle(color: package.bookableSeats <= 2 ? const Color(0xFF955900) : const Color(0xFF08754F), fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
              Positioned(left: 15, right: 15, bottom: 13, child: Text(package.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFEAF7F2), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(child: Text(package.startingCity, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.arrow_forward_rounded, size: 17, color: AppColors.primary)),
                  Expanded(child: Text(package.destination, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.primaryDark))),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('${package.driverName} · ${package.vehicle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))),
                const Icon(Icons.verified_rounded, size: 16, color: AppColors.primary),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.muted),
                const SizedBox(width: 5),
                Text(DateFormat('dd MMM · hh:mm a').format(package.departureAt), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_t('Per seat', 'فی نشست'), style: const TextStyle(color: AppColors.muted, fontSize: 9)),
                  Text('PKR ${NumberFormat('#,###').format(package.pricePerSeat)}', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 14)),
                ]),
              ]),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFFF1F6F4), borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: AppColors.primaryDark), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))]),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.copy});
  final IconData icon;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Icon(icon, size: 54, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(copy, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
      ]),
    ),
  );
}
