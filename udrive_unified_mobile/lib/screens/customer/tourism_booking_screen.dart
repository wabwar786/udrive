import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import '../../models/booking_models.dart';
import 'driver_offers_screen.dart';
import 'live_packages_screen.dart';

class TourismBookingScreen extends StatefulWidget {
  const TourismBookingScreen({this.initialType, this.initialDestination, super.key});
  final BookingType? initialType;
  final String? initialDestination;

  @override
  State<TourismBookingScreen> createState() => _TourismBookingScreenState();
}

class _TourismBookingScreenState extends State<TourismBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController();
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
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _bookingType = widget.initialType ?? BookingType.perSeat;
    _destination = TextEditingController(text: widget.initialDestination ?? '');
    _destination.addListener(_refreshSearchResults);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AppControllerScope.of(context).refreshPhase9Marketplace();
    });
  }

  void _refreshSearchResults() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pickup.dispose();
    _destination
      ..removeListener(_refreshSearchResults)
      ..dispose();
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

  Widget _routeStep() {
    final controller = AppControllerScope.of(context);
    final matches = _matchingVehicles(controller.liveMarketplacePackages);
    final destinationEntered = _destination.text.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        _StepIntro(
          icon: Icons.route_rounded,
          title: context.tr('whereTo'),
          subtitle: 'Enter your destination and date. Available vehicles will appear instantly.',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .035),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              TextFormField(
                controller: _pickup,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.trip_origin_rounded),
                  labelText: context.tr('pickup'),
                  hintText: 'Your pickup city or point',
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _destination,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.location_on_rounded),
                  labelText: context.tr('destination'),
                  hintText: 'e.g. Neelum Valley, Sharda, Arang Kel',
                  suffixIcon: _destination.text.trim().isEmpty
                      ? null
                      : IconButton(
                          onPressed: _destination.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _CompactDateField(
                      label: context.tr('departureDate'),
                      value: DateFormat('dd MMM yyyy').format(_departureDate),
                      icon: Icons.calendar_month_rounded,
                      onTap: _pickDepartureDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CompactDateField(
                      label: context.tr('departureTime'),
                      value: _departureTime.format(context),
                      icon: Icons.schedule_rounded,
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available vehicles',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap a vehicle to view location and reserve seats.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (destinationEntered)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F6F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${matches.length} found',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (controller.marketplaceBusy && controller.liveMarketplacePackages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!destinationEntered)
          const _VehicleSearchHint(
            icon: Icons.travel_explore_rounded,
            title: 'Type your destination',
            message: 'Vehicles will be filtered automatically by destination and departure date.',
          )
        else if (matches.isEmpty)
          _VehicleSearchHint(
            icon: Icons.event_busy_rounded,
            title: 'No vehicle found for this date',
            message: 'Change the date or continue to request a private vehicle from verified Drivers.',
            actionLabel: 'Show next available date',
            onAction: _showNextAvailableDate,
          )
        else
          ...matches.map(
            (package) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _SearchVehicleCard(
                package: package,
                onTap: () => _openScheduledVehicle(package),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FA),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'No suitable scheduled vehicle? Continue below to request a private or shared ride and receive Driver offers.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.border),
          ),
          value: _returnTrip,
          onChanged: (value) => setState(() {
            _returnTrip = value;
            _returnDate = value ? _departureDate.add(const Duration(days: 2)) : null;
          }),
          title: Text(
            context.tr('returnTrip'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            context.tr('returnTripHelp'),
            style: const TextStyle(fontSize: 11),
          ),
        ),
        if (_returnTrip) ...[
          const SizedBox(height: 10),
          _DateCard(
            label: context.tr('returnDate'),
            value: DateFormat('dd MMM yyyy').format(_returnDate!),
            icon: Icons.event_repeat_rounded,
            onTap: _pickReturnDate,
          ),
        ],
      ],
    );
  }

  List<LiveTourPackage> _matchingVehicles(List<LiveTourPackage> source) {
    final destination = _destination.text.trim().toLowerCase();
    if (destination.isEmpty) return const [];
    final target = DateUtils.dateOnly(_departureDate);
    final matches = source.where((package) {
      final packageDate = DateUtils.dateOnly(package.departureAt);
      return package.destination.toLowerCase().contains(destination) &&
          packageDate == target &&
          package.bookableSeats > 0;
    }).toList()
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return matches.take(10).toList();
  }

  Future<void> _showNextAvailableDate() async {
    final destination = _destination.text.trim().toLowerCase();
    final packages = AppControllerScope.of(context).liveMarketplacePackages
        .where(
          (package) =>
              package.destination.toLowerCase().contains(destination) &&
              package.bookableSeats > 0 &&
              package.departureAt.isAfter(DateTime.now()),
        )
        .toList()
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    if (packages.isEmpty) return;
    setState(() => _departureDate = DateUtils.dateOnly(packages.first.departureAt));
  }

  Future<void> _openScheduledVehicle(LiveTourPackage package) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePackageDetailScreen(package: package),
      ),
    );
    if (mounted) {
      await AppControllerScope.of(context).refreshPhase9Marketplace();
    }
  }

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
                const Divider(height: 24),
                _PriceLine(label: context.tr('estimatedTotal'), value: _estimate, bold: true),
                const SizedBox(height: 8),
                Text(
                  _bookingType == BookingType.perSeat
                      ? 'Fuel, toll and uDrive charges are included in the seat fare.'
                      : 'Toll charges, if applicable, will be paid by the customer at actual cost.',
                  style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w800),
                ),
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
                onPressed: _submitting ? null : (_step == 3 ? _submit : _next),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_step == 3 ? context.tr('findVerifiedDrivers') : context.tr('continue')),
              ),
            ),
          ],
        ),
      );

  void _next() {
    if (_step == 0 && !_formKey.currentState!.validate()) return;
    setState(() => _step++);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final departure = DateTime(
        _departureDate.year,
        _departureDate.month,
        _departureDate.day,
        _departureTime.hour,
        _departureTime.minute,
      );
      final returnAt = _returnDate == null
          ? null
          : DateTime(
              _returnDate!.year,
              _returnDate!.month,
              _returnDate!.day,
              _departureTime.hour,
              _departureTime.minute,
            );
      final pickupCoordinates = _coordinatesFor(_pickup.text, pickup: true);
      final destinationCoordinates = _coordinatesFor(_destination.text);
      final total = _estimate;
      final controller = AppControllerScope.of(context);
      final request = await controller.createLiveRideRequest({
        'pickupLabel': _pickup.text.trim(),
        'destinationLabel': _destination.text.trim(),
        'pickupLatitude': pickupCoordinates.$1,
        'pickupLongitude': pickupCoordinates.$2,
        'destinationLatitude': destinationCoordinates.$1,
        'destinationLongitude': destinationCoordinates.$2,
        'pickupAt': departure.toUtc().toIso8601String(),
        'returnAt': returnAt?.toUtc().toIso8601String(),
        'bookingType': _bookingType == BookingType.perSeat ? 'PerSeat' : 'WholeVehicle',
        'seatsRequested': _bookingType == BookingType.wholeVehicle ? _vehicle.seats : _travellers,
        'adults': _adults,
        'children': _children,
        'luggageCount': _luggage,
        'customerOffer': total,
        'vehicleCategory': _vehicle.name,
        'partyType': switch (_partyType) {
          TripPartyType.family => 'Family',
          TripPartyType.womenOnly => 'WomenOnly',
          TripPartyType.group => 'Group',
          TripPartyType.maleOnly => 'MaleOnly',
          TripPartyType.couple => 'Couple',
          _ => 'Individual',
        },
        'familyOnly': _familyOnly,
        'womenOnly': _femalePreference || _partyType == TripPartyType.womenOnly,
        'notes': _notes.text.trim(),
      });

      final localBooking = AdvanceBooking(
        id: request.id,
        pickup: _pickup.text.trim(),
        destination: _destination.text.trim(),
        departureDate: _departureDate,
        departureTime: _departureTime,
        bookingType: _bookingType,
        adults: _adults,
        children: _children,
        luggage: _luggage,
        vehicle: _vehicle.name,
        estimatedTotal: total,
        partyType: _partyType,
        returnDate: _returnDate,
        notes: _notes.text.trim(),
      );
      controller.addAdvanceBooking(localBooking);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverOffersScreen(
            rideRequestId: request.id,
            pickup: request.pickupLabel,
            destination: request.destinationLabel,
            customerOffer: request.customerOffer.round(),
            vehicleName: request.vehicleCategory,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  (double, double) _coordinatesFor(String label, {bool pickup = false}) {
    final value = label.toLowerCase();
    if (value.contains('sharda')) return (34.7932, 74.1832);
    if (value.contains('keran') || value.contains('neelum')) return (34.6500, 73.9500);
    if (value.contains('rawalakot')) return (33.8578, 73.7604);
    if (value.contains('banjosa')) return (33.8098, 73.8162);
    if (value.contains('pir chinasi')) return (34.3870, 73.5335);
    if (value.contains('islamabad')) return (33.6844, 73.0479);
    return pickup ? (34.3700, 73.4700) : (34.6500, 73.9500);
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


class _CompactDateField extends StatelessWidget {
  const _CompactDateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9F8),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryDark, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _VehicleSearchHint extends StatelessWidget {
  const _VehicleSearchHint({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 34, color: AppColors.muted),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      );
}

class _SearchVehicleCard extends StatelessWidget {
  const _SearchVehicleCard({required this.package, required this.onTap});

  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = package.coverImageUrl?.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: image != null && image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFFE9F4F0),
                            child: Icon(Icons.directions_bus_rounded, color: AppColors.primaryDark),
                          ),
                        )
                      : const ColoredBox(
                          color: Color(0xFFE9F4F0),
                          child: Icon(Icons.directions_bus_rounded, color: AppColors.primaryDark),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.vehicle.isEmpty ? package.title : package.vehicle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${package.startingCity} → ${package.destination}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${DateFormat('hh:mm a').format(package.departureAt)} · ${package.bookableSeats} seats free',
                      style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PKR ${NumberFormat('#,###').format(package.pricePerSeat)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  const Text('per seat', style: TextStyle(color: AppColors.muted, fontSize: 9)),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
