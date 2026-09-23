import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';
import '../customer/package_detail_screen.dart';

class DriverTourismPackagesScreen extends StatelessWidget {
  const DriverTourismPackagesScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        Row(
          children: [
            Expanded(child: FilledButton.icon(onPressed: () => onNavigate('createPackage'), icon: const Icon(Icons.add_rounded), label: Text(context.tr('createPackage')))),
            const SizedBox(width: 9),
            Expanded(child: OutlinedButton.icon(onPressed: () => onNavigate('packageBookings'), icon: const Icon(Icons.confirmation_number_rounded), label: const Text('Bookings'))),
          ],
        ),
        const SizedBox(height: 14),
        PremiumCard(
          color: const Color(0xFFF1FAF6),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.success),
              SizedBox(width: 10),
              Expanded(child: Text('Packages remain private until admin approval. Route and vehicle suitability are checked before activation.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...controller.driverPackages.map(
          (package) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PremiumCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(23)), child: Image.asset(package.image, height: 165, width: double.infinity, fit: BoxFit.cover)),
                      Positioned(top: 12, left: 12, child: StatusPill(label: package.status, color: _packageColor(package.status))),
                      Positioned(top: 12, right: 12, child: StatusPill(label: '${package.safetyScore}/100 safety', color: AppColors.success)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(package.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text(package.route, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _PriceTile(label: 'Per seat', value: 'PKR ${package.pricePerSeat ?? package.price}')),
                            const SizedBox(width: 8),
                            Expanded(child: _PriceTile(label: 'Whole vehicle', value: 'PKR ${package.wholeVehiclePrice ?? package.price}')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            StatusPill(label: '${package.availableSeats ?? package.maxGuests} seats available', color: AppColors.secondary),
                            if (package.familyOnly) const StatusPill(label: 'Family only', color: AppColors.primary),
                            if (package.womenOnly) const StatusPill(label: 'Women only', color: Color(0xFF7C3AED)),
                            StatusPill(label: package.vehicle, color: AppColors.info),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Row(children: [Expanded(child: _MiniMetric(label: 'Views', value: '248')), SizedBox(width: 8), Expanded(child: _MiniMetric(label: 'Offers', value: '12')), SizedBox(width: 8), Expanded(child: _MiniMetric(label: 'Bookings', value: '5'))]),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(package: package))), child: const Text('Preview'))),
                            const SizedBox(width: 8),
                            Expanded(child: FilledButton.tonal(onPressed: package.status == 'Pending' ? null : () => controller.togglePackage(package.id), child: Text(package.status == 'Active' ? 'Pause' : 'Activate'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _packageColor(String status) {
    if (status == 'Active') return AppColors.success;
    if (status == 'Pending') return AppColors.warning;
    if (status == 'Paused') return AppColors.muted;
    return AppColors.info;
  }
}

class AdvancedCreatePackageScreen extends StatefulWidget {
  const AdvancedCreatePackageScreen({super.key});

  @override
  State<AdvancedCreatePackageScreen> createState() => _AdvancedCreatePackageScreenState();
}

class _AdvancedCreatePackageScreenState extends State<AdvancedCreatePackageScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Muzaffarabad to Neelum Family Tour');
  final _start = TextEditingController(text: 'Ghari Pan, Muzaffarabad');
  final _destination = TextEditingController(text: 'Keran and Sharda, Neelum Valley');
  final _stops = TextEditingController(text: 'Kohala viewpoint · Athmuqam · Upper Neelum');
  final _departureDate = TextEditingController(text: '15 Aug 2026');
  final _departureTime = TextEditingController(text: '7:00 AM');
  final _returnDate = TextEditingController(text: '18 Aug 2026');
  final _seatPrice = TextEditingController(text: '12000');
  final _wholePrice = TextEditingController(text: '62000');
  final _luggage = TextEditingController(text: '1 medium bag per passenger');
  final _description = TextEditingController(text: 'A safe, flexible family tour with verified passengers, scenic stops and complete route guidance.');
  final _cancellation = TextEditingController(text: 'Free cancellation up to 24 hours before departure.');
  final _itinerary = <String>['Day 1: Muzaffarabad to Keran', 'Day 2: Sharda and Upper Neelum', 'Day 3: Return via Muzaffarabad'];

  int _days = 3;
  int _nights = 2;
  int _seats = 6;
  String _vehicle = 'Honda BR-V 2021';
  String _passengerPolicy = 'Verified family / group';
  bool _allowOffers = true;
  bool _familyOnly = true;
  bool _womenOnly = false;
  bool _fuel = true;
  bool _tolls = true;
  bool _hotel = false;
  bool _meals = false;
  bool _guide = false;
  bool _jeepTransfer = false;
  bool _driverStay = true;
  bool _routeRequires4x4 = false;

  @override
  void dispose() {
    for (final controller in [_title, _start, _destination, _stops, _departureDate, _departureTime, _returnDate, _seatPrice, _wholePrice, _luggage, _description, _cancellation]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final approvedVehicles = controller.vehicles.where((item) => item.status == VerificationStatus.verified).toList();
    if (approvedVehicles.isNotEmpty && !approvedVehicles.any((item) => '${item.make} ${item.model} ${item.year}' == _vehicle)) {
      _vehicle = '${approvedVehicles.first.make} ${approvedVehicles.first.model} ${approvedVehicles.first.year}';
    }
    final selectedVehicle = approvedVehicles.isEmpty ? null : approvedVehicles.firstWhere((item) => '${item.make} ${item.model} ${item.year}' == _vehicle, orElse: () => approvedVehicles.first);
    final suitable = !_routeRequires4x4 || (selectedVehicle?.mountainReady ?? false);

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
        children: [
          UploadTile(label: 'Package cover image', uploaded: true, icon: Icons.image_rounded, onTap: () => _notice('Dummy cover image selected.')),
          const SizedBox(height: 12),
          TextFormField(controller: _title, decoration: InputDecoration(labelText: context.tr('packageTitle')), validator: _required),
          const SizedBox(height: 12),
          TextFormField(controller: _start, decoration: const InputDecoration(labelText: 'Starting city / pickup point', prefixIcon: Icon(Icons.trip_origin_rounded)), validator: _required),
          const SizedBox(height: 12),
          TextFormField(controller: _destination, decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.location_on_rounded)), validator: _required),
          const SizedBox(height: 12),
          TextFormField(controller: _stops, maxLines: 2, decoration: const InputDecoration(labelText: 'Intermediate stops', prefixIcon: Icon(Icons.alt_route_rounded))),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextFormField(controller: _departureDate, decoration: const InputDecoration(labelText: 'Departure date'))), const SizedBox(width: 8), Expanded(child: TextFormField(controller: _departureTime, decoration: const InputDecoration(labelText: 'Departure time')))]),
          const SizedBox(height: 12),
          TextFormField(controller: _returnDate, decoration: const InputDecoration(labelText: 'Return date')),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _CounterField(label: 'Days', value: _days, onChanged: (value) => setState(() => _days = value))), const SizedBox(width: 8), Expanded(child: _CounterField(label: 'Nights', value: _nights, onChanged: (value) => setState(() => _nights = value))), const SizedBox(width: 8), Expanded(child: _CounterField(label: 'Seats', value: _seats, onChanged: (value) => setState(() => _seats = value)))]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: approvedVehicles.isEmpty ? null : _vehicle,
            decoration: const InputDecoration(labelText: 'Approved vehicle', prefixIcon: Icon(Icons.directions_car_filled_rounded)),
            hint: const Text('Register and approve a vehicle first'),
            items: approvedVehicles.map((item) => DropdownMenuItem(value: '${item.make} ${item.model} ${item.year}', child: Text('${item.make} ${item.model} · ${item.registration}'))).toList(),
            onChanged: (value) => setState(() => _vehicle = value!),
          ),
          const SizedBox(height: 10),
          PremiumCard(
            color: suitable ? const Color(0xFFF1FAF6) : const Color(0xFFFFF0F0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(suitable ? Icons.verified_rounded : Icons.warning_amber_rounded, color: suitable ? AppColors.success : AppColors.danger), const SizedBox(width: 10), Expanded(child: Text(suitable ? 'Selected vehicle is suitable for this package configuration.' : 'This route requires a mountain-ready 4×4 vehicle with first-aid kit and spare tyre.', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)))]),
          ),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextFormField(controller: _seatPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price per seat', prefixText: 'PKR '), validator: _money)), const SizedBox(width: 8), Expanded(child: TextFormField(controller: _wholePrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Whole vehicle price', prefixText: 'PKR '), validator: _money))]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _passengerPolicy, decoration: const InputDecoration(labelText: 'Passenger policy'), items: const ['Verified family / group', 'Family only', 'Women only', 'Male only', 'Couples and families', 'Verified passengers only'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => _passengerPolicy = value!)),
          const SizedBox(height: 12),
          TextFormField(controller: _luggage, decoration: const InputDecoration(labelText: 'Luggage allowance', prefixIcon: Icon(Icons.luggage_rounded))),
          const SizedBox(height: 12),
          PremiumCard(
            child: Column(
              children: [
                SwitchListTile(contentPadding: EdgeInsets.zero, value: _allowOffers, onChanged: (value) => setState(() => _allowOffers = value), title: const Text('Allow customer price offers', style: TextStyle(fontWeight: FontWeight.w900))),
                const Divider(),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: _familyOnly, onChanged: (value) => setState(() => _familyOnly = value), title: const Text('Family-only package', style: TextStyle(fontWeight: FontWeight.w900))),
                const Divider(),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: _womenOnly, onChanged: (value) => setState(() => _womenOnly = value), title: const Text('Women-only departure', style: TextStyle(fontWeight: FontWeight.w900))),
                const Divider(),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: _routeRequires4x4, onChanged: (value) => setState(() => _routeRequires4x4 = value), title: const Text('Route requires mountain-ready 4×4', style: TextStyle(fontWeight: FontWeight.w900))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionHeader(title: 'Package inclusions'),
          const SizedBox(height: 8),
          PremiumCard(
            child: Column(
              children: [
                _InclusionSwitch(label: 'Fuel included', value: _fuel, onChanged: (value) => setState(() => _fuel = value)),
                _InclusionSwitch(label: 'Tolls included', value: _tolls, onChanged: (value) => setState(() => _tolls = value)),
                _InclusionSwitch(label: 'Hotel included', value: _hotel, onChanged: (value) => setState(() => _hotel = value)),
                _InclusionSwitch(label: 'Meals included', value: _meals, onChanged: (value) => setState(() => _meals = value)),
                _InclusionSwitch(label: 'Local guide included', value: _guide, onChanged: (value) => setState(() => _guide = value)),
                _InclusionSwitch(label: 'Jeep transfer included', value: _jeepTransfer, onChanged: (value) => setState(() => _jeepTransfer = value)),
                _InclusionSwitch(label: 'Driver accommodation included', value: _driverStay, onChanged: (value) => setState(() => _driverStay = value), last: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _description, maxLines: 4, decoration: const InputDecoration(labelText: 'Package description'), validator: _required),
          const SizedBox(height: 12),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Detailed itinerary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                ..._itinerary.asMap().entries.map((entry) => ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(radius: 15, child: Text('${entry.key + 1}')), title: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: IconButton(onPressed: () => _editItinerary(entry.key), icon: const Icon(Icons.edit_outlined)))),
                OutlinedButton.icon(onPressed: _addItinerary, icon: const Icon(Icons.add_rounded), label: const Text('Add itinerary day')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _cancellation, maxLines: 3, decoration: const InputDecoration(labelText: 'Cancellation policy')),
          const SizedBox(height: 16),
          Row(children: [Expanded(child: OutlinedButton(onPressed: () => _notice('Package saved as a private draft.'), child: const Text('Save draft'))), const SizedBox(width: 9), Expanded(flex: 2, child: FilledButton(onPressed: suitable && approvedVehicles.isNotEmpty ? _submit : null, child: const Text('Submit for approval')))]),
        ],
      ),
    );
  }

  String? _required(String? value) => (value ?? '').trim().isEmpty ? context.tr('required') : null;
  String? _money(String? value) => int.tryParse((value ?? '').trim()) == null ? 'Enter a valid amount' : null;

  void _addItinerary() {
    setState(() => _itinerary.add('Day ${_itinerary.length + 1}: Add route and activities'));
  }

  void _editItinerary(int index) {
    final field = TextEditingController(text: _itinerary[index]);
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Edit itinerary'), content: TextField(controller: field, maxLines: 3), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () { setState(() => _itinerary[index] = field.text.trim()); Navigator.pop(dialogContext); }, child: const Text('Save'))]));
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final inclusions = <String>[
      'Verified driver and approved vehicle',
      if (_fuel) 'Fuel',
      if (_tolls) 'Tolls',
      if (_hotel) 'Hotel',
      if (_meals) 'Meals',
      if (_guide) 'Local guide',
      if (_jeepTransfer) 'Jeep transfer',
      if (_driverStay) 'Driver accommodation',
    ];
    final exclusions = <String>[
      if (!_hotel) 'Hotel accommodation',
      if (!_meals) 'Meals',
      if (!_guide) 'Local guide',
      if (!_jeepTransfer) 'Jeep transfer',
    ];
    AppControllerScope.of(context).addPackage(
      TourPackage(
        id: 'P-${DateTime.now().millisecondsSinceEpoch}',
        title: _title.text.trim(),
        route: '${_start.text.trim()} · ${_stops.text.trim()} · ${_destination.text.trim()}',
        days: _days,
        price: int.parse(_wholePrice.text),
        image: 'assets/images/neelum.png',
        driver: 'Shahzad Ahmad',
        rating: 4.9,
        maxGuests: _seats,
        vehicle: _vehicle,
        description: _description.text.trim(),
        inclusions: inclusions,
        exclusions: exclusions,
        itinerary: List<String>.from(_itinerary),
        allowOffers: _allowOffers,
        status: 'Pending',
        pricePerSeat: int.parse(_seatPrice.text),
        wholeVehiclePrice: int.parse(_wholePrice.text),
        availableSeats: _seats,
        departureDate: _departureDate.text.trim(),
        departureTime: _departureTime.text.trim(),
        returnDate: _returnDate.text.trim(),
        pickupPoint: _start.text.trim(),
        familyOnly: _familyOnly,
        womenOnly: _womenOnly,
        passengerPolicy: _passengerPolicy,
        luggageAllowance: _luggage.text.trim(),
        cancellationPolicy: _cancellation.text.trim(),
        fuelIncluded: _fuel,
        tollIncluded: _tolls,
        hotelIncluded: _hotel,
        mealsIncluded: _meals,
        guideIncluded: _guide,
        jeepTransferIncluded: _jeepTransfer,
        driverAccommodationIncluded: _driverStay,
        routeRequiresFourByFour: _routeRequires4x4,
        safetyScore: 94,
      ),
    );
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(icon: const Icon(Icons.fact_check_rounded, color: AppColors.success, size: 52), title: const Text('Package submitted'), content: const Text('Your package is private and marked Pending until an administrator reviews the route, vehicle, price and safety information.'), actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))]));
  }

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]));
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10))]));
}

class _CounterField extends StatelessWidget {
  const _CounterField({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(15)), child: Column(children: [Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: value > 1 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded, size: 17)), Text('$value', style: const TextStyle(fontWeight: FontWeight.w900)), IconButton(onPressed: value < 30 ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_rounded, size: 17))])])) ;
}

class _InclusionSwitch extends StatelessWidget {
  const _InclusionSwitch({required this.label, required this.value, required this.onChanged, this.last = false});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) => Column(children: [SwitchListTile(contentPadding: EdgeInsets.zero, value: value, onChanged: onChanged, title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))), if (!last) const Divider(height: 1)]);
}
