import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/maps/ud_map.dart';
import '../../core/vehicles/nearby_repository.dart';
import '../../core/vehicles/nearby_vehicle.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/booking/travel_mode.dart';
import '../../core/booking/vehicle_booking_mode.dart';
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
import 'place_search_screen.dart';
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

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  // ------------------------------------------------------------- controllers
  final _pickup = TextEditingController(text: 'Detecting current address…');
  final _destination = TextEditingController();
  final _hotelCity = TextEditingController();
  final _tourOffer = TextEditingController();


  final _places = PlaceSearchService();

  Timer? _tripTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  TripOperationsRepository? _tripRepository;
  NearbyVehicleRepository? _nearbyRepository;
  final _mapController = UdMapController();
  Timer? _nearbyTimer;

  /// Vehicles currently online inside the radius. Filtered by service when
  /// drawn, so switching Car → Bike changes the markers without a refetch.
  List<NearbyVehicle> _nearby = const [];
  bool _nearbyLoading = true;

  // ------------------------------------------------------------------- state
  HomeService _service = HomeService.car;
  TravelMode _travelMode = TravelMode.wholeVehicle;

  /// Seats requested in per-seat mode.
  int _seats = 1;

  /// Tour length in days. A Kashmir tour is rarely a single day, so this
  /// replaces the single departure time the old tour panel used.
  int _tourDays = 3;
  bool _locating = false;
  bool _offline = false;
  bool _submitting = false;
  bool _locationExpanded = false;

  LatLng _pickupPoint =
      const LatLng(AppConfig.fallbackLatitude, AppConfig.fallbackLongitude);
  LatLng? _destinationPoint;
  String _resolvedPlaceName = 'Locating…';


  // Tour options
  DateTime _tourDate = DateTime.now().add(const Duration(days: 1));
  int _tourPassengers = 2;

  // Hotel options
  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 2));
  int _guests = 2;
  int _rooms = 1;

  MobileTrip? _activeTrip;

  /// Drives the red dot on the bell. Cleared once the customer opens the panel.
  bool _unreadNotifications = true;

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
    if (_nearbyRepository == null) {
      _nearbyRepository =
          NearbyVehicleRepository(AppControllerScope.of(context).apiClient);
      _refreshNearby();
      _nearbyTimer = Timer.periodic(
        AppConfig.nearbyVehiclesPoll,
        (_) => _refreshNearby(),
      );
    }
    _refreshActiveTrip();
    _tripTimer ??= Timer.periodic(
      const Duration(seconds: 12),
      (_) => _refreshActiveTrip(),
    );
  }

  @override
  void dispose() {
    _tripTimer?.cancel();
    _nearbyTimer?.cancel();
    _mapController.dispose();
    _connectivity?.cancel();
    _pickup.dispose();
    _destination.dispose();
    _hotelCity.dispose();
    _tourOffer.dispose();
    _places.dispose();
    super.dispose();
  }

  /// Refreshes the vehicles around the customer.
  ///
  /// All categories are fetched in one call and filtered client-side, so
  /// switching service is instant and does not cost an extra request.
  Future<void> _refreshNearby() async {
    final repository = _nearbyRepository;
    if (repository == null || _offline) return;
    // IndexedStack keeps this screen mounted when another tab is showing.
    // TickerMode pauses animations but not timers, so check visibility here or
    // a hidden Home would keep polling in the background.
    if (!TickerMode.of(context)) return;

    final results = await repository.nearby(
      latitude: _pickupPoint.latitude,
      longitude: _pickupPoint.longitude,
      radiusKm: AppConfig.nearbyVehiclesRadiusKm,
    );
    if (!mounted) return;
    setState(() {
      _nearby = results;
      _nearbyLoading = false;
    });
  }

  List<NearbyVehicle> get _visibleVehicles {
    if (!_service.isVehicle) return const [];
    return _nearby
        .where((vehicle) => vehicle.service == _service)
        .toList(growable: false);
  }

  void _showVehicleSheet(NearbyVehicle vehicle) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _VehicleMarkerSheet(vehicle: vehicle),
    );
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final offline = results.every((value) => value == ConnectivityResult.none);
    if (offline == _offline) return;
    setState(() => _offline = offline);
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
    if (_travelMode.isTour) {
      final offer = int.tryParse(_tourOffer.text.trim());
      return offer != null && offer > 0;
    }
    return true;
  }

  String get _ctaLabel {
    if (_service == HomeService.hotel) return 'Find Hotels';
    if (_travelMode.isTour) return 'Find Tour Vehicle';

    final noun = switch (_service) {
      HomeService.bus => 'Coaster / Bus',
      HomeService.car => 'a Car',
      HomeService.bike => 'a Bike',
      HomeService.hotel => 'Hotels',
    };
    if (_travelMode == TravelMode.perSeat) {
      return 'Find $_seats seat${_seats == 1 ? '' : 's'}';
    }
    return 'Find $noun';
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

    if (_travelMode.isTour) {
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
          // Whole vehicle maps to the private-vehicle service; per seat uses
          // the shared city service. The next screen still narrows this to what
          // the chosen vehicle's driver actually allows.
          serviceType: _travelMode == TravelMode.wholeVehicle
              ? UDriveServiceType.privateVehicle
              : UDriveServiceType.city,
          pickupLabel: _pickup.text.trim(),
          pickupPoint: _pickupPoint,
          initialDestinationLabel: _destination.text.trim(),
          initialDestinationLatitude: destinationPoint?.latitude,
          initialDestinationLongitude: destinationPoint?.longitude,
          // Only the service the customer picked is offered next — Car shows
          // cars, Bike shows bikes, Coaster shows coasters.
          onlyVehicleKey: _service.vehicleFilterKey,
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
        8,
        0,
      );

      final request = await controller.createLiveRideRequest({
        'pickupLabel': _pickup.text.trim(),
        'destinationLabel': _destination.text.trim(),
        'pickupLatitude': _pickupPoint.latitude,
        'pickupLongitude': _pickupPoint.longitude,
        'destinationLatitude': destinationPoint.latitude,
        'destinationLongitude': destinationPoint.longitude,
        'pickupAt': departure.toUtc().toIso8601String(),
        'bookingType': _travelMode.apiBookingType,
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
        'notes': 'Tour booking • $_tourDays day(s) • '
            '$_tourPassengers passenger(s) • advance payment required',
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

  /// Opens the notifications panel as a dismissible popup.
  ///
  /// Tapping the backdrop, the close button, or anywhere outside dismisses it —
  /// the customer never loses their place on Home.
  Future<void> _openNotifications() async {
    setState(() => _unreadNotifications = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: .62),
      builder: (_) => const _NotificationsPopup(),
    );
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
    final topInset = MediaQuery.paddingOf(context).top;
    final height = MediaQuery.sizeOf(context).height;

    // The sheet is capped so a slice of map is always visible above it. Without
    // the cap a tall tour panel would cover the map entirely and the screen
    // would stop reading as map-first.
    final sheetMaxHeight = height * .62;

    return Container(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildMap(),

          // Header chrome floats directly on the map.
          Positioned(
            top: topInset + 10,
            left: 16,
            right: 16,
            child: SizedBox(
              height: 40,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _LocationControl(
                      expanded: _locationExpanded,
                      placeName: _resolvedPlaceName,
                      onTap: () => setState(
                        () => _locationExpanded = !_locationExpanded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _LanguagePill(
                        isEnglish: controller.locale.languageCode != 'ur',
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
                        showDot: _unreadNotifications,
                        onTap: _openNotifications,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Status strip, sitting just above the sheet.
          Positioned(
            left: 16,
            right: 16,
            bottom: sheetMaxHeight * .5 + 12,
            child: IgnorePointer(
              ignoring: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeTrip != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ActiveTripBanner(
                        trip: _activeTrip!,
                        onTrack: _openActiveTrip,
                      ),
                    ),
                  Row(
                    children: [
                      if (_service.isVehicle)
                        Flexible(
                          child: _NearbyCountChip(
                            service: _service,
                            count: _visibleVehicles.length,
                            loading: _nearbyLoading,
                            offline: _offline,
                          ),
                        ),
                      const Spacer(),
                      _LocateButton(busy: _locating, onTap: _loadLocation),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // The booking sheet.
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: sheetMaxHeight),
              child: _buildSheet(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final vehicles = _visibleVehicles;

    return UdMap(
      controller: _mapController,
      initialCenter: _pickupPoint,
      zoom: 13.4,
      myLocation: _pickupPoint,
      routeOrigin: _pickupPoint,
      routeDestination: _destinationPoint ?? _pickupPoint,
      circles: [
        UdCircle(
          id: 'radius',
          centre: _pickupPoint,
          radiusMetres: AppConfig.nearbyVehiclesRadiusKm * 1000,
        ),
      ],
      markers: [
        for (final vehicle in vehicles)
          UdMarker(
            id: vehicle.id,
            position: vehicle.point,
            label: '${vehicle.category} · '
                '${vehicle.distanceKm.toStringAsFixed(1)} km',
            hue: UdMarkerHue.navy,
            onTap: () => _showVehicleSheet(vehicle),
          ),
        if (_destinationPoint != null)
          UdMarker(
            id: 'destination',
            position: _destinationPoint!,
            label: _destination.text.trim(),
            hue: UdMarkerHue.info,
          ),
      ],
    );
  }

  /// The panel that rides on top of the map.
  Widget _buildSheet() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(color: Color(0x66000000), blurRadius: 26, offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Where to?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 13),
              ServiceSelector(
                selected: _service,
                onChanged: (service) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _service = service;
                    // Hotels are not a vehicle, so per-seat and tour do not apply.
                    if (service == HomeService.hotel) {
                      _travelMode = TravelMode.wholeVehicle;
                    }
                  });
                },
              ),
              const SizedBox(height: 13),
              if (_offline) ...[
                const _OfflineNotice(),
                const SizedBox(height: 12),
              ],
              AnimatedSize(
                duration: AppConfig.panelSwitch,
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _service == HomeService.hotel
                    ? _buildHotelPanel()
                    : _buildVehiclePanel(),
              ),
              const SizedBox(height: 14),
              _StickyCta(
                label: _ctaLabel,
                enabled: _ctaEnabled,
                busy: _submitting,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehiclePanel() {
    return Column(
      key: const ValueKey('vehicle-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The three travel modes sit above the addresses because they change
        // what the customer is buying, not just a detail of it.
        _TravelModeSelector(
          value: _travelMode,
          onChanged: (mode) => setState(() => _travelMode = mode),
        ),
        const SizedBox(height: 13),
        _RouteSummaryFields(
          pickupLabel: _pickup.text,
          destinationLabel: _destination.text,
          locating: _locating,
          onUseMyLocation: _loadLocation,
          onEditPickup: () => _openSearch(RouteFieldKind.pickup),
          onEditDestination: () => _openSearch(RouteFieldKind.destination),
        ),
        AnimatedSize(
          duration: AppConfig.panelSwitch,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: switch (_travelMode) {
            TravelMode.perSeat => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: UdStepper(
                  label: 'Seats',
                  caption: 'Shared ride — you pay per seat',
                  value: _seats,
                  min: 1,
                  max: 12,
                  onChanged: (value) => setState(() => _seats = value),
                ),
              ),
            TravelMode.wholeVehicle => const SizedBox.shrink(),
            TravelMode.tour => _buildTourPanel(),
          },
        ),
      ],
    );
  }

  /// Opens the full-screen address search and applies whatever comes back.
  Future<void> _openSearch(RouteFieldKind field) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<PlacePickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceSearchScreen(
          title: field == RouteFieldKind.pickup
              ? 'Set pickup'
              : 'Set destination',
          pickupLabel: _pickup.text.trim(),
          initialQuery: field == RouteFieldKind.pickup
              ? ''
              : _destination.text.trim(),
          bias: _pickupPoint,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (field == RouteFieldKind.pickup) {
        _pickup.text = result.label;
        _resolvedPlaceName = result.label;
        if (result.point != null) _pickupPoint = result.point!;
      } else {
        _destination.text = result.label;
        // Null means the customer used free text the geocoder could not place.
        // _resolveDestination() geocodes it when they press the button, and
        // falls back to the full route screen if that also fails.
        _destinationPoint = result.point;
      }
    });

    if (result.point != null) {
      await _mapController.moveTo(result.point!, zoom: AppConfig.focusedMapZoom);
      if (field == RouteFieldKind.pickup) await _refreshNearby();
    }
  }

  Widget _buildTourPanel() {
    final dateLabel = DateFormat('EEE, d MMM').format(_tourDate);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One-tap Kashmir destinations. The destination field stays free
          // text, so anywhere else can still be typed.
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: TourDestinations.popular.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final place = TourDestinations.popular[index];
                final selected =
                    _destination.text.trim().toLowerCase() ==
                        place.name.toLowerCase();
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _destination.text = place.name;
                      _destinationPoint =
                          LatLng(place.latitude, place.longitude);
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? AppTint.brand : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: selected
                            ? AppColors.secondary
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      place.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.secondary
                            : AppText.secondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _TapField(
                  caption: 'Departure',
                  value: dateLabel,
                  icon: Icons.calendar_today_rounded,
                  onTap: _pickTourDate,
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 128,
                child: UdStepper(
                  label: 'Days',
                  value: _tourDays,
                  min: 1,
                  max: TourDestinations.maxDays,
                  onChanged: (value) => setState(() => _tourDays = value),
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
            caption: 'Your offer for the whole trip',
            controller: _tourOffer,
            hint: 'e.g. 24000',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 9),
          _AdvanceDisclosure(offer: _tourOffer.text),
        ],
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
                color: AppColors.secondary,
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
                          color: AppColors.surfaceHigh.withValues(alpha: .92),
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
                color: AppColors.surfaceHigh.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(11),
                boxShadow: AppShadows.floating,
              ),
              child: Icon(icon, size: 20, color: AppColors.secondary),
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

/// "6 cars within 5 km" chip over the map.
class _NearbyCountChip extends StatelessWidget {
  const _NearbyCountChip({
    required this.service,
    required this.count,
    required this.loading,
    required this.offline,
  });

  final HomeService service;
  final int count;
  final bool loading;
  final bool offline;

  String get _label {
    if (offline) return 'Offline — vehicles unavailable';
    if (loading) return 'Looking for vehicles…';

    final noun = switch (service) {
      HomeService.bus => count == 1 ? 'coaster' : 'coasters',
      HomeService.car => count == 1 ? 'car' : 'cars',
      HomeService.bike => count == 1 ? 'bike' : 'bikes',
      HomeService.hotel => 'hotels',
    };
    if (count == 0) return 'No $noun nearby right now';
    return '$count $noun within '
        '${AppConfig.nearbyVehiclesRadiusKm.toStringAsFixed(0)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: .40),
        ),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(service.icon, size: 17, color: AppColors.secondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppText.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Centre the map on my location',
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: AppShadows.floating,
          ),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded,
                  size: 19, color: AppColors.secondary),
        ),
      ),
    );
  }
}

/// Opened by tapping a vehicle marker.
///
/// Shows what the customer needs to judge availability and nothing more. The
/// driver's name, plate and phone stay private until a booking is confirmed.
class _VehicleMarkerSheet extends StatelessWidget {
  const _VehicleMarkerSheet({required this.vehicle});

  final NearbyVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.sheetTop(),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTint.brand,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    vehicle.service?.icon ?? Icons.directions_car_rounded,
                    size: 24,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vehicle.category,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppText.primary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${vehicle.distanceKm.toStringAsFixed(1)} km away  ·  '
                        'about ${vehicle.etaMinutes} min',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (vehicle.rating > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 17, color: Color(0xFFF5B942)),
                      const SizedBox(width: 4),
                      Text(
                        vehicle.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppText.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: AppRadii.all(AppRadii.field),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 15, color: AppText.disabled),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      vehicle.bookingMode.allowsPerSeat &&
                              !vehicle.bookingMode.allowsWholeVehicle
                          ? 'Offered per seat.'
                          : vehicle.bookingMode.allowsWholeVehicle &&
                                  !vehicle.bookingMode.allowsPerSeat
                              ? 'Booked as a whole vehicle.'
                              : 'Per seat or whole vehicle.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppText.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Driver details are shared once your booking is confirmed.',
              style: TextStyle(fontSize: 11.5, color: AppText.disabled),
            ),
          ],
        ),
      ),
    );
  }
}

/// Language switch shown as a labelled pill/// Language switch shown as a labelled pill so the current language is
/// readable at a glance rather than hidden behind a glyph.
class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.isEnglish, required this.onTap});

  final bool isEnglish;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Switch language. Currently ${isEnglish ? 'English' : 'Urdu'}.',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(11),
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LanguageChip(label: 'EN', active: isEnglish),
              const SizedBox(width: 3),
              _LanguageChip(label: 'اردو', active: !isEnglish),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.secondary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: active ? AppText.onBrand : AppText.secondary,
        ),
      ),
    );
  }
}

/// Notifications shown as a popup so the customer stays on Home.
class _NotificationsPopup extends StatelessWidget {
  const _NotificationsPopup();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 80),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(AppRadii.panel),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppText.secondary,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 34, color: AppText.disabled),
                      SizedBox(height: 12),
                      Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Trip updates, driver messages and offers will appear '
                        'here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per seat / whole vehicle / tour.
///
/// These three sit together because they are three different products, not
/// three settings — the choice changes what the customer buys, so it belongs
/// above the addresses rather than hidden in a toggle.
class _TravelModeSelector extends StatelessWidget {
  const _TravelModeSelector({required this.value, required this.onChanged});

  final TravelMode value;
  final ValueChanged<TravelMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: TravelMode.values.map((mode) {
          final selected = mode == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: mode.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.secondary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        mode.icon,
                        size: 19,
                        color: selected
                            ? AppText.onBrand
                            : AppText.disabled,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mode.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w600,
                          color: selected
                              ? AppText.onBrand
                              : AppText.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

/// Pickup and destination shown as tappable rows rather than live text fields.
///
/// Typing happens on the dedicated search screen, so this only has to read
/// well: no borders, no boxes, just the route with a connector down the side.
class _RouteSummaryFields extends StatelessWidget {
  const _RouteSummaryFields({
    required this.pickupLabel,
    required this.destinationLabel,
    required this.locating,
    required this.onUseMyLocation,
    required this.onEditPickup,
    required this.onEditDestination,
  });

  final String pickupLabel;
  final String destinationLabel;
  final bool locating;
  final VoidCallback onUseMyLocation;
  final VoidCallback onEditPickup;
  final VoidCallback onEditDestination;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 1.5,
                    height: 32,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    color: AppColors.border,
                  ),
                  Container(width: 8, height: 8, color: AppText.primary),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RouteRow(
                    caption: 'From',
                    value: pickupLabel,
                    onTap: onEditPickup,
                  ),
                  Container(height: 1, color: AppColors.border),
                  _RouteRow(
                    caption: 'To',
                    value: destinationLabel,
                    placeholder: 'Where are you going?',
                    onTap: onEditDestination,
                  ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: locating ? null : onUseMyLocation,
            icon: locating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 16),
            label: Text(locating ? 'Locating…' : 'Use my location'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 34),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.caption,
    required this.value,
    required this.onTap,
    this.placeholder,
  });

  final String caption;
  final String value;
  final String? placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caption,
              style: const TextStyle(fontSize: 11, color: AppText.disabled),
            ),
            const SizedBox(height: 2),
            Text(
              empty ? (placeholder ?? '') : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: empty ? AppText.disabled : AppText.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvanceDisclosure extends StatelessWidget {
  const _AdvanceDisclosure({this.offer});

  /// The customer's typed offer, so the advance can be shown as a real figure
  /// rather than a percentage they have to work out themselves.
  final String? offer;

  String get _text {
    final total = int.tryParse((offer ?? '').trim());
    final percent = (AppConfig.tourAdvancePercent * 100).round();
    if (total == null || total <= 0) {
      return 'Tour bookings need a $percent% advance, held by UDrive and '
          'released to your driver on arrival.';
    }
    final advance = (total * AppConfig.tourAdvancePercent).round();
    return '$percent% advance (PKR $advance) held by UDrive, released to your '
        'driver on arrival.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTint.success,
        borderRadius: AppRadii.all(AppRadii.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 15, color: AppTint.successText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _text,
              style: const TextStyle(
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
        color: AppColors.surfaceAlt,
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
        color: AppColors.surfaceAlt,
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
          color: AppColors.surfaceAlt,
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

/// The primary action at the foot of the booking sheet.
class _StickyCta extends StatelessWidget {
  const _StickyCta({
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
      height: 54,
      child: Material(
        color: enabled ? AppColors.secondary : AppColors.border,
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
                      color: AppText.onBrand,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: enabled ? AppText.onBrand : AppText.disabled,
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
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.secondary.withValues(alpha: .35)),
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
                    color: AppText.secondary,
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
                    color: AppText.primary,
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
                    color: AppText.onBrand,
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
