import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';

class JoinTourScreen extends StatefulWidget {
  const JoinTourScreen({super.key});

  @override
  State<JoinTourScreen> createState() => _JoinTourScreenState();
}

class _JoinTourScreenState extends State<JoinTourScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  TripPartyType? _filter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr('joinTour')),
          bottom: TabBar(
            controller: _tabs,
            tabs: [Tab(text: context.tr('availableTours')), Tab(text: context.tr('registerInterest'))],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [_availableTours(), const TourInterestForm()],
        ),
      );

  Widget _availableTours() {
    final items = _filter == null ? sharedTours : sharedTours.where((item) => item.partyType == _filter).toList();
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Row(
              children: [
                Container(width: 54, height: 54, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.groups_rounded, color: Colors.white)),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('joinTourHeadline'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 4), Text(context.tr('joinTourSubtitle'), style: const TextStyle(color: Colors.white70, height: 1.35, fontSize: 12))])),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(label: context.tr('all'), selected: _filter == null, onTap: () => setState(() => _filter = null)),
                _FilterChip(label: context.tr('familyOnly'), selected: _filter == TripPartyType.family, onTap: () => setState(() => _filter = TripPartyType.family)),
                _FilterChip(label: context.tr('womenOnly'), selected: _filter == TripPartyType.womenOnly, onTap: () => setState(() => _filter = TripPartyType.womenOnly)),
                _FilterChip(label: context.tr('group'), selected: _filter == TripPartyType.group, onTap: () => setState(() => _filter = TripPartyType.group)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 13), child: SharedTourCard(tour: item))),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(child: Column(children: [const Icon(Icons.search_off_rounded, size: 56, color: AppColors.muted), const SizedBox(height: 12), Text(context.tr('noMatchingTours'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800))])),
            ),
        ],
      ),
    );
  }
}

class SharedTourCard extends StatelessWidget {
  const SharedTourCard({required this.tour, super.key});
  final SharedTour tour;

  @override
  Widget build(BuildContext context) => PremiumCard(
        padding: EdgeInsets.zero,
        onTap: () => _openDetails(context),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: const BoxDecoration(color: Color(0xFFF0FAF6), borderRadius: BorderRadius.vertical(top: Radius.circular(23))),
              child: Row(
                children: [
                  StatusPill(label: '${tour.matchPercent}% ${context.tr('match')}'),
                  const Spacer(),
                  Icon(Icons.shield_rounded, size: 17, color: tour.safetyScore >= 90 ? AppColors.success : AppColors.warning),
                  const SizedBox(width: 4),
                  Text('${tour.safetyScore}/100', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tour.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.navy)),
                  const SizedBox(height: 8),
                  _TourInfo(icon: Icons.trip_origin_rounded, text: tour.pickup),
                  _TourInfo(icon: Icons.location_on_rounded, text: tour.destination),
                  _TourInfo(icon: Icons.schedule_rounded, text: '${tour.departureDate} · ${tour.departureTime}'),
                  const Divider(height: 24),
                  Row(
                    children: [
                      CircleAvatar(radius: 21, backgroundColor: AppColors.primary.withValues(alpha: .12), child: const Icon(Icons.person_rounded, color: AppColors.primaryDark)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(tour.driver, style: const TextStyle(fontWeight: FontWeight.w900))), if (tour.verifiedDriver) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, size: 16, color: AppColors.info))]), Text('${tour.vehicle} · ${tour.rating} ★', style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${tour.availableSeats} ${context.tr('seatsLeft')}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)), Text('${tour.totalSeats} total', style: const TextStyle(color: AppColors.muted, fontSize: 10))]),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(child: _FareBox(label: context.tr('perSeat'), amount: tour.pricePerSeat)),
                      const SizedBox(width: 9),
                      Expanded(child: _FareBox(label: context.tr('wholeVehicle'), amount: tour.wholeVehiclePrice)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  void _openDetails(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .88,
          minChildSize: .55,
          maxChildSize: .96,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(9)))),
              const SizedBox(height: 18),
              Row(children: [Expanded(child: Text(tour.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))), StatusPill(label: '${tour.matchPercent}% ${context.tr('match')}')]),
              const SizedBox(height: 14),
              PremiumCard(color: const Color(0xFFF0FAF6), child: Column(children: [_TourInfo(icon: Icons.trip_origin_rounded, text: tour.pickup), _TourInfo(icon: Icons.location_on_rounded, text: tour.destination), _TourInfo(icon: Icons.schedule_rounded, text: '${tour.departureDate} · ${tour.departureTime}'), _TourInfo(icon: Icons.directions_car_filled_rounded, text: tour.vehicle)])),
              const SizedBox(height: 14),
              SectionHeader(title: context.tr('securePassengerSummary')),
              const SizedBox(height: 8),
              PremiumCard(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_PassengerCount(icon: Icons.man_rounded, label: context.tr('male'), value: tour.malePassengers), _PassengerCount(icon: Icons.woman_rounded, label: context.tr('female'), value: tour.femalePassengers), _PassengerCount(icon: Icons.child_care_rounded, label: context.tr('children'), value: tour.children)])),
              const SizedBox(height: 14),
              PremiumCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Icon(Icons.verified_user_rounded, color: AppColors.success), const SizedBox(width: 8), Expanded(child: Text(context.tr('verifiedTripProtection'), style: const TextStyle(fontWeight: FontWeight.w900)))]),
                  const SizedBox(height: 10),
                  _SafetyLine(text: context.tr('otpTripStart')),
                  _SafetyLine(text: context.tr('liveLocationSharing')),
                  _SafetyLine(text: context.tr('privatePassengerData')),
                  _SafetyLine(text: context.tr('supportMonitoring')),
                ]),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _confirm(context, BookingType.perSeat),
                      child: Text('${context.tr('bookPerSeat')} · PKR ${tour.pricePerSeat}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _confirm(context, BookingType.wholeVehicle),
                      child: Text(context.tr('bookWholeVehicle')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  void _confirm(BuildContext context, BookingType type) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 52),
        title: Text(context.tr('tourSeatReserved')),
        content: Text(type == BookingType.perSeat ? context.tr('perSeatReservationSuccess') : context.tr('wholeVehicleReservationSuccess')),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('done')))],
      ),
    );
  }
}

class TourInterestForm extends StatefulWidget {
  const TourInterestForm({super.key});

  @override
  State<TourInterestForm> createState() => _TourInterestFormState();
}

class _TourInterestFormState extends State<TourInterestForm> {
  final _formKey = GlobalKey<FormState>();
  final _destination = TextEditingController(text: 'Neelum Valley');
  final _pickup = TextEditingController(text: 'Ghari Pan, Muzaffarabad');
  final _budget = TextEditingController(text: '5000');
  DateTime _from = DateTime.now().add(const Duration(days: 10));
  DateTime _to = DateTime.now().add(const Duration(days: 13));
  int _persons = 2;
  TripPartyType _party = TripPartyType.family;
  String _vehicle = 'SUV';

  @override
  void dispose() {
    _destination.dispose();
    _pickup.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            _InterestHero(),
            const SizedBox(height: 18),
            TextFormField(controller: _destination, decoration: InputDecoration(labelText: context.tr('destination'), prefixIcon: const Icon(Icons.location_on_rounded)), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _pickup, decoration: InputDecoration(labelText: context.tr('pickupCity'), prefixIcon: const Icon(Icons.trip_origin_rounded)), validator: _required),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _DatePickerField(label: context.tr('dateFrom'), value: _from, onTap: () => _pickDate(true))), const SizedBox(width: 10), Expanded(child: _DatePickerField(label: context.tr('dateTo'), value: _to, onTap: () => _pickDate(false)))]),
            const SizedBox(height: 14),
            PremiumCard(child: _PersonCounter(value: _persons, onChanged: (value) => setState(() => _persons = value))),
            const SizedBox(height: 14),
            DropdownButtonFormField<TripPartyType>(
              initialValue: _party,
              decoration: InputDecoration(labelText: context.tr('tourType'), prefixIcon: const Icon(Icons.groups_rounded)),
              items: [
                DropdownMenuItem(value: TripPartyType.family, child: Text(context.tr('family'))),
                DropdownMenuItem(value: TripPartyType.individual, child: Text(context.tr('individual'))),
                DropdownMenuItem(value: TripPartyType.womenOnly, child: Text(context.tr('womenOnly'))),
                DropdownMenuItem(value: TripPartyType.group, child: Text(context.tr('group'))),
              ],
              onChanged: (value) => setState(() => _party = value ?? TripPartyType.family),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _vehicle,
              decoration: InputDecoration(labelText: context.tr('vehiclePreference'), prefixIcon: const Icon(Icons.directions_car_filled_rounded)),
              items: vehicleCategories.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name))).toList(),
              onChanged: (value) => setState(() => _vehicle = value ?? 'SUV'),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _budget, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('budgetPerSeat'), prefixText: 'PKR '), validator: _required),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.notifications_active_rounded), label: Text(context.tr('notifyMatchingTour'))),
            const SizedBox(height: 10),
            Text(context.tr('interestPrivacyMessage'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
          ],
        ),
      );

  String? _required(String? value) => value == null || value.trim().isEmpty ? context.tr('required') : null;

  Future<void> _pickDate(bool start) async {
    final initial = start ? _from : _to;
    final value = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (value == null) return;
    setState(() {
      if (start) {
        _from = value;
        if (_to.isBefore(_from)) _to = _from.add(const Duration(days: 2));
      } else {
        _to = value;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final interest = TourInterest(
      id: 'TI-${DateTime.now().millisecondsSinceEpoch}',
      destination: _destination.text.trim(),
      pickupCity: _pickup.text.trim(),
      dateFrom: _from,
      dateTo: _to,
      persons: _persons,
      budgetPerSeat: int.tryParse(_budget.text) ?? 5000,
      partyType: _party,
      vehiclePreference: _vehicle,
    );
    AppControllerScope.of(context).addTourInterest(interest);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 52),
        title: Text(context.tr('tourInterestRegistered')),
        content: Text(context.tr('tourInterestSuccessMessage')),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('done')))],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()));
}

class _TourInfo extends StatelessWidget {
  const _TourInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [Icon(icon, size: 17, color: AppColors.primaryDark), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)))]));
}

class _FareBox extends StatelessWidget {
  const _FareBox({required this.label, required this.amount});
  final String label;
  final int amount;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text('PKR ${NumberFormat('#,###').format(amount)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 14))]));
}

class _PassengerCount extends StatelessWidget {
  const _PassengerCount({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Column(children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(height: 5), Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10))]);
}

class _SafetyLine extends StatelessWidget {
  const _SafetyLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 17), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)))]));
}

class _InterestHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PremiumCard(color: const Color(0xFFFFF8E5), child: Row(children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: .2), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8A5B00))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('cannotFindTour'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 4), Text(context.tr('registerAndNotify'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35))]))]));
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PremiumCard(onTap: onTap, padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Row(children: [const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primaryDark), const SizedBox(width: 7), Text(DateFormat('dd MMM yyyy').format(value), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))]) ]));
}

class _PersonCounter extends StatelessWidget {
  const _PersonCounter({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [const Icon(Icons.people_alt_rounded, color: AppColors.primaryDark), const SizedBox(width: 10), Expanded(child: Text(context.tr('numberOfPersons'), style: const TextStyle(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: value > 1 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded)), SizedBox(width: 38, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))), IconButton.filledTonal(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_rounded))]);
}
