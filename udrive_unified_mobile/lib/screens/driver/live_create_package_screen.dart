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
  /// The destinations, read from the catalogue the server actually holds.
  ///
  /// These six used to be written into the app:
  ///
  ///     '10000000-0000-0000-0000-000000000001': 'Muzaffarabad',
  ///     '10000000-0000-0000-0000-000000000002': 'Neelum Valley',
  ///     ...
  ///
  /// Not one of those ids exists. The live catalogue is keyed
  /// `11000000-...`, thirty-five destinations of it, so every package a Driver
  /// filled in here was posted against a destination the database had never
  /// heard of; the insert broke the foreign key and the Driver was handed a
  /// 409. Creating a tour package has therefore not worked at all — not
  /// sometimes, not for some routes, never — and nothing on the screen could
  /// hint at why, because the form looked perfectly filled in.
  ///
  /// Hard-coded ids cannot be right for longer than it takes an Admin to add a
  /// destination, which is the whole point of the Admin having that screen. So
  /// the list is fetched, and a Driver sees every route the Admin has
  /// published rather than six that were true once.
  List<_Destination> _destinations = const [];
  bool _loadingDestinations = true;
  String? _destinationsError;

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
  String? _destinationId;
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
  bool _requestedDestinations = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once. didChangeDependencies runs again on every inherited-widget change,
    // and this screen reads AppControllerScope, which notifies often.
    if (_requestedDestinations) return;
    _requestedDestinations = true;
    _loadDestinations();
  }

  String? _selectedDestinationName() {
    for (final destination in _destinations) {
      if (destination.id == _destinationId) return destination.name;
    }
    return null;
  }

  Future<void> _loadDestinations() async {
    setState(() {
      _loadingDestinations = true;
      _destinationsError = null;
    });
    try {
      final controller = AppControllerScope.of(context);
      final response = await controller.apiClient.getJson(
        '/api/v1/catalog/destinations'
        '?language=${controller.locale.languageCode}',
        authenticated: false,
      );
      final raw = response['data'] as List? ?? const [];
      final list = raw
          .whereType<Map>()
          .map((e) => _Destination(
                id: '${e['id']}',
                name: '${e['name']}',
                district: e['district'] == null ? null : '${e['district']}',
              ))
          .where((d) => d.id.isNotEmpty && d.id != 'null')
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _destinations = list;
        // Keep whatever the Driver already picked if it survived the reload.
        if (!list.any((d) => d.id == _destinationId)) {
          _destinationId = list.isEmpty ? null : list.first.id;
        }
        _loadingDestinations = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _destinationsError = '$error'.replaceFirst('Exception: ', '');
        _loadingDestinations = false;
      });
    }
  }

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
    // 'Verified' or 'Approved', either case.
    //
    // The server treats both as a usable vehicle — every check in
    // TripOperationsService reads `lower(v.status) in ('verified','approved')`
    // — but this screen matched the one exact string 'Verified'. A Driver
    // whose vehicle an Admin had approved saw "No verified vehicle is
    // available", with the Save button dead and nothing to do about it.
    final vehicles = AppControllerScope.of(context)
        .liveVehicles
        .where((v) => const {'verified', 'approved'}
            .contains('${v.status}'.toLowerCase()))
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
              value: _loadingDestinations
                  ? 'Loading routes…'
                  : _destinationsError != null
                      ? 'Could not load routes'
                      : _selectedDestinationName() ?? 'Select',
              onTap: _busy || _loadingDestinations || _destinations.isEmpty
                  ? null
                  : _pickDestination,
            ),
            if (_destinationsError != null) ...[
              const SizedBox(height: 10),
              UdBanner(
                tone: UdTone.warn,
                icon: Icons.wifi_off_rounded,
                text: 'Routes could not be loaded. Tap to try again. '
                    '$_destinationsError',
                onTap: _loadDestinations,
              ),
            ] else if (!_loadingDestinations && _destinations.isEmpty)
              const UdBanner(
                tone: UdTone.warn,
                icon: Icons.landscape_outlined,
                text: 'No tour destination has been published yet. Admin must '
                    'add a destination before a package can be created.',
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
              onPressed: _busy || _vehicleId == null || _destinationId == null
                  ? null
                  : _save,
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
                for (final destination in _destinations)
                  UdListRow(
                    title: destination.name,
                    subtitle: destination.district,
                    onTap: () => Navigator.pop(sheetContext, destination.id),
                    trailing: destination.id == _destinationId
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
    final destinationId = _destinationId;
    if (destinationId == null) return;
    setState(() => _busy = true);
    try {
      final p =
          await AppControllerScope.of(context).createLiveDriverPackage({
        'vehicleId': _vehicleId,
        'destinationId': destinationId,
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

/// One row of the destination catalogue, as the server sent it.
///
/// The id is carried through untouched: it is the only thing the server
/// matches on, and the last time this screen invented one, no package could be
/// created at all.
class _Destination {
  const _Destination({
    required this.id,
    required this.name,
    this.district,
  });

  final String id;
  final String name;
  final String? district;
}
