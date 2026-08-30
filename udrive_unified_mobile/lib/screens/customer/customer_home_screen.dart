import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/booking/trip_operations_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/services/place_search_service.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/route_fields.dart';
import '../../core/widgets/service_selector.dart';
import '../../core/widgets/ud_controls.dart';
import '../../data/models.dart';
import '../../models/trip_operations_models.dart';
import '../hotels/hotel_list_screen.dart';
import '../operations/live_trip_navigation_screen.dart';
import 'tour_map_screen.dart';
import 'udrive_route_flow_screen.dart';

/// Map-first, service-first Home.
///
/// Layout, per the redesign handoff: a fixed map band with floating controls, a
/// white booking card that overlaps it by 24px, then the active-trip banner and
/// the invite row, all in a single scroll.
///
/// The booking card is presentation only. Every submission still goes through
/// the existing repositories: non-tour bookings hand off to the current vehicle
/// selection screen, tour bookings create a ride request and push [TourMapScreen].
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

enum _BusFareMode { perSeat, wholeVehicle }

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  // ------------------------------------------------------------- controllers
  final _pickup = TextEditingController(text: 'Detecting current address…');
  final _destination = TextEditingController();
  final _hotelCity = TextEditingController();
  final _tourOffer = TextEditingController();

  final _pickupFocus = FocusNode();
  final _destinationFocus = FocusNode();

  final _places = PlaceSearchService();

  Timer? _tripTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  TripOperationsRepository? _tripRepository;

  // ------------------------------------------------------------------- state
  HomeService _service = HomeService.car;
  bool _tourMode = false;
  bool _locating = false;
  bool _offline = false;
  bool _submitting = false;
  bool _locationExpanded = false;

  LatLng _pickupPoint =
      const LatLng(AppConfig.fallbackLatitude, AppConfig.fallbackLongitude);
  LatLng? _destinationPoint;
  String _resolvedPlaceName = 'Locating…';

  RouteFieldKind? _activeField;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;

  // Non-tour vehicle options
  _BusFareMode _busFareMode = _BusFareMode.perSeat;
  int _seats = 1;
  int _passengers = 1;

  // Tour options
  DateTime _tourDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _tourTime = const TimeOfDay(hour: 8, minute: 0);
  int _tourPassengers = 2;

  // Hotel options
  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 2));
  int _guests = 2;
  int _rooms = 1;

  MobileTrip? _activeTrip;

  /// Trip states that mean a ride is genuinely under way. Matches the set the
  /// previous Home screen used, so banner behaviour is unchanged.
  static const _activeTripStatuses = {
    'DriverEnRoute',
    'DriverArrived',
    'TripStarted',
    'Emergency',
  };

  @override
  void initState() {
    super.initState();

    _pickupFocus.addListener(_onFocusChanged);
    _destinationFocus.addListener(_onFocusChanged);

    Connectivity().checkConnectivity().then(_applyConnectivity);
    _connectivity =
        Connectivity().onConnectivityChanged.listen(_applyConnectivity);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocation());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripRepository ??=
        TripOperationsRepository(AppControllerScope.of(context).apiClient);
    _refreshActiveTrip();
    _tripTimer ??= Timer.periodic(
      const Duration(seconds: 12),
      (_) => _refreshActiveTrip(),
    );
  }

  @override
  void dispose() {
    _tripTimer?.cancel();
    _connectivity?.cancel();
    _pickupFocus.removeListener(_onFocusChanged);
    _destinationFocus.removeListener(_onFocusChanged);
    _pickup.dispose();
    _destination.dispose();
    _hotelCity.dispose();
    _tourOffer.dispose();
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    _places.dispose();
    super.dispose();
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final offline = results.every((value) => value == ConnectivityResult.none);
    if (offline == _offline) return;
    setState(() => _offline = offline);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_pickupFocus.hasFocus) {
        _activeField = RouteFieldKind.pickup;
      } else if (_destinationFocus.hasFocus) {
        _activeField = RouteFieldKind.destination;
      } else {
        _activeField = null;
        _suggestions = const [];
      }
    });
  }

  // ----------------------------------------------------------------- location

  Future<void> _loadLocation() async {
    if (_locating) return;
    if (mounted) setState(() => _locating = true);
    _pickup.text = 'Detecting current address…';

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setPickupFailure('Turn on location to use current address');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _setPickupFailure('Allow location from app settings');
        return;
      }
      if (permission == LocationPermission.denied) {
        _setPickupFailure('Allow location to detect pickup');
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _setPickupFailure('Tap the locate button to try again');
        return;
      }

      final point = LatLng(position.latitude, position.longitude);
      final address =
          await _places.reverseGeocode(point.latitude, point.longitude);
      if (!mounted) return;

      final label = address.isNotEmpty
          ? address
          : '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}';

      setState(() {
        _pickupPoint = point;
        _pickup.text = label;
        _resolvedPlaceName = label;
      });
    } catch (_) {
      _setPickupFailure('Tap the locate button to try again');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _setPickupFailure(String message) {
    if (!mounted) return;
    setState(() {
      _pickup.text = message;
      _resolvedPlaceName = message;
    });
  }

  Future<void> _refreshActiveTrip() async {
    final repository = _tripRepository;
    if (repository == null) return;
    try {
      final trips = await repository.customerTrips();
      if (!mounted) return;
      final active = trips
          .where((trip) => _activeTripStatuses.contains(trip.tripStatus))
          .toList();
      setState(() => _activeTrip = active.isEmpty ? null : active.first);
    } catch (_) {
      // A failed poll must never disturb a screen the customer is using.
    }
  }

  Future<void> _openActiveTrip() async {
    final trip = _activeTrip;
    final repository = _tripRepository;
    if (trip == null || repository == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFullScreenTrackingScreen(
          trip: trip,
          repository: repository,
        ),
      ),
    );
    if (mounted) await _refreshActiveTrip();
  }

  // -------------------------------------------------------------- suggestions

  void _onRouteQueryChanged(RouteFieldKind field, String value) {
    setState(() {
      _activeField = field;
      _searching = value.trim().length >= 2;
      if (field == RouteFieldKind.destination) _destinationPoint = null;
    });
    _places.searchDebounced(
      value,
      bias: _pickupPoint,
      onResults: (results) {
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      },
    );
  }

  void _onSuggestionSelected(RouteFieldKind field, PlaceSuggestion place) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (field == RouteFieldKind.pickup) {
        _pickup.text = place.title;
        _pickupPoint = place.point;
        _resolvedPlaceName = place.title;
      } else {
        _destination.text = place.title;
        _destinationPoint = place.point;
      }
      _suggestions = const [];
      _activeField = null;
    });
  }

  // ------------------------------------------------------------------ actions

  bool get _ctaEnabled {
    if (_submitting) return false;
    if (_service == HomeService.hotel) {
      return _hotelCity.text.trim().isNotEmpty && _checkOut.isAfter(_checkIn);
    }
    // Typed text is enough. Coordinates are resolved when the button is
    // pressed, so the customer is never blocked on picking a suggestion.
    if (_pickup.text.trim().isEmpty || _destination.text.trim().isEmpty) {
      return false;
    }
    if (_tourMode) {
      final offer = int.tryParse(_tourOffer.text.trim());
      return offer != null && offer > 0;
    }
    return true;
  }

  String get _ctaLabel {
    if (_service == HomeService.hotel) return 'Find Hotels';
    if (_tourMode) return 'Find Vehicle for Tour';
    return switch (_service) {
      HomeService.bus => 'Find Coaster / Bus',
      HomeService.car => 'Find a Car',
      HomeService.bike => 'Find a Bike',
      HomeService.hotel => 'Find Hotels',
    };
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_ctaEnabled) return;

    if (_service == HomeService.hotel) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HotelListScreen(
            destination: _hotelCity.text.trim(),
            checkIn: _checkIn,
            checkOut: _checkOut,
            guests: _guests,
            rooms: _rooms,
          ),
        ),
      );
      return;
    }

    if (_tourMode) {
      await _submitTour();
      return;
    }

    await _openVehicleSelection();
  }

  /// Resolves whatever the customer typed into coordinates.
  ///
  /// The customer is never forced to pick from the suggestion list — they can
  /// type any address, area or landmark. If they did tap a suggestion we
  /// already have the point; otherwise we geocode the free text here. A null
  /// result is not a dead end: the caller falls back to the full route screen
  /// with the text pre-filled so the trip can still be booked.
  Future<LatLng?> _resolveDestination() async {
    if (_destinationPoint != null) return _destinationPoint;

    final text = _destination.text.trim();
    if (text.isEmpty) return null;

    setState(() => _submitting = true);
    try {
      final matches = await _places.search(text, bias: _pickupPoint);
      if (matches.isEmpty) return null;
      final point = matches.first.point;
      if (mounted) setState(() => _destinationPoint = point);
      return point;
    } catch (_) {
      return null;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Non-tour: hand straight to the existing route/vehicle flow. The
  /// route-entry step is skipped when we have coordinates for both ends.
  Future<void> _openVehicleSelection() async {
    final destinationPoint = await _resolveDestination();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UDriveRouteFlowScreen(
          serviceType: _busFareMode == _BusFareMode.wholeVehicle &&
                  _service == HomeService.bus
              ? UDriveServiceType.privateVehicle
              : UDriveServiceType.city,
          pickupLabel: _pickup.text.trim(),
          pickupPoint: _pickupPoint,
          initialDestinationLabel: _destination.text.trim(),
          initialDestinationLatitude: destinationPoint?.latitude,
          initialDestinationLongitude: destinationPoint?.longitude,
          // When the typed address could not be geocoded we open the full
          // route screen (pre-filled) rather than blocking the customer.
          skipRouteEntry: destinationPoint != null,
        ),
      ),
    );
  }

  /// Tour: create the ride request now, then show nearby drivers on a map so
  /// the customer can pick whichever price suits them.
  Future<void> _submitTour() async {
    final destinationPoint = await _resolveDestination();
    if (!mounted) return;
    if (destinationPoint == null) {
      // The tour request API needs real coordinates, so this is the one place
      // we have to ask for a more specific address.
      _snack(
        'We could not locate "${_destination.text.trim()}". Try adding the '
        'town or district, or pick from the suggestions.',
      );
      return;
    }
    final offer = int.tryParse(_tourOffer.text.trim());
    if (offer == null || offer <= 0) {
      _snack('Enter your fare offer before finding a vehicle.');
      return;
    }

    setState(() => _submitting = true);
    final controller = AppControllerScope.of(context);
    try {
      final departure = DateTime(
        _tourDate.year,
        _tourDate.month,
        _tourDate.day,
        _tourTime.hour,
        _tourTime.minute,
      );

      final request = await controller.createLiveRideRequest({
        'pickupLabel': _pickup.text.trim(),
        'destinationLabel': _destination.text.trim(),
        'pickupLatitude': _pickupPoint.latitude,
        'pickupLongitude': _pickupPoint.longitude,
        'destinationLatitude': destinationPoint.latitude,
        'destinationLongitude': destinationPoint.longitude,
        'pickupAt': departure.toUtc().toIso8601String(),
        'bookingType': 'WholeVehicle',
        'seatsRequested': _tourPassengers,
        'adults': _tourPassengers,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': offer,
        'vehicleCategory': _service.vehicleCategory ?? 'Car',
        'partyType': _tourPassengers > 1 ? 'Group' : 'Individual',
        'familyOnly': false,
        'womenOnly': false,
        'instantRide': false,
        'notes': 'Tour booking • $_tourPassengers passenger(s) • '
            'advance payment required',
      });

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TourMapScreen(
            rideRequestId: request.id,
            pickupLabel: request.pickupLabel,
            destinationLabel: request.destinationLabel,
            pickupPoint: _pickupPoint,
            destinationPoint: destinationPoint,
            departureAt: departure,
            passengers: _tourPassengers,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _snack('$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickTourDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _tourDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (selected != null && mounted) setState(() => _tourDate = selected);
  }

  Future<void> _pickTourTime() async {
    final selected =
        await showTimePicker(context: context, initialTime: _tourTime);
    if (selected != null && mounted) setState(() => _tourTime = selected);
  }

  Future<void> _pickHotelDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _checkIn, end: _checkOut),
    );
    if (range != null && mounted) {
      setState(() {
        _checkIn = range.start;
        _checkOut = range.end;
      });
    }
  }

  Future<void> _shareApp() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Book rides, tours and hotels across Azad Kashmir with '
            '${AppConfig.appName}: ${AppConfig.referralShareUrl}',
        subject: '${AppConfig.appName} — travel across Kashmir',
      ),
    );
  }

  Future<void> _toggleLanguage(AppController controller) async {
    final next = controller.locale.languageCode == 'ur' ? 'en' : 'ur';
    await controller.setLanguage(next);
  }

  // ------------------------------------------------------------------ building

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return Container(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _buildServiceHero(controller),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildBookingCard(),
                ),
                if (_offline)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _OfflineNotice(),
                  ),
                if (_activeTrip != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _ActiveTripBanner(
                      trip: _activeTrip!,
                      onTrack: _openActiveTrip,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _InviteRow(onShare: _shareApp),
                ),
                const SizedBox(height: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Service hero. Replaces the map: the customer sees a large picture of
  /// whatever service is selected, so the choice is unmistakable.
  Widget _buildServiceHero(AppController controller) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 34),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTint.surface, AppColors.background],
        ),
      ),
      child: Column(
        children: [
          // Header row. Everything is centred on one axis so the location
          // control and the three icon buttons line up regardless of height.
          SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _LocationControl(
                    expanded: _locationExpanded,
                    placeName: _resolvedPlaceName,
                    onTap: () =>
                        setState(() => _locationExpanded = !_locationExpanded),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _MapIconButton(
                      icon: Icons.translate_rounded,
                      semanticLabel: 'Switch language',
                      onTap: () => _toggleLanguage(controller),
                    ),
                    const SizedBox(width: 8),
                    _MapIconButton(
                      icon: Icons.swap_horiz_rounded,
                      semanticLabel: 'Switch to driver mode',
                      onTap: () => controller.switchMode(UserMode.driver),
                    ),
                    const SizedBox(width: 8),
                    _MapIconButton(
                      icon: Icons.notifications_none_rounded,
                      semanticLabel: 'Notifications',
                      showDot: true,
                      onTap: () => widget.onNavigate('notifications'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: .94, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: _ServiceHeroArt(
              key: ValueKey(_service),
              service: _service,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.panel),
        boxShadow: AppShadows.panel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ServiceSelector(
            selected: _service,
            onChanged: (service) {
              FocusScope.of(context).unfocus();
              setState(() {
                _service = service;
                if (service == HomeService.hotel) _tourMode = false;
              });
            },
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: AppConfig.panelSwitch,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppConfig.panelSwitch,
              child: _service == HomeService.hotel
                  ? _buildHotelPanel()
                  : _buildVehiclePanel(),
            ),
          ),
          const SizedBox(height: 14),
          _PrimaryCta(
            label: _ctaLabel,
            enabled: _ctaEnabled,
            busy: _submitting,
            onTap: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclePanel() {
    return Column(
      key: const ValueKey('vehicle-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Trip details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppText.secondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _locating ? null : _loadLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 17),
              label: Text(_locating ? 'Locating…' : 'Use my location'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        RouteFields(
          pickupController: _pickup,
          destinationController: _destination,
          pickupFocus: _pickupFocus,
          destinationFocus: _destinationFocus,
          activeField: _activeField,
          suggestions: _suggestions,
          searching: _searching,
          onPickupChanged: (value) =>
              _onRouteQueryChanged(RouteFieldKind.pickup, value),
          onDestinationChanged: (value) =>
              _onRouteQueryChanged(RouteFieldKind.destination, value),
          onSuggestionSelected: _onSuggestionSelected,
        ),
        const SizedBox(height: 12),
        _TourToggleRow(
          value: _tourMode,
          onChanged: (value) => setState(() => _tourMode = value),
        ),
        AnimatedSize(
          duration: AppConfig.panelSwitch,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _tourMode ? _buildTourPanel() : _buildStandardOptions(),
        ),
      ],
    );
  }

  Widget _buildTourPanel() {
    final dateLabel = DateFormat('EEE, d MMM yyyy').format(_tourDate);
    final timeLabel = _tourTime.format(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TapField(
                  caption: 'Departure date',
                  value: dateLabel,
                  icon: Icons.calendar_today_rounded,
                  onTap: _pickTourDate,
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 116,
                child: _TapField(
                  caption: 'Time',
                  value: timeLabel,
                  icon: Icons.schedule_rounded,
                  onTap: _pickTourTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          UdStepper(
            label: 'Passengers',
            value: _tourPassengers,
            min: 1,
            max: 40,
            onChanged: (value) => setState(() => _tourPassengers = value),
          ),
          const SizedBox(height: 9),
          _MoneyField(
            caption: 'Your offer',
            controller: _tourOffer,
            hint: 'e.g. 12000',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 9),
          const _AdvanceDisclosure(),
        ],
      ),
    );
  }

  Widget _buildStandardOptions() {
    if (_service == HomeService.bike) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _service == HomeService.bus
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UdSegmented<_BusFareMode>(
                  value: _busFareMode,
                  options: const [
                    (value: _BusFareMode.perSeat, label: 'Per seat'),
                    (value: _BusFareMode.wholeVehicle, label: 'Full vehicle'),
                  ],
                  onChanged: (value) => setState(() => _busFareMode = value),
                ),
                if (_busFareMode == _BusFareMode.perSeat) ...[
                  const SizedBox(height: 9),
                  UdStepper(
                    label: 'Seats',
                    value: _seats,
                    min: 1,
                    max: 40,
                    onChanged: (value) => setState(() => _seats = value),
                  ),
                ],
              ],
            )
          : UdStepper(
              label: 'Passengers',
              value: _passengers,
              min: 1,
              max: 7,
              onChanged: (value) => setState(() => _passengers = value),
            ),
    );
  }

  Widget _buildHotelPanel() {
    final nights = _checkOut.difference(_checkIn).inDays;
    final format = DateFormat('d MMM');

    return Column(
      key: const ValueKey('hotel-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlainField(
          caption: 'City',
          controller: _hotelCity,
          hint: 'Muzaffarabad, Rawalakot, Neelum…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 9),
        _TapField(
          caption: 'Check-in — Check-out',
          value: '${format.format(_checkIn)} — ${format.format(_checkOut)}'
              '${nights > 0 ? '  ·  $nights night${nights == 1 ? '' : 's'}' : ''}',
          icon: Icons.date_range_rounded,
          onTap: _pickHotelDates,
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: UdStepper(
                label: 'Guests',
                value: _guests,
                min: 1,
                max: 20,
                onChanged: (value) => setState(() => _guests = value),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: UdStepper(
                label: 'Rooms',
                value: _rooms,
                min: 1,
                max: 10,
                onChanged: (value) => setState(() => _rooms = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- map chrome

/// Collapsed: a plain 30x30 navy square with the green U mark, no card.
/// Expanded: animates open left-to-right into a translucent white pill.
class _LocationControl extends StatelessWidget {
  const _LocationControl({
    required this.expanded,
    required this.placeName,
    required this.onTap,
  });

  final bool expanded;
  final String placeName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Current location: $placeName',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'U',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            AnimatedSize(
              duration: AppConfig.pillExpand,
              curve: Curves.easeOut,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 165),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .95),
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: AppShadows.floating,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current location',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppText.secondary,
                              ),
                            ),
                            Text(
                              placeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppText.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .97),
                borderRadius: BorderRadius.circular(11),
                boxShadow: AppShadows.floating,
              ),
              child: Icon(icon, size: 20, color: AppColors.navy),
            ),
            if (showDot)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Large illustration of the currently selected service.
class _ServiceHeroArt extends StatelessWidget {
  const _ServiceHeroArt({required this.service, super.key});

  final HomeService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 168,
          child: Image.asset(
            service.heroAsset,
            fit: BoxFit.contain,
            // If an asset is ever missing the screen still works: a large
            // outline icon stands in rather than a broken-image box.
            errorBuilder: (_, __, ___) => Center(
              child: Icon(service.icon, size: 96, color: AppText.disabled),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          service.heroTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppText.primary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          service.heroSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppText.secondary,
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- card pieces

class _TourToggleRow extends StatelessWidget {
  const _TourToggleRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(AppRadii.field),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded,
              size: 21, color: AppColors.navy),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Tour booking',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ),
          UdToggleSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: 'Tour booking',
          ),
        ],
      ),
    );
  }
}

class _AdvanceDisclosure extends StatelessWidget {
  const _AdvanceDisclosure();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTint.success,
        borderRadius: AppRadii.all(AppRadii.field),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: AppTint.successText),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tour bookings require an advance payment, held securely by '
              'UDrive and released to your driver on arrival.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppTint.successText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.caption,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final String caption;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 3),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppText.disabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// PKR prefix is a static label, never part of the editable value.
class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.caption,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final String caption;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
          Row(
            children: [
              const Text(
                'PKR',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppText.secondary,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 3),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppText.disabled,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TapField extends StatelessWidget {
  const _TapField({
    required this.caption,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String caption;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.field),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.all(AppRadii.field),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppText.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, size: 20, color: AppText.secondary),
          ],
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: enabled ? AppColors.navy : AppColors.border,
        borderRadius: AppRadii.all(AppRadii.cta),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadii.all(AppRadii.cta),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: enabled ? Colors.white : AppText.disabled,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTint.warning,
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: AppTint.warningText),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'You are offline. Saved maps are in use and bookings will need a '
              'connection.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppTint.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveTripBanner extends StatelessWidget {
  const _ActiveTripBanner({required this.trip, required this.onTrack});

  final MobileTrip trip;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadii.all(AppRadii.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Trip in progress',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${trip.pickupLabel} → ${trip.destinationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(99),
            child: InkWell(
              onTap: onTrack,
              borderRadius: BorderRadius.circular(99),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Text(
                  'Track Ride',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.onShare});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTint.brand,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.ios_share_rounded,
                size: 18, color: AppColors.navy),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Invite a friend',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Share the UDrive app link',
                  style: TextStyle(fontSize: 12.5, color: AppText.secondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onShare,
            child: const Text(
              'Share',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
