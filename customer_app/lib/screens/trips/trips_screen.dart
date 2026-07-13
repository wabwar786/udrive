import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dummy_data.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
    Text(S.of(context, 'trips'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
    const SizedBox(height: 18),
    ...tripRecords.map((trip) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(trip.route, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))), Chip(label: Text(trip.status))]),
      const SizedBox(height: 8),
      Text(trip.date, style: const TextStyle(color: AppColors.muted)), const SizedBox(height: 12),
      Row(children: [const CircleAvatar(radius: 18, child: Icon(Icons.person, size: 18)), const SizedBox(width: 9), Text(trip.driver), const Spacer(), Text('PKR ${trip.price}', style: const TextStyle(fontWeight: FontWeight.w900))]),
    ]))))),
  ]));
}
