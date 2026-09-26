import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../models/auth_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/vehicles/vehicle_catalogue.dart';
import '../../data/models.dart';
import '../../models/booking_models.dart';
import 'driver_offers_screen.dart';
import 'live_packages_screen.dart';
import '../../core/permissions/location_access.dart';

/// Secondary copy, at the smallest size the design system allows.
///
/// This file used to set nine, nine and a half, eleven, eleven and a half and
/// twelve pixels by hand, in seventeen places. Nothing in v2 goes below 12.5,
/// and nine pixels on a phone in daylight is not small type — it is absent
/// type.
const _captionMuted = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppColors.muted,
  height: 1.35,
);

/// The same, one step down, for the tightest rows inside a card.
const _overlineMuted = TextStyle(
  fontSize: 12.5,
  fontWeight: FontWeight.w700,
  color: AppColors.muted,
);

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
  late final TextEditingController _customerOffer;
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
  VehicleCategory _vehicle = recommendedVehicleFor(3);
  bool _submitting = false;
  bool _locatingPickup = false;
  double? _pickupLatitude;
  double? _pickupLongitude;

  @override
  void initState() {
    super.initState();
    _bookingType = widget.initialType ?? BookingType.perSeat;
    _destination = TextEditingController(text: widget.initialDestination ?? '');
    // Empty on purpose. This field used to open pre-filled with a figure
    // derived from an invented baseFare, which meant most customers sent
    // back a number the app had written for them and called it their offer.
    _customerOffer = TextEditingController();
    _destination.addListener(_refreshSearchResults);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Marketplace loading must not block automatic pickup GPS detection.
      try {
        await AppControllerScope.of(context).refreshPhase9Marketplace();
      } catch (_) {
        // Customer can still continue with a private ride request.
      }
      if (!mounted) return;
      await _useCurrentLocation(silent: true);
      if (mounted) _syncRecommendedVehicle();
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
    _customerOffer.dispose();
    super.dispose();
  }

  int get _travellers => _adults + _children;

  int get _effectiveCustomerOffer {
    final parsed = int.tryParse(_customerOffer.text.trim().replaceAll(',', ''));
    return parsed != null && parsed > 0 ? parsed : 0;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UdTopBar(
              title: context.tr('advanceBooking'),
              onBack: () => Navigator.maybePop(context),
            ),
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
      );

  Widget _routeStep() {
    final controller = AppControllerScope.of(context);
    final matches = _matchingVehicles(controller.liveMarketplacePackages);
    final destinationEntered = _destination.text.trim().isNotEmpty;
    final destinationSuggestions = _destinationSuggestions(
      controller.liveMarketplacePackages,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        _StepIntro(
          icon: Icons.route_rounded,
          title: context.tr('whereTo'),
          subtitle: 'Enter your destination and date. Available vehicles will appear instantly.',
        ),
        const SizedBox(height: 14),
        UdCard(
          child: Column(
            children: [
              UdTextField(
                controller: _pickup,
                textInputAction: TextInputAction.next,
                icon: Icons.trip_origin_rounded,
                label: context.tr('pickup'),
                hint: 'Your pickup city or point',
                suffix: _locatingPickup
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : UdIconButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Use my current location',
                        onPressed: _useCurrentLocation,
                      ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              UdTextField(
                controller: _destination,
                textInputAction: TextInputAction.search,
                icon: Icons.location_on_rounded,
                label: context.tr('destination'),
                hint: 'e.g. Neelum Valley, Sharda, Arang Kel',
                suffix: _destination.text.trim().isEmpty
                    ? null
                    : UdIconButton(
                        icon: Icons.close_rounded,
                        onPressed: _destination.clear,
                      ),
                validator: _required,
              ),
              if (destinationSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                // Still scrollable, and still capped — a long suggestion list
                // must not push the date fields off the step. UdListGroup lays
                // its children out in a Column, so the scrolling is here.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: SingleChildScrollView(
                    child: UdListGroup(
                      children: [
                        for (final suggestion in destinationSuggestions)
                          UdListRow(
                            title: suggestion,
                            leading: const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.navy,
                              size: 19,
                            ),
                            onTap: () {
                              _destination.value = TextEditingValue(
                                text: suggestion,
                                selection: TextSelection.collapsed(
                                  offset: suggestion.length,
                                ),
                              );
                              FocusScope.of(context).unfocus();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
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
                  Text('Available vehicles', style: AppType.section),
                  SizedBox(height: 2),
                  Text(
                    'Matching scheduled vehicles are shown for reference. Continue to complete your request below.',
                    style: _captionMuted,
                  ),
                ],
              ),
            ),
            if (destinationEntered)
              UdBadge(label: '${matches.length} found', tone: UdTone.lime),
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
              ),
            ),
          ),
        const SizedBox(height: 14),
        const UdBanner(
          tone: UdTone.info,
          icon: Icons.info_outline_rounded,
          text: 'No suitable scheduled vehicle? Continue below to request a '
              'private or shared ride and receive Driver offers.',
        ),
        const SizedBox(height: 12),
        // The subtitle stays: it is the only place that explains what a return
        // trip does to the fare, and the row is meaningless without it.
        UdListGroup(
          children: [
            UdListRow(
              title: context.tr('returnTrip'),
              subtitle: context.tr('returnTripHelp'),
              trailing: UdSwitch(
                value: _returnTrip,
                onChanged: (value) => setState(() {
                  _returnTrip = value;
                  _returnDate =
                      value ? _departureDate.add(const Duration(days: 2)) : null;
                }),
              ),
            ),
          ],
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

  /// Typeahead hints only, on top of whatever the live packages offer.
  ///
  /// These are the six destinations the server's catalogue actually carries
  /// (migration 003). They replaced `destinations` from `data/dummy_data.dart`,
  /// which listed the same sort of places but attached invented ratings,
  /// travel times, road conditions and a "safety score out of 100" to each —
  /// numbers nobody measured. Only the names were ever used here, but a list
  /// carrying fabricated metadata had no business being imported at all.
  static const List<String> _knownDestinations = [
    'Muzaffarabad',
    'Neelum Valley',
    'Sharda',
    'Rawalakot',
    'Banjosa Lake',
    'Pir Chinasi',
  ];

  List<String> _destinationSuggestions(List<LiveTourPackage> source) {
    final query = _destination.text.trim().toLowerCase();
    if (query.isEmpty) return const [];

    final values = <String>{
      ...source.map((package) => package.destination.trim()),
      ..._knownDestinations,
    }..removeWhere((value) => value.isEmpty);

    if (values.any((value) => value.toLowerCase() == query)) {
      return const [];
    }

    final suggestions = values
        .where((value) => value.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        final aStarts = a.toLowerCase().startsWith(query);
        final bStarts = b.toLowerCase().startsWith(query);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return a.compareTo(b);
      });
    return suggestions.take(6).toList(growable: false);
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
          UdCard(
            child: Column(
              children: [
                _CounterRow(label: context.tr('adults'), icon: Icons.person_rounded, value: _adults, min: 1, onChanged: (value) { setState(() => _adults = value); _syncRecommendedVehicle(); }),
                const Divider(),
                _CounterRow(label: context.tr('children'), icon: Icons.child_care_rounded, value: _children, onChanged: (value) { setState(() => _children = value); _syncRecommendedVehicle(); }),
                const Divider(),
                _CounterRow(label: context.tr('luggage'), icon: Icons.luggage_rounded, value: _luggage, onChanged: (value) => setState(() => _luggage = value)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(context.tr('travellerPreference'), style: AppType.h3),
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
          UdCheckboxRow(
            value: _familyOnly,
            onChanged: (value) => setState(() => _familyOnly = value),
            child: Text(context.tr('familyOnlyPreference'), style: AppType.body),
          ),
          const SizedBox(height: 4),
          UdCheckboxRow(
            value: _femalePreference,
            onChanged: (value) => setState(() => _femalePreference = value),
            child: Text(context.tr('femalePassengerPreference'), style: AppType.body),
          ),
        ],
      );

  Widget _vehicleStep() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _StepIntro(icon: Icons.directions_car_filled_rounded, title: context.tr('selectVehicle'), subtitle: context.tr('bookingStepThreeHelp')),
          const SizedBox(height: 18),
          ...vehicleCatalogue.map(
            (vehicle) {
              final enabled = vehicle.seats >= _travellers;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _VehicleChoice(
                  vehicle: vehicle,
                  selected: _vehicle.name == vehicle.name,
                  recommended: _recommended(vehicle),
                  enabled: enabled,
                  onTap: enabled ? () => setState(() => _vehicle = vehicle) : null,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          UdTextField(
            controller: _notes,
            maxLines: 3,
            minLines: 3,
            icon: Icons.notes_rounded,
            label: context.tr('specialInstructions'),
            hint: context.tr('specialInstructionsHint'),
          ),
        ],
      );

  Widget _reviewStep() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _StepIntro(icon: Icons.fact_check_rounded, title: context.tr('reviewBooking'), subtitle: context.tr('bookingStepFourHelp')),
          const SizedBox(height: 18),
          UdCard(
            tone: UdCardTone.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.route_rounded, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_pickup.text} → ${_destination.text}',
                      style: AppType.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.onInk,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _ReviewLine(label: context.tr('dateTime'), value: '${DateFormat('dd MMM yyyy').format(_departureDate)} · ${_departureTime.format(context)}'),
                _ReviewLine(label: context.tr('bookingOption'), value: _bookingType == BookingType.perSeat ? context.tr('bookPerSeat') : context.tr('bookWholeVehicle')),
                _ReviewLine(label: context.tr('passengers'), value: '$_travellers'),
                _ReviewLine(label: context.tr('vehicle'), value: _vehicle.name),
              ],
            ),
          ),
          const SizedBox(height: 14),
          UdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your fare offer', style: AppType.h3),
                const SizedBox(height: 6),
                const Text(
                  'Enter the total amount you want to offer verified Drivers. Drivers can accept it or send a counteroffer.',
                  style: _captionMuted,
                ),
                const SizedBox(height: 12),
                UdTextField(
                  controller: _customerOffer,
                  keyboardType: TextInputType.number,
                  icon: Icons.payments_rounded,
                  label: 'Customer offered fare (PKR)',
                  helper: 'A driver will answer with their own price.',
                  validator: (value) {
                    final amount = int.tryParse((value ?? '').trim().replaceAll(',', ''));
                    if (amount == null || amount <= 0) return 'Enter a valid fare offer.';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PriceLine(label: 'Your total offer', value: _effectiveCustomerOffer, bold: true),
                const SizedBox(height: 8),
                Text(
                  _bookingType == BookingType.perSeat
                      ? 'Fuel, toll and Udrive charges are included in the seat fare.'
                      : 'Toll charges, if applicable, will be paid by the customer at actual cost.',
                  style: const TextStyle(
                    color: AppTint.successText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          UdBanner(
            tone: UdTone.ok,
            icon: Icons.verified_user_rounded,
            text: context.tr('secureBookingMessage'),
          ),
        ],
      );

  Widget _bottomActions() => UdBottomBar(
        children: [
          Row(
            children: [
              if (_step > 0) ...[
                SizedBox(
                  width: 120,
                  child: UdButton.outline(
                    label: context.tr('back'),
                    onPressed: () => setState(() => _step--),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: UdButton.primary(
                  label: _step == 3
                      ? context.tr('findVerifiedDrivers')
                      : context.tr('continue'),
                  trailingIcon: Icons.arrow_forward_rounded,
                  busy: _submitting,
                  onPressed: _step == 3 ? _submit : _next,
                ),
              ),
            ],
          ),
        ],
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
      final pickupCoordinates = (_pickupLatitude != null && _pickupLongitude != null)
          ? (_pickupLatitude!, _pickupLongitude!)
          : _coordinatesFor(_pickup.text, pickup: true);
      final destinationCoordinates = _coordinatesFor(_destination.text);
      if (!_formKey.currentState!.validate()) return;
      final total = _effectiveCustomerOffer;
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
    } on ApiException catch (error) {
      if (mounted) {
        final message = error.statusCode == 401
            ? 'Your session has expired. Please log in again.'
            : error.statusCode != null && error.statusCode! >= 500
                ? 'Booking service is temporarily unavailable. Please retry in a moment.'
                : error.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The booking request could not be sent. Please check your connection and retry.')),
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
    if (vehicle.seats < _travellers) return false;
    final destination = _destination.text.toLowerCase();
    if (destination.contains('arang') || destination.contains('ratti') || destination.contains('kel')) {
      return vehicle.name == '4×4 Jeep';
    }
    if (_travellers > 14) return vehicle.name == 'Coaster';
    return vehicle.name == recommendedVehicleFor(_travellers).name;
  }

  void _syncRecommendedVehicle() {
    // Smallest vehicle everybody fits in. The old version picked between
    // "Comfort", "SUV" and "Hiace" — two of which the server has never heard
    // of — and a family of three was steered to a category that did not exist.
    final recommended = recommendedVehicleFor(_travellers);
    if (_vehicle.name != recommended.name && mounted) {
      setState(() => _vehicle = recommended);
    }
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    if (_locatingPickup) return;
    if (mounted) setState(() => _locatingPickup = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services to use your current pickup.')),
          );
        }
        return;
      }
      // Disclosure before the prompt — see LocationAccess.
      final permission =
          await LocationAccess.ensure(context, LocationPurpose.customer);
      if (!LocationAccess.granted(permission)) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required for automatic pickup.')),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      final address = await _reverseGeocodePickup(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _pickupLatitude = position.latitude;
        _pickupLongitude = position.longitude;
        _pickup.text = address;
      });
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current location could not be detected. You can enter pickup manually.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locatingPickup = false);
    }
  }


  Future<String> _reverseGeocodePickup(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String?>[
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

        final unique = <String>[];
        for (final part in parts) {
          if (!unique.any((item) => item.toLowerCase() == part.toLowerCase())) {
            unique.add(part);
          }
        }
        if (unique.isNotEmpty) return unique.join(', ');
      }
    } catch (_) {
      // Keep the booking usable if the geocoding provider is temporarily unavailable.
    }
    return 'Current location';
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.navy, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: _overlineMuted),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption,
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
          color: AppColors.surface,
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
              style: _captionMuted,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              UdButton.ghost(
                label: actionLabel!,
                icon: Icons.event_available_rounded,
                size: UdButtonSize.small,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      );
}

class _SearchVehicleCard extends StatelessWidget {
  const _SearchVehicleCard({required this.package});

  final LiveTourPackage package;

  @override
  Widget build(BuildContext context) {
    final image = package.coverImageUrl?.trim();
    final seats = package.bookableSeats;
    final seatColor = seats <= 2 ? AppTint.warning : AppTint.success;
    final seatText = seats <= 2 ? AppTint.warningText : AppTint.successText;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppTint.brand,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                const Icon(Icons.trip_origin_rounded, size: 15, color: AppColors.primary),
                const SizedBox(width: 5),
                Expanded(child: Text(package.startingCity, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.navy)),
                Expanded(child: Text(package.destination, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 12.5))),
                const SizedBox(width: 4),
                const Icon(Icons.location_on_rounded, size: 15, color: AppColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                clipBehavior: Clip.antiAlias,
                child: image != null && image.isNotEmpty
                    ? Image.network(image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.directions_bus_rounded, color: AppColors.navy))
                    : const Icon(Icons.directions_bus_rounded, color: AppColors.navy),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(package.vehicle.isEmpty ? package.title : package.vehicle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption),
                  const SizedBox(height: 2),
                  Text(package.registrationNumber, maxLines: 1, overflow: TextOverflow.ellipsis, style: _overlineMuted),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM · hh:mm a').format(package.departureAt), style: _overlineMuted),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('PKR ${NumberFormat('#,###').format(package.pricePerSeat)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.navy)),
                const Text('per seat', style: _overlineMuted),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: seatColor, borderRadius: BorderRadius.circular(999)),
                  child: Text('$seats seats free', style: _overlineMuted.copyWith(color: seatText)),
                ),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}

/// Four steps, as four segments.
///
/// It used to be four numbered circles joined by a rule. The numbers were the
/// only thing carrying the state, at 12px, and the row cost about forty pixels
/// of a phone screen to say "you are on step 2 of 4" — which the segments say
/// in six pixels, and which the step's own heading says in words anyway.
class _BookingProgress extends StatelessWidget {
  const _BookingProgress({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 2, AppSizes.sidePadding, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            UdSteps(total: 4, current: current),
            const SizedBox(height: 8),
            Text(
              'Step ${current + 1} of 4',
              style: AppType.overline.copyWith(color: AppText.secondary),
            ),
          ],
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
          UdIconTile(icon: icon, size: UdIconTileSize.lg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppType.h2.copyWith(color: AppText.primary)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppType.body2.copyWith(color: AppText.secondary),
                ),
              ],
            ),
          ),
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
  Widget build(BuildContext context) => UdCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.navy),
            const SizedBox(height: 10),
            Text(label, style: _overlineMuted),
            const SizedBox(height: 3),
            Text(value, style: AppType.listTitle),
          ],
        ),
      );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandWash : AppColors.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.card),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              UdIconTile(
                icon: icon,
                tone: selected ? UdIconTone.soft : UdIconTone.neutral,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.listTitle.copyWith(
                        fontSize: 16,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
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
          Icon(icon, color: AppColors.navy),
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
  Widget build(BuildContext context) => UdChip(
        label: label,
        icon: icon,
        selected: selected == value,
        onTap: () => onSelected(value),
      );
}

class _VehicleChoice extends StatelessWidget {
  const _VehicleChoice({
    required this.vehicle,
    required this.selected,
    required this.recommended,
    required this.enabled,
    required this.onTap,
  });

  final VehicleCategory vehicle;
  final bool selected;
  final bool recommended;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : .48,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandWash : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(vehicle.icon, color: AppColors.navy),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              vehicle.name,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 7),
                            UdBadge(
                              label: context.tr('recommended'),
                              tone: UdTone.lime,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        enabled
                            ? '${vehicle.seats} seats · ${vehicle.luggage} bags'
                            : '${vehicle.seats} seats · Not enough capacity',
                        style: _captionMuted,
                      ),
                      Text(
                        vehicle.description,
                        style: _captionMuted,
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                // On navy, so the secondary ink is the on-navy one. It was
                // AppText.secondary — a grey chosen for white pages — which on
                // this card measured about 2:1.
                style: AppType.caption.copyWith(color: AppText.onInkMuted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppType.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.onInk,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.label, required this.value, this.bold = false});
  final String label;
  final int value;
  final bool bold;
  @override
  Widget build(BuildContext context) => UdKeyValue(
        label: label,
        value: 'PKR ${NumberFormat('#,###').format(value)}',
        total: bold,
      );
}
