import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import 'driver_offers_screen.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});
  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController(text: 'Muzaffarabad');
  final _destination = TextEditingController(text: 'Keran, Neelum Valley');
  final _fare = TextEditingController(text: '5000');
  int _passengers = 2;
  int _luggage = 1;
  String _vehicle = 'Comfort';

  @override
  void dispose() {
    _pickup.dispose(); _destination.dispose(); _fare.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context, 'requestRide'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            const _RoutePreview(),
            const SizedBox(height: 18),
            TextFormField(controller: _pickup, decoration: InputDecoration(labelText: S.of(context, 'pickup'), prefixIcon: const Icon(Icons.radio_button_checked_rounded)), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _destination, decoration: InputDecoration(labelText: S.of(context, 'destination'), prefixIcon: const Icon(Icons.location_on_outlined)), validator: _required),
            const SizedBox(height: 12),
            TextFormField(readOnly: true, initialValue: '18 Jul 2026 · 08:00', decoration: InputDecoration(labelText: S.of(context, 'dateTime'), prefixIcon: const Icon(Icons.calendar_month_outlined))),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _Counter(label: S.of(context, 'passengers'), value: _passengers, onChanged: (v) => setState(() => _passengers = v))),
              const SizedBox(width: 10),
              Expanded(child: _Counter(label: S.of(context, 'luggage'), value: _luggage, onChanged: (v) => setState(() => _luggage = v))),
            ]),
            const SizedBox(height: 18),
            const Text('Vehicle', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: ['Economy', 'Comfort', 'SUV', '4×4 Jeep'].map((item) => ChoiceChip(label: Text(item), selected: _vehicle == item, onSelected: (_) => setState(() => _vehicle = item))).toList()),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(S.of(context, 'suggestedFare'), style: const TextStyle(fontWeight: FontWeight.w800)), const Spacer(), const Text('PKR 5,400', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary))]),
                  const SizedBox(height: 12),
                  TextFormField(controller: _fare, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context, 'offerFare'), prefixText: 'PKR '), validator: (value) {
                    final amount = int.tryParse(value ?? '');
                    if (amount == null || amount < 1000) return 'Enter a valid offer';
                    return null;
                  }),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => DriverOffersScreen(customerOffer: int.parse(_fare.text))));
              },
              icon: const Icon(Icons.send_rounded),
              label: Text(S.of(context, 'requestRide')),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'This field is required' : null;
}

class _RoutePreview extends StatelessWidget {
  const _RoutePreview();
  @override
  Widget build(BuildContext context) => Container(
    height: 145,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFFDCEFEA), Color(0xFFDDE8FB)])),
    child: Stack(children: [
      const Positioned(left: 34, top: 32, child: Icon(Icons.trip_origin, color: AppColors.primary)),
      const Positioned(right: 38, bottom: 28, child: Icon(Icons.location_on, color: AppColors.secondary, size: 36)),
      Positioned(left: 58, top: 51, right: 62, child: Container(height: 3, transform: Matrix4.rotationZ(.2), color: Colors.white)),
      const Center(child: Icon(Icons.directions_car_rounded, color: AppColors.text, size: 34)),
    ]),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onChanged});
  final String label; final int value; final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
    Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      IconButton.filledTonal(onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
      Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      IconButton.filledTonal(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add)),
    ]),
  ])));
}
