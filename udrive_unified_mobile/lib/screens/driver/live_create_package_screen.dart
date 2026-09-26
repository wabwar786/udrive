import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_controls.dart';
import '../../core/widgets/ud_kit.dart';

/// D-31 — the form that creates a tour package.
///
/// Always pushed, never rendered by the shell. It used to be both: the drawer
/// routed to it *and* D-30's button pushed it, and because it ships its own
/// `Scaffold` the drawer route drew a second bar on top of the shell's. The
/// drawer now lands on the packages list and pushes this, so there is one path
/// and one bar.
class LiveCreatePackageScreen extends StatefulWidget {
  const LiveCreatePackageScreen({super.key});
  @override
  State<LiveCreatePackageScreen> createState() =>
      _LiveCreatePackageScreenState();
}

class _LiveCreatePackageScreenState extends State<LiveCreatePackageScreen> {
  static const destinations = <String, String>{
    '10000000-0000-0000-0000-000000000001': 'Muzaffarabad',
    '10000000-0000-0000-0000-000000000002': 'Neelum Valley',
    '10000000-0000-0000-0000-000000000003': 'Sharda',
    '10000000-0000-0000-0000-000000000004': 'Rawalakot',
    '10000000-0000-0000-0000-000000000005': 'Banjosa Lake',
    '10000000-0000-0000-0000-000000000006': 'Pir Chinasi',
  };

  final _form = GlobalKey<FormState>();
  final _title =
      TextEditingController(text: '3-Day Neelum Valley Family Tour');
  final _start = TextEditingController(text: 'Muzaffarabad');
  final _pickup = TextEditingController(text: 'Ghari Pan Pickup Point');
  final _seatPrice = TextEditingController(text: '12000');
  final _vehiclePrice = TextEditingController(text: '95000');
  final _description = TextEditingController(
      text: 'A safe family tourism package with a verified local Driver.');
  final _itinerary = TextEditingController(
      text: 'Day 1: Muzaffarabad to Keran\n'
          'Day 2: Sharda and local sightseeing\n'
          'Day 3: Return to Muzaffarabad');

  String? _vehicleId;
  String _destinationId = destinations.keys.elementAt(1);
  DateTime _departure = DateTime.now().add(const Duration(days: 14));
  DateTime _return = DateTime.now().add(const Duration(days: 17));
  int _seats = 7;
  bool _family = true;
  bool _women = false;
  bool _offers = true;
  bool _fuel = true;
  bool _toll = true;
  bool _hotel = false;
  bool _meals = false;
  bool _guide = false;
  bool _jeep = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _title,
      _start,
      _pickup,
      _seatPrice,
      _vehiclePrice,
      _description,
      _itinerary
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = AppControllerScope.of(context)
        .liveVehicles
        .where((v) => v.status == 'Verified')
        .toList();
    _vehicleId ??= vehicles.isEmpty ? null : vehicles.first.id;

    final selected = vehicles.where((v) => v.id == _vehicleId).toList();
    final vehicleLabel = selected.isEmpty
        ? 'Select a vehicle'
        : '${selected.first.make} ${selected.first.model} · '
            '${selected.first.registrationNumber}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: 'Create live package',
        onBack: () => Navigator.pop(context),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
          children: [
            UdBanner(
              tone: UdTone.info,
              icon: Icons.admin_panel_settings_rounded,
              text: 'Package remains private until Admin approves route, '
                  'vehicle, pricing and safety readiness.',
            ),
            const SizedBox(height: 18),

            UdTextField(
              controller: _title,
              label: 'Package title',
              icon: Icons.luggage_rounded,
              validator: _required,
            ),
            const SizedBox(height: 14),

            // Both dropdowns are pickers now. A `DropdownButtonFormField`
            // opens a Material menu over the field in Material's own colours,
            // and this form had two of them.
            const UdLabel('Destination'),
            const SizedBox(height: 8),
            _PickerField(
              icon: Icons.landscape_rounded,
              value: destinations[_destinationId] ?? 'Select',
              onTap: _busy ? null : _pickDestination,
            ),
            const SizedBox(height: 14),

            if (vehicles.isEmpty)
              UdBanner(
                tone: UdTone.warn,
                icon: Icons.directions_car_outlined,
                text: 'No verified vehicle is available. Admin must verify a '
                    'vehicle first.',
              )
            else ...[
              const UdLabel('Verified vehicle'),
              const SizedBox(height: 8),
              _PickerField(
                icon: Icons.directions_car_rounded,
                value: vehicleLabel,
                onTap: _busy ? null : () => _pickVehicle(vehicles),
              ),
            ],
            const SizedBox(height: 14),

            UdTextField(
              controller: _start,
              label: 'Starting city',
              icon: Icons.location_city_rounded,
              validator: _required,
            ),
            const SizedBox(height: 14),
            UdTextField(
              controller: _pickup,
              label: 'Pickup point',
              labelSuffix: '(required)',
              icon: Icons.trip_origin_rounded,
              validator: _required,
            ),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Departure',
                    date: _departure,
                    onTap: () => _pick(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Return',
                    date: _return,
                    onTap: () => _pick(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            UdStepper(
              label: 'Total passenger seats',
              value: _seats,
              min: 1,
              max: 60,
              onChanged: (v) => setState(() => _seats = v),
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: UdTextField(
                    controller: _seatPrice,
                    label: 'Price per seat',
                    labelSuffix: 'PKR',
                    keyboardType: TextInputType.number,
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UdTextField(
                    controller: _vehiclePrice,
                    label: 'Whole vehicle',
                    labelSuffix: 'PKR',
                    keyboardType: TextInputType.number,
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            UdTextField(
              controller: _description,
              label: 'Description',
              icon: Icons.description_rounded,
              minLines: 3,
              maxLines: 4,
            ),
            const SizedBox(height: 14),
            UdTextField(
              controller: _itinerary,
              label: 'Itinerary',
              labelSuffix: '— one item per line',
              icon: Icons.route_rounded,
              minLines: 4,
              maxLines: 7,
            ),
            const SizedBox(height: 20),

            UdListGroup(
              children: [
                _switch('Family-only departure', _family,
                    (v) => setState(() => _family = v)),
                _switch('Women-only departure', _women,
                    (v) => setState(() => _women = v)),
                _switch('Allow customer offers', _offers,
                    (v) => setState(() => _offers = v)),
              ],
            ),
            const SizedBox(height: 20),

            const UdSectionHeader(
              title: 'What the price includes',
              caption: 'tap to toggle',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _flag('Fuel', _fuel, (v) => setState(() => _fuel = v)),
                _flag('Toll', _toll, (v) => setState(() => _toll = v)),
                _flag('Hotel', _hotel, (v) => setState(() => _hotel = v)),
                _flag('Meals', _meals, (v) => setState(() => _meals = v)),
                _flag('Guide', _guide, (v) => setState(() => _guide = v)),
                _flag('Jeep transfer', _jeep, (v) => setState(() => _jeep = v)),
              ],
            ),
            const SizedBox(height: 24),

            UdButton.primary(
              label: 'Save live draft',
              icon: Icons.save_rounded,
              busy: _busy,
              onPressed: _busy || _vehicleId == null ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> changed) =>
      UdListRow(
        title: label,
        trailing:
            UdSwitch(value: value, onChanged: changed, semanticLabel: label),
      );

  Widget _flag(String label, bool value, ValueChanged<bool> changed) => UdChip(
        label: label,
        selected: value,
        icon: value ? Icons.check_rounded : null,
        onTap: () => changed(!value),
      );

  Future<void> _pickDestination() async {
    final picked = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Text('Destination',
                style: AppType.h2.copyWith(color: AppText.primary)),
            const SizedBox(height: 14),
            UdListGroup(
              children: [
                for (final entry in destinations.entries)
                  UdListRow(
                    title: entry.value,
                    onTap: () => Navigator.pop(sheetContext, entry.key),
                    trailing: entry.key == _destinationId
                        ? const Icon(Icons.check_rounded,
                            size: 22, color: AppColors.brandInk)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _destinationId = picked);
  }

  Future<void> _pickVehicle(List<dynamic> vehicles) async {
    final picked = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Text('Verified vehicle',
                style: AppType.h2.copyWith(color: AppText.primary)),
            const SizedBox(height: 14),
            UdListGroup(
              children: [
                for (final v in vehicles)
                  UdListRow(
                    title: '${v.make} ${v.model}',
                    subtitle: '${v.registrationNumber} · '
                        '${v.passengerCapacity} seats',
                    leading: const UdIconTile(
                        icon: Icons.directions_car_filled_rounded),
                    onTap: () => Navigator.pop(sheetContext, v.id as String),
                    trailing: v.id == _vehicleId
                        ? const Icon(Icons.check_rounded,
                            size: 22, color: AppColors.brandInk)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _vehicleId = picked);
  }

  Future<void> _pick(bool departure) async {
    final current = departure ? _departure : _return;
    final date = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 500)));
    if (date != null) {
      setState(() {
        if (departure) {
          _departure = DateTime(date.year, date.month, date.day, 7);
          if (_return.isBefore(_departure)) {
            _return = _departure.add(const Duration(days: 2));
          }
        } else {
          _return = DateTime(date.year, date.month, date.day, 18);
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final p =
          await AppControllerScope.of(context).createLiveDriverPackage({
        'vehicleId': _vehicleId,
        'destinationId': _destinationId,
        'title': _title.text.trim(),
        'startingCity': _start.text.trim(),
        'pickupPoint': _pickup.text.trim(),
        'departureAt': _departure.toUtc().toIso8601String(),
        'returnAt': _return.toUtc().toIso8601String(),
        'totalSeats': _seats,
        'pricePerSeat': double.parse(_seatPrice.text),
        'wholeVehiclePrice': double.parse(_vehiclePrice.text),
        'familyOnly': _family,
        'womenOnly': _women,
        'customerOffersAllowed': _offers,
        'description': _description.text.trim(),
        'cancellationPolicy':
            'Free cancellation before 48 hours. Admin-approved policy applies.',
        'passengerPolicy': _family
            ? 'Verified family passengers only'
            : 'Verified passengers only',
        'luggageAllowance': 'One standard bag per passenger',
        'routeStops': ['Kohala', 'Keran', 'Sharda'],
        'inclusions': [
          if (_fuel) 'Fuel',
          if (_toll) 'Toll',
          if (_hotel) 'Hotel',
          if (_meals) 'Meals',
          if (_guide) 'Local guide',
          if (_jeep) 'Jeep transfer'
        ],
        'exclusions': ['Personal expenses'],
        'itinerary': _itinerary.text
            .split('\n')
            .where((e) => e.trim().isNotEmpty)
            .toList(),
        'fuelIncluded': _fuel,
        'tollIncluded': _toll,
        'hotelIncluded': _hotel,
        'mealsIncluded': _meals,
        'guideIncluded': _guide,
        'jeepTransferIncluded': _jeep,
        'driverAccommodationIncluded': true
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Draft ${p.title} saved.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;
}

/// A field-shaped button that opens a sheet — 58px, same border and radius as
/// [UdTextField], so it lines up with the real fields around it.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(AppRadii.field),
          child: Container(
            height: AppSizes.field,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadii.all(AppRadii.field),
              border: Border.all(color: AppColors.borderStrong, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppText.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body.copyWith(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: AppText.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.expand_more_rounded,
                    size: 22, color: AppText.caption),
              ],
            ),
          ),
        ),
      );
}

/// Was an `InputDecorator` inside an `InkWell`, which carries Material's own
/// floating label and underline into a design that has neither.
class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          UdLabel(label),
          const SizedBox(height: 8),
          _PickerField(
            icon: Icons.calendar_month_rounded,
            value: DateFormat('d MMM yyyy').format(date),
            onTap: onTap,
          ),
        ],
      );
}
