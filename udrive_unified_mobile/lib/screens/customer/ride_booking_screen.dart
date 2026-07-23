import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import 'driver_offers_screen.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({this.serviceId = 'local', super.key});
  final String serviceId;
  @override
  State<RideBookingScreen> createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController(text: 'F-8 Markaz, Islamabad');
  final _destination = TextEditingController(text: 'Muzaffarabad, Azad Kashmir');
  final _offer = TextEditingController(text: '5200');
  VehicleCategory _vehicle = vehicleCategories[1];
  int _passengers = 2;
  int _luggage = 1;
  bool _scheduled = false;
  DateTime _date = DateTime.now().add(const Duration(hours: 1));

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    _offer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('bookRide'))),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
            children: [
              const MapPreview(height: 190),
              const SizedBox(height: 18),
              PremiumCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _pickup,
                      decoration: InputDecoration(labelText: context.tr('pickup'), prefixIcon: const Icon(Icons.trip_origin_rounded, color: AppColors.primary)),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _destination,
                      decoration: InputDecoration(labelText: context.tr('destination'), prefixIcon: const Icon(Icons.location_on_rounded, color: AppColors.secondary)),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _scheduled,
                      onChanged: (value) => setState(() => _scheduled = value),
                      title: const Text('Schedule this ride', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_scheduled ? '${_date.day}/${_date.month}/${_date.year} · ${TimeOfDay.fromDateTime(_date).format(context)}' : 'Request nearby drivers now'),
                      secondary: const Icon(Icons.calendar_month_rounded),
                    ),
                    if (_scheduled)
                      OutlinedButton.icon(
                        onPressed: _selectDateTime,
                        icon: const Icon(Icons.edit_calendar_rounded),
                        label: Text(context.tr('dateTime')),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(title: context.tr('vehicle')),
              const SizedBox(height: 10),
              SizedBox(
                height: 145,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: vehicleCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = vehicleCategories[index];
                    final selected = item == _vehicle;
                    return InkWell(
                      onTap: () => setState(() {
                        _vehicle = item;
                        _offer.text = item.baseFare.toString();
                      }),
                      borderRadius: BorderRadius.circular(21),
                      child: Container(
                        width: 142,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary.withValues(alpha: .1) : Colors.white,
                          borderRadius: BorderRadius.circular(21),
                          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.7 : 1),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(item.icon, color: selected ? AppColors.primaryDark : AppColors.navy, size: 31),
                          const Spacer(),
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('${item.seats} seats · ${item.luggage} bags', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          const SizedBox(height: 5),
                          Text('From PKR ${item.baseFare}', style: const TextStyle(color: AppColors.primaryDark, fontSize: 11, fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _CounterTile(label: context.tr('passengers'), icon: Icons.people_alt_rounded, value: _passengers, onChanged: (value) => setState(() => _passengers = value))),
                const SizedBox(width: 10),
                Expanded(child: _CounterTile(label: context.tr('luggage'), icon: Icons.luggage_rounded, value: _luggage, onChanged: (value) => setState(() => _luggage = value))),
              ]),
              const SizedBox(height: 20),
              PremiumCard(
                color: const Color(0xFFF1FAF6),
                child: Column(
                  children: [
                    Row(children: [Text(context.tr('suggestedFare'), style: const TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('PKR ${_vehicle.baseFare}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _offer,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('yourOffer'), prefixText: 'PKR ', prefixIcon: const Icon(Icons.local_offer_rounded)),
                      validator: (value) {
                        final amount = int.tryParse(value ?? '');
                        if (amount == null || amount < 500) return 'Enter a valid offer';
                        return null;
                      },
                    ),
                    const SizedBox(height: 9),
                    const Row(children: [Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted), SizedBox(width: 6), Expanded(child: Text('Drivers may accept your fare or send a counteroffer.', style: TextStyle(color: AppColors.muted, fontSize: 11)))]),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomSheet: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
            child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.send_rounded), label: Text(context.tr('requestRide'))),
          ),
        ),
      );

  String? _required(String? value) => (value ?? '').trim().isEmpty ? context.tr('required') : null;

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (time == null) return;
    setState(() => _date = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverOffersScreen(
          pickup: _pickup.text,
          destination: _destination.text,
          customerOffer: int.parse(_offer.text),
          vehicle: _vehicle,
        ),
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({required this.label, required this.icon, required this.value, required this.onChanged});
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => PremiumCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          children: [
            Row(children: [Icon(icon, size: 19, color: AppColors.primaryDark), const SizedBox(width: 7), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _RoundButton(icon: Icons.remove, onTap: value > 0 ? () => onChanged(value - 1) : null),
              Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              _RoundButton(icon: Icons.add, onTap: () => onChanged(value + 1)),
            ]),
          ],
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 17, color: onTap == null ? AppColors.border : AppColors.navy)),
      );
}
