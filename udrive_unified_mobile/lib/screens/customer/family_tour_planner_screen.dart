import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';

class FamilyTourPlannerScreen extends StatefulWidget {
  const FamilyTourPlannerScreen({super.key});

  @override
  State<FamilyTourPlannerScreen> createState() => _FamilyTourPlannerScreenState();
}

class _FamilyTourPlannerScreenState extends State<FamilyTourPlannerScreen> {
  final _start = TextEditingController(text: 'Islamabad');
  String _destination = 'Neelum Valley';
  int _days = 3;
  int _adults = 2;
  int _children = 2;
  int _infants = 0;
  int _elderly = 1;
  int _budget = 70000;
  String _vehicle = 'SUV';
  bool _hotel = true;
  bool _meals = false;
  bool _childSeat = true;
  bool _accessible = false;
  FamilyTourPlan? _plan;

  @override
  void dispose() {
    _start.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('familyTourPlanner'))),
        body: _plan == null ? _form() : _result(_plan!),
      );

  Widget _form() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Row(
              children: [
                Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.family_restroom_rounded, color: Colors.white, size: 29)),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('planSafeFamilyTour'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 4), Text(context.tr('familyPlannerSubtitle'), style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35))])),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextFormField(controller: _start, decoration: InputDecoration(labelText: context.tr('startLocation'), prefixIcon: const Icon(Icons.trip_origin_rounded))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _destination,
            decoration: InputDecoration(labelText: context.tr('preferredDestination'), prefixIcon: const Icon(Icons.location_on_rounded)),
            items: destinations.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name))).toList(),
            onChanged: (value) => setState(() => _destination = value ?? 'Neelum Valley'),
          ),
          const SizedBox(height: 14),
          PremiumCard(child: _PlannerCounter(icon: Icons.calendar_month_rounded, label: context.tr('numberOfDays'), value: _days, min: 1, max: 14, onChanged: (value) => setState(() => _days = value))),
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(
              children: [
                _PlannerCounter(icon: Icons.person_rounded, label: context.tr('adults'), value: _adults, min: 1, max: 20, onChanged: (value) => setState(() => _adults = value)),
                const Divider(),
                _PlannerCounter(icon: Icons.child_care_rounded, label: context.tr('children'), value: _children, min: 0, max: 20, onChanged: (value) => setState(() => _children = value)),
                const Divider(),
                _PlannerCounter(icon: Icons.baby_changing_station_rounded, label: context.tr('infants'), value: _infants, min: 0, max: 10, onChanged: (value) => setState(() => _infants = value)),
                const Divider(),
                _PlannerCounter(icon: Icons.elderly_rounded, label: context.tr('elderlyPersons'), value: _elderly, min: 0, max: 10, onChanged: (value) => setState(() => _elderly = value)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            decoration: InputDecoration(labelText: context.tr('vehiclePreference'), prefixIcon: const Icon(Icons.directions_car_filled_rounded)),
            items: vehicleCategories.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name))).toList(),
            onChanged: (value) => setState(() => _vehicle = value ?? 'SUV'),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryDark), const SizedBox(width: 10), Expanded(child: Text(context.tr('familyBudget'), style: const TextStyle(fontWeight: FontWeight.w900))), Text('PKR ${NumberFormat('#,###').format(_budget)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
              Slider(value: _budget.toDouble(), min: 20000, max: 250000, divisions: 23, label: 'PKR $_budget', onChanged: (value) => setState(() => _budget = value.round())),
            ]),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(children: [
              _FeatureSwitch(icon: Icons.hotel_rounded, label: context.tr('hotelRequired'), value: _hotel, onChanged: (value) => setState(() => _hotel = value)),
              const Divider(),
              _FeatureSwitch(icon: Icons.restaurant_rounded, label: context.tr('mealsRequired'), value: _meals, onChanged: (value) => setState(() => _meals = value)),
              const Divider(),
              _FeatureSwitch(icon: Icons.child_friendly_rounded, label: context.tr('childSeatRequired'), value: _childSeat, onChanged: (value) => setState(() => _childSeat = value)),
              const Divider(),
              _FeatureSwitch(icon: Icons.accessible_rounded, label: context.tr('accessibilityRequired'), value: _accessible, onChanged: (value) => setState(() => _accessible = value)),
            ]),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.auto_awesome_rounded), label: Text(context.tr('generateFamilyPlan'))),
        ],
      );

  Widget _result(FamilyTourPlan plan) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.auto_awesome_rounded, color: AppColors.accent), const SizedBox(width: 9), Expanded(child: Text(context.tr('yourFamilyPlanReady'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)))]),
              const SizedBox(height: 14),
              Text('${plan.startLocation} → ${plan.destination}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 6),
              Text('${plan.days} days · ${plan.adults + plan.children + plan.infants + plan.elderly} travellers · ${plan.vehicle}', style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [MetricTile(icon: Icons.shield_rounded, label: context.tr('safetyScore'), value: '${plan.safetyScore}/100', color: AppColors.success), const SizedBox(width: 10), MetricTile(icon: Icons.payments_rounded, label: context.tr('estimatedTotal'), value: '${(plan.estimatedTotal / 1000).toStringAsFixed(0)}K', color: AppColors.secondary)]),
          const SizedBox(height: 18),
          SectionHeader(title: context.tr('recommendedItinerary')),
          const SizedBox(height: 9),
          ...plan.itinerary.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 10), child: PremiumCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('${entry.key + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))), const SizedBox(width: 12), Expanded(child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.45)))])))),
          const SizedBox(height: 8),
          PremiumCard(
            color: const Color(0xFFF0FAF6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PlanInfo(icon: Icons.directions_car_filled_rounded, label: context.tr('recommendedVehicle'), value: plan.vehicle),
              _PlanInfo(icon: Icons.hotel_rounded, label: context.tr('hotelSuggestion'), value: plan.hotelSuggestion),
              _PlanInfo(icon: Icons.schedule_rounded, label: context.tr('bestDepartureTime'), value: '6:30 AM'),
              _PlanInfo(icon: Icons.warning_amber_rounded, label: context.tr('roadDifficulty'), value: plan.destination.contains('Neelum') ? 'Moderate mountain route' : 'Easy to moderate'),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => _book(plan), icon: const Icon(Icons.verified_user_rounded), label: Text(context.tr('findFamilyDriver'))),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => setState(() => _plan = null), icon: const Icon(Icons.edit_rounded), label: Text(context.tr('editPlan'))),
        ],
      );

  void _generate() {
    final groupSize = _adults + _children + _infants + _elderly;
    final recommendedVehicle = groupSize > 7 ? 'Hiace' : groupSize > 4 ? 'SUV' : _vehicle;
    final base = 16000 + (_days * 8500) + (groupSize * 1200) + (_hotel ? _days * 6500 : 0) + (_meals ? groupSize * _days * 1000 : 0);
    final estimate = base.clamp(20000, _budget + 25000).toInt();
    final itinerary = _buildItinerary(_destination, _days);
    final plan = FamilyTourPlan(
      id: 'FP-${DateTime.now().millisecondsSinceEpoch}',
      startLocation: _start.text.trim().isEmpty ? 'Islamabad' : _start.text.trim(),
      destination: _destination,
      days: _days,
      adults: _adults,
      children: _children,
      infants: _infants,
      elderly: _elderly,
      budget: _budget,
      vehicle: recommendedVehicle,
      estimatedTotal: estimate,
      itinerary: itinerary,
      hotelSuggestion: _hotel ? 'Family hotel near the main bazaar with parking' : 'No hotel requested',
      safetyScore: _accessible || _elderly > 0 ? 94 : 91,
    );
    AppControllerScope.of(context).addFamilyPlan(plan);
    setState(() => _plan = plan);
  }

  List<String> _buildItinerary(String destination, int days) {
    final templates = <String, List<String>>{
      'Neelum Valley': ['Islamabad to Muzaffarabad, hotel check-in and local sightseeing', 'Muzaffarabad to Keran, river-side family stops', 'Keran to Sharda and return journey', 'Kel day visit with approved local Jeep', 'Relaxed return via Muzaffarabad'],
      'Banjosa Lake': ['Islamabad to Rawalakot and hotel check-in', 'Banjosa Lake family picnic and local sightseeing', 'Toli Pir morning visit and return'],
      'Pir Chinasi': ['Arrival in Muzaffarabad and local sightseeing', 'Early Pir Chinasi visit and family picnic', 'Return with optional Kashmir waterfall stop'],
    };
    final selected = templates[destination] ?? templates['Neelum Valley']!;
    return List.generate(days, (index) => 'Day ${index + 1}: ${selected[index % selected.length]}');
  }

  void _book(FamilyTourPlan plan) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.verified_user_rounded, color: AppColors.success, size: 52),
          title: Text(context.tr('familyDriverSearchStarted')),
          content: Text(context.tr('familyDriverSearchMessage')),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('done')))],
        ),
      );
}

class _PlannerCounter extends StatelessWidget {
  const _PlannerCounter({required this.icon, required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded, size: 18)), SizedBox(width: 38, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), IconButton.filledTonal(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_rounded, size: 18))]);
}

class _FeatureSwitch extends StatelessWidget {
  const _FeatureSwitch({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, secondary: Icon(icon, color: AppColors.primaryDark), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)), value: value, onChanged: onChanged);
}

class _PlanInfo extends StatelessWidget {
  const _PlanInfo({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 11), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppColors.primaryDark, size: 20), const SizedBox(width: 9), SizedBox(width: 125, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700))), Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)))]));
}
