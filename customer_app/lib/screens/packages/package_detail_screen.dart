import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';

class PackageDetailScreen extends StatefulWidget {
  const PackageDetailScreen({required this.package, super.key});
  final TourPackage package;
  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  bool _customOffer = false;
  final _offer = TextEditingController();
  @override
  void dispose() { _offer.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item = widget.package;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 260, pinned: true,
          flexibleSpace: FlexibleSpaceBar(background: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(item.imageColor), Color(item.imageColor).withValues(alpha: .55)])), child: const Center(child: Icon(Icons.landscape_rounded, color: Colors.white, size: 92)))),
        ),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 20, 18, 120), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
          Row(children: [const Icon(Icons.star_rounded, color: AppColors.accent), Text(' ${item.rating} · ${item.driver}'), const Spacer(), const Icon(Icons.verified_rounded, color: AppColors.secondary)]),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _MiniStat(icon: Icons.calendar_month, value: '${item.days} days'),
            _MiniStat(icon: Icons.directions_car, value: item.vehicle),
            _MiniStat(icon: Icons.groups, value: 'Up to 6'),
          ]))),
          const SizedBox(height: 20),
          Text(S.of(context, 'itinerary'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
          ...['Day 1 · Muzaffarabad to Keran', 'Day 2 · Keran, Sharda and local sightseeing', 'Day 3 · Return through Dhani Waterfall'].map((e) => ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(radius: 15, child: Icon(Icons.check, size: 17)), title: Text(e))),
          const SizedBox(height: 12),
          Text(S.of(context, 'included'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
          const Wrap(spacing: 8, runSpacing: 8, children: [Chip(label: Text('Vehicle')), Chip(label: Text('Fuel')), Chip(label: Text('Tolls')), Chip(label: Text('Driver accommodation'))]),
          const SizedBox(height: 18),
          SegmentedButton<bool>(segments: [ButtonSegment(value: false, label: Text(S.of(context, 'fixedPrice'))), ButtonSegment(value: true, label: Text(S.of(context, 'sendOffer')))], selected: {_customOffer}, onSelectionChanged: (v) => setState(() => _customOffer = v.first)),
          if (_customOffer) ...[const SizedBox(height: 12), TextField(controller: _offer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your package offer', prefixText: 'PKR '))],
        ]))),
      ]),
      bottomSheet: SafeArea(child: Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(18, 12, 18, 16), child: Row(children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total', style: TextStyle(color: AppColors.muted)), Text('PKR ${item.price}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]),
        const SizedBox(width: 18),
        Expanded(child: FilledButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package booking request submitted'))), child: Text(_customOffer ? S.of(context, 'sendOffer') : S.of(context, 'bookNow')))),
      ]))),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value}); final IconData icon; final String value;
  @override Widget build(BuildContext context) => Column(children: [Icon(icon, color: AppColors.primary), const SizedBox(height: 5), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]);
}
