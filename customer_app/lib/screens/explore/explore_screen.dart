import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dummy_data.dart';
import '../packages/package_detail_screen.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
    Text(S.of(context, 'explore'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
    const SizedBox(height: 6),
    const Text('Driver-created packages approved by UDrive.', style: TextStyle(color: AppColors.muted)),
    const SizedBox(height: 18),
    TextField(decoration: InputDecoration(hintText: 'Search destinations or packages', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: IconButton(onPressed: () {}, icon: const Icon(Icons.tune_rounded)))),
    const SizedBox(height: 16),
    Wrap(spacing: 8, children: const [Chip(label: Text('Neelum')), Chip(label: Text('Family')), Chip(label: Text('4×4')), Chip(label: Text('Weekend'))]),
    const SizedBox(height: 18),
    ...tourPackages.map((item) => Padding(padding: const EdgeInsets.only(bottom: 12), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(package: item))), borderRadius: BorderRadius.circular(22), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      Container(width: 88, height: 88, decoration: BoxDecoration(color: Color(item.imageColor), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.landscape_rounded, color: Colors.white, size: 42)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 5),
        Text(item.route, maxLines: 2, style: const TextStyle(color: AppColors.muted)), const SizedBox(height: 10),
        Row(children: [Text('${item.days} days · ${item.vehicle}'), const Spacer(), Text('PKR ${item.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary))]),
      ])),
    ]))))),
  ]));
}
