import 'package:flutter/material.dart';

import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import 'tourism_booking_screen.dart';

class LiveExploreScreen extends StatefulWidget {
  const LiveExploreScreen({super.key});

  @override
  State<LiveExploreScreen> createState() => _LiveExploreScreenState();
}

class _LiveExploreScreenState extends State<LiveExploreScreen> {
  late final ApiClient _api;
  List<Map<String, dynamic>> _items = const [];
  bool _busy = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _api = ApiClient(SessionStore());
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _busy = true; _error = null; });
    try {
      final language = AppControllerScope.of(context).locale.languageCode;
      final response = await _api.getJson('/api/v1/catalog/destinations?language=$language', authenticated: false);
      final raw = response['data'] as List? ?? const [];
      _items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = _items.where((e) {
      if (q.isEmpty) return true;
      return '${e['name']} ${e['district']} ${e['summary']}'.toLowerCase().contains(q);
    }).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(hintText: 'Search Kashmir destinations', prefixIcon: Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 16),
          if (_busy && _items.isEmpty) const Padding(padding: EdgeInsets.all(56), child: Center(child: CircularProgressIndicator())),
          if (_error != null) PremiumCard(child: Column(children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 10), FilledButton(onPressed: _load, child: const Text('Retry'))])),
          if (!_busy && _error == null && items.isEmpty) const PremiumCard(child: Text('No destination matches your search.', textAlign: TextAlign.center)),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PremiumCard(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                  child: item['coverImageUrl'] == null
                      ? Container(height: 180, color: AppColors.primary.withValues(alpha: .12), child: const Center(child: Icon(Icons.landscape_rounded, size: 58, color: AppColors.primaryDark)))
                      : Image.network('${item['coverImageUrl']}', height: 180, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 180, color: AppColors.primary.withValues(alpha: .12), child: const Center(child: Icon(Icons.landscape_rounded, size: 58, color: AppColors.primaryDark)))),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text('${item['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))), StatusPill(label: '${item['routeSafetyScore']}/100')]),
                    const SizedBox(height: 5),
                    Text('${item['district']} · ${item['bestSeason']}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 9),
                    Text('${item['summary']}', style: const TextStyle(color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 12),
                    Text('Recommended: ${item['recommendedVehicle']} · Network: ${item['networkStatus']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 13),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TourismBookingScreen(initialDestination: '${item['name']}'))),
                      icon: const Icon(Icons.local_taxi_rounded),
                      label: Text('Ride to ${item['name']}'),
                    ),
                  ]),
                ),
              ]),
            ),
          )),
        ],
      ),
    );
  }
}
