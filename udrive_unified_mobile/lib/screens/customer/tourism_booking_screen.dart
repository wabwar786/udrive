import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import 'driver_offers_screen.dart';

class TourismBookingScreen extends StatefulWidget {
  const TourismBookingScreen({this.initialType, this.initialDestination, super.key});
  final BookingType? initialType;
  final String? initialDestination;

  @override
  State<TourismBookingScreen> createState() => _TourismBookingScreenState();
}

class _TourismBookingScreenState extends State<TourismBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController(text: 'Ghari Pan, Muzaffarabad');
  late final TextEditingController _destination;
  final _notes = TextEditingController();
  int _step = 0;
  late BookingType _bookingType;
  TripPartyType _partyType = TripPartyType.family;
  bool _returnTrip = false;
  bool _familyOnly = true;
  bool _femalePreference = false;
  DateTime _departureDate = DateTime.now().add(const Duration(days: 3));
  DateTime? _returnDate;
  TimeOfDay _departureTime = const TimeOfDay(hour: 7, minute: 0);
  int _adults = 2;
  int _children = 1;
  int _luggage = 2;
  VehicleCategory _vehicle = vehicleCategories[2];

  @override
  void initState() {
    super.initState();
    _bookingType = widget.initialType ?? BookingType.perSeat;
    _destination = TextEditingController(text: widget.initialDestination ?? 'Neelum Valley');
  }

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _travellers => _adults + _children;
  int get _estimate => _bookingType == BookingType.perSeat
      ? (_vehicle.baseFare * .55 * _travellers).round()
      : (_vehicle.baseFare * 2.8).round();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('advanceBooking'))),
        body: SafeArea(
          child: Column(
            children: [
              _BookingProgress(current: _step),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: IndexedStack(
                    index: _step,
                    children: [
                      _routeStep(),
                      _travelStep(),
                      _vehicleStep(),
                      _reviewStep(),
                    ],
                  ),
                ),
              ),
              _bottomActions(),
            ],
          ),
        ),
      );

  Widget _routeStep() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _StepIntro(
            icon: Icons.route_rounded,
            title: context.tr('whereTo'),
            subtitle: context.tr('bookingStepOneHelp'),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _pickup,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.trip_origin_rounded), labelText: context.tr('pickup')),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _destination,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.location_on_rounded), labelText: context.tr('destination')),
            validator: _required,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _DateCard(label: context.tr('departureDate'), value: DateFormat('dd MMM yyyy').format(_departureDate), icon: Icons.calendar_month_rounded, onTap: _pickDepartureDate)),
              const SizedBox(width: 10),
              Expanded(child: _DateCard(label: context.tr('departureTime'), value: _departureTime.format(context), icon: Icons.schedule_rounded, onTap: _pickTime)),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
            value: _returnTrip,
            onChanged: (value) => setState(() {
              _returnTrip = value;
              _returnDate = value ? _departureDate.add(const Duration(days: 2)) : null;
            }),
            title: Text(context.tr('returnTrip'), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(context.tr('returnTripHelp'), style: const TextStyle(fontSize: 12)),
          ),
          if (_returnTrip) ...[
            const SizedBox(height: 12),
            _DateCard(label: context.tr('returnDate'), value: DateFormat('dd MMM yyyy').format(_returnDate!), icon: Icons.event_repeat_rounded, onTap: _pickReturnDate),
          ],
        ],
      );

  Widget _travelStep() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _StepIntro(icon: Icons.people_alt_rounded, title: context.tr('travelDetails'), subtitle: context.tr('bookingStepTwoHelp')),
          const SizedBox(height: 18),
          _ChoiceCard(
            selected: _bookingType == BookingType.perSeat,
            icon: Icons.event_seat_rounded,
            title: context.tr('bookPerSeat'),
            subtitle: context.tr('perSeatHelp'),
            onTap: () => setState(() => _bookingType = BookingType.perSeat),
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            selected: _bookingType == BookingType.wholeVehicle,
            icon: Icons.directions_car_filled_rounded,
            title: context.tr('bookWholeVehicle'),
            subtitle: context.tr('wholeVehicleHelp'),
            onTap: () => setState(() => _bookingType = BookingType.wholeVehicle),
          ),
          const SizedBox(height: 18),
          PremiumCard(
            child: Column(
              children: [
                _CounterRow(label: context.tr('adults'), icon: Icons.person_rounded, value: _adults, min: 1, onChanged: (value) => setState(() => _adults = value)),
                const Divider(),
                _CounterRow(label: context.tr('children'), icon: Icons.child_care_rounded, value: _children, onChanged: (value) => setState(() => _children = value)),
                const Divider(),
                _CounterRow(label: context.tr('luggage'), icon: Icons.luggage_rounded, value: _luggage, onChanged: (value) => setState(() => _luggage = value)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(context.tr('travellerPreference'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PartyChip(value: TripPartyType.family, label: context.tr('family'), icon: Icons.family_restroom_rounded, selected: _partyType, onSelected: _selectParty),
              _PartyChip(value: TripPartyType.individual, label: context.tr('individual'), icon: Icons.person_rounded, selected: _partyType, onSelected: _selectParty),
              _PartyChip(value: TripPartyType.womenOnly, label: context.tr('womenOnly'), icon: Icons.woman_rounded, selected: _partyType, onSelected: _selectParty),
              _PartyChip(value: TripPartyType.group, label: context.tr('group'), icon: Icons.groups_rounded, selected: _partyType, onSelected: _selectParty),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _familyOnly,
            onChanged: (value) => setState(() => _familyOnly = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('familyOnlyPreference'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          CheckboxListTile(
            value: _femalePreference,
            onChanged: (value) => setState(() => _femalePreference = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('femalePassengerPreference'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      );

  Widget _vehicleStep() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _StepIntro(icon: Icons.directions_car_filled_rounded, title: context.tr('selectVehicle'), subtitle: context.tr('bookingStepThreeHelp')),
          const SizedBox(height: 18),
          ...vehicleCategories.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VehicleChoice(
                vehicle: vehicle,
                selected: _vehicle.name == vehicle.name,
                recommended: _recommended(vehicle),
                onTap: () => setState(() => _vehicle = vehicle),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(labelText: context.tr('specialInstructions'), hintText: context.tr('specialInstructionsHint'), prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 54), child: Icon(Icons.notes_rounded))),
          ),
        ],
      );

  Widget _reviewStep() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _StepIntro(icon: Icons.fact_check_rounded, title: context.tr('reviewBooking'), subtitle: context.tr('bookingStepFourHelp')),
          const SizedBox(height: 18),
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [const Icon(Icons.route_rounded, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text('${_pickup.text} → ${_destination.text}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)))]),
                const SizedBox(height: 16),
                _ReviewLine(label: context.tr('dateTime'), value: '${DateFormat('dd MMM yyyy').format(_departureDate)} · ${_departureTime.format(context)}'),
                _ReviewLine(label: context.tr('bookingOption'), value: _bookingType == BookingType.perSeat ? context.tr('bookPerSeat') : context.tr('bookWholeVehicle')),
                _ReviewLine(label: context.tr('passengers'), value: '$_travellers'),
                _ReviewLine(label: context.tr('vehicle'), value: _vehicle.name),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('transparentPrice'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 12),
                _PriceLine(label: _bookingType == BookingType.perSeat ? context.tr('seatFare') : context.tr('vehicleFare'), value: _estimate),
                const _PriceLine(label: 'Fuel & toll estimate', value: 900),
                const _PriceLine(label: 'uDrive service fee', value: 180),
                const Divider(height: 24),
                _PriceLine(label: context.tr('estimatedTotal'), value: _estimate + 1080, bold: true),
                const SizedBox(height: 8),
                Text(context.tr('noHiddenCharges'), style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            color: const Color(0xFFEAF8F2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.primaryDark),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr('secureBookingMessage'), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700, height: 1.4))),
              ],
            ),
          ),
        ],
      );

  Widget _bottomActions() => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            if (_step > 0) ...[
              SizedBox(width: 110, child: OutlinedButton(onPressed: () => setState(() => _step--), child: Text(context.tr('back')))),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _step == 3 ? _submit : _next,
                child: Text(_step == 3 ? context.tr('findVerifiedDrivers') : context.tr('continue')),
              ),
            ),
          ],
        ),
      );

  void _next() {
    if (_step == 0 && !_formKey.currentState!.validate()) return;
    setState(() => _step++);
  }

  void _submit() {
    final booking = AdvanceBooking(
      id: 'AB-${DateTime.now().millisecondsSinceEpoch}',
      pickup: _pickup.text.trim(),
      destination: _destination.text.trim(),
      departureDate: _departureDate,
      departureTime: _departureTime,
      bookingType: _bookingType,
      adults: _adults,
      children: _children,
      luggage: _luggage,
      vehicle: _vehicle.name,
      estimatedTotal: _estimate + 1080,
      partyType: _partyType,
      returnDate: _returnDate,
      notes: _notes.text.trim(),
    );
    AppControllerScope.of(context).addAdvanceBooking(booking);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverOffersScreen(
          pickup: booking.pickup,
          destination: booking.destination,
          customerOffer: booking.estimatedTotal,
          vehicle: _vehicle,
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? context.tr('required') : null;

  bool _recommended(VehicleCategory vehicle) {
    final destination = _destination.text.toLowerCase();
    if (destination.contains('arang') || destination.contains('ratti') || destination.contains('kel')) return vehicle.name == '4×4 Jeep';
    if (_travellers > 7) return vehicle.name == 'Hiace' || vehicle.name == 'Coaster';
    if (_partyType == TripPartyType.family) return vehicle.name == 'SUV';
    return vehicle.name == 'Comfort';
  }

  void _selectParty(TripPartyType value) => setState(() => _partyType = value);

  Future<void> _pickDepartureDate() async {
    final value = await showDatePicker(context: context, initialDate: _departureDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (value != null) setState(() => _departureDate = value);
  }

  Future<void> _pickReturnDate() async {
    final value = await showDatePicker(context: context, initialDate: _returnDate ?? _departureDate.add(const Duration(days: 1)), firstDate: _departureDate, lastDate: _departureDate.add(const Duration(days: 60)));
    if (value != null) setState(() => _returnDate = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _departureTime);
    if (value != null) setState(() => _departureTime = value);
  }
}

class _BookingProgress extends StatelessWidget {
  const _BookingProgress({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Row(
          children: List.generate(4, (index) {
            final active = index <= current;
            return Expanded(
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: active ? AppColors.primary : AppColors.background, shape: BoxShape.circle, border: Border.all(color: active ? AppColors.primary : AppColors.border)),
                    alignment: Alignment.center,
                    child: Text('${index + 1}', style: TextStyle(color: active ? Colors.white : AppColors.muted, fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                  if (index < 3) Expanded(child: Container(height: 2, color: index < current ? AppColors.primary : AppColors.border)),
                ],
              ),
            );
          }),
        ),
      );
}

class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 50, height: 50, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: AppColors.primaryDark)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: AppColors.muted, height: 1.4))])),
        ],
      );
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.label, required this.value, required this.icon, required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(height: 10), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))]),
      );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: selected ? const Color(0xFFEAF8F2) : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1)),
          child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: AppColors.primaryDark)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35))])), Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? AppColors.primary : AppColors.border)]),
        ),
      );
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({required this.label, required this.icon, required this.value, required this.onChanged, this.min = 0});
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
          IconButton.filledTonal(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded, size: 18)),
          SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          IconButton.filledTonal(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_rounded, size: 18)),
        ],
      );
}

class _PartyChip extends StatelessWidget {
  const _PartyChip({required this.value, required this.label, required this.icon, required this.selected, required this.onSelected});
  final TripPartyType value;
  final String label;
  final IconData icon;
  final TripPartyType selected;
  final ValueChanged<TripPartyType> onSelected;
  @override
  Widget build(BuildContext context) => ChoiceChip(selected: selected == value, onSelected: (_) => onSelected(value), avatar: Icon(icon, size: 18), label: Text(label));
}

class _VehicleChoice extends StatelessWidget {
  const _VehicleChoice({required this.vehicle, required this.selected, required this.recommended, required this.onTap});
  final VehicleCategory vehicle;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: selected ? const Color(0xFFEAF8F2) : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1)),
          child: Row(children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .11), borderRadius: BorderRadius.circular(16)), child: Icon(vehicle.icon, color: AppColors.primaryDark)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))), if (recommended) ...[const SizedBox(width: 7), StatusPill(label: context.tr('recommended'))]]), const SizedBox(height: 3), Text('${vehicle.seats} seats · ${vehicle.luggage} bags', style: const TextStyle(color: AppColors.muted, fontSize: 12)), Text(vehicle.description, style: const TextStyle(color: AppColors.muted, fontSize: 11))])), Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: selected ? AppColors.primary : AppColors.muted)]),
        ),
      );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 105, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12))), Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)))]));
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.label, required this.value, this.bold = false});
  final String label;
  final int value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: bold ? AppColors.navy : AppColors.muted, fontWeight: bold ? FontWeight.w900 : FontWeight.w600))), Text('PKR ${NumberFormat('#,###').format(value)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: bold ? 17 : 13, color: AppColors.navy))]));
}
