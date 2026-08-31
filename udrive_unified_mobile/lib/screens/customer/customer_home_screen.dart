import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/maps/ud_map.dart';
import '../../core/routing/route_repository.dart';
import '../../core/vehicles/nearby_repository.dart';
import '../../core/vehicles/nearby_vehicle.dart';
import '../../core/vehicles/tour_rates_repository.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/booking/booking_options.dart';
import '../../core/booking/vehicle_booking_mode.dart';
import '../../core/config/app_config.dart';
import '../../core/places/recent_places_store.dart';
import '../../core/services/place_search_service.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/route_fields.dart';
import '../../core/widgets/home_service.dart';
import '../../core/widgets/ud_controls.dart';
import '../../data/models.dart';
import '../../models/trip_operations_models.dart';
import '../hotels/hotel_list_screen.dart';
import '../operations/live_trip_navigation_screen.dart';
import 'place_search_screen.dart';
import 'tour_map_screen.dart';
import 'vehicle_choice_screen.dart';
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
  /// Seeded with a status line rather than left blank: on first open the app is
  /// actively finding the customer, and an empty field looks broken.
  final _pickup = TextEditingController(text: 'Finding your location…');
  final _destination = TextEditingController();
  final _hotelCity = TextEditingController();
  final _tourOffer = TextEditingController();


  final _places = PlaceSearchService();
  final _routes = RouteRepository();

  Timer? _tripTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  TripOperationsRepository? _tripRepository;
  NearbyVehicleRepository? _nearbyRepository;
  final _mapController = UdMapController();

  /// Scrolls the sheet so the addresses are in view.
  ///
  /// Choosing a service should move the customer forward without them having
  /// to find the next field themselves.
  final _sheetScroll = ScrollController();
  Timer? _nearbyTimer;

  /// Vehicles currently online inside the radius. Filtered by service when
  /// drawn, so switching Car → Bike changes the markers without a refetch.
  List<NearbyVehicle> _nearby = const [];
  bool _nearbyLoading = true;

  /// Destinations used before, newest first. Shown until a destination is
  /// chosen, because most trips repeat.
  List<RecentPlace> _recent = const [];

  /// True while the customer is dragging the map. The centre pin lifts and its
  /// label hides, the way a dropped pin behaves in every map app.
  bool _draggingMap = false;

  /// Set while the address under the pin is being looked up.
  bool _resolvingPin = false;

  /// Guards against reverse-geocoding on every tiny camera settle. Only a move
  /// of real distance is worth a request — each one is billed.
  LatLng? _lastResolvedCentre;

  /// The pin writes the pickup only after the customer has actually dragged the
  /// map.
  ///
  /// Without this, the very first camera idle — which happens at the fallback
  /// centre before GPS has resolved — reverse-geocoded that fallback and wrote
  /// a Kashmir address into the pickup field. The real location arrived a
  /// moment later but the label was already wrong.
  bool _userMovedMap = false;

  /// Set when the device location could not be read. Shown as a banner with a
  /// retry, rather than leaving an instruction sitting in the pickup field
  /// where it reads like an address.
  String? _locationError;

  /// Driving routes for the current pickup → destination pair.
  TripRouteResult _routeResult = const TripRouteResult();
  int _selectedRoute = 0;
  bool _routeLoading = false;

  TripRoute? get _activeRoute => _routeResult.routes.isEmpty
      ? null
      : _routeResult.routes[
          _selectedRoute.clamp(0, _routeResult.routes.length - 1)];

  // ------------------------------------------------------------------- state
  HomeService _service = HomeService.car;
  BookingType _bookingType = BookingType.wholeVehicle;

  /// Seats requested in per-seat mode.
  int _seats = 1;

  /// Tour length in days. A Kashmir tour is rarely a single day, so this
  /// replaces the single departure time the old tour panel used.
  int _tourDays = 3;
  bool _locating = false;
  bool _offline = false;
  bool _submitting = false;
  bool _locationExpanded = false;

  /// True when the booking card has been pulled up over the map.
  ///
  /// The card carries the products and both addresses, and on a short phone
  /// the bottom of it sat under the fold. Rather than shrink the map for
  /// everyone, the customer decides: the handle above "Where to?" lifts the
  /// card over the map and drops it back.
  bool _sheetLifted = false;

  LatLng _pickupPoint =
      const LatLng(AppConfig.fallbackLatitude, AppConfig.fallbackLongitude);
  LatLng? _destinationPoint;
  String _resolvedPlaceName = 'Locating…';


  // Tour options
  DateTime _tourDate = DateTime.now().add(const Duration(days: 1));
  int _tourPassengers = 2;

  /// What tour drivers around here are asking per day.
  ///
  /// Tourism is priced by the driver, not by the admin's rules, so there is no
  /// recommended fare to show. This is the next best thing and it is honest:
  /// the prices drivers have actually published. Without it the customer was
  /// typing a number into a field whose only guidance was a placeholder.
  List<TourRateGuide> _tourGuide = const [];

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
    RecentPlacesStore.load().then((places) {
      if (mounted) setState(() => _recent = places);
    });
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
    _sheetScroll.dispose();
    _connectivity?.cancel();
    _pickup.dispose();
    _destination.dispose();
    _hotelCity.dispose();
    _tourOffer.dispose();
    _places.dispose();
    _routes.dispose();
    super.dispose();
  }

  /// The centre pin only sets pickup while no destination is chosen. Once a
  /// trip is being planned the map is showing a route, and moving it must not
  /// silently rewrite where the customer is starting from.
  bool get _pinActive => _destination.text.trim().isEmpty;

  void _onMapDragStart() {
    if (!_pinActive) return;
    _userMovedMap = true;
    if (_draggingMap) return;
    setState(() => _draggingMap = true);
  }

  /// Reverse-geocodes whatever the pin is now over and makes it the pickup.
  Future<void> _onMapSettled(LatLng centre) async {
    if (!_pinActive) return;
    if (mounted && _draggingMap) setState(() => _draggingMap = false);

    // Camera moves the app made itself — opening, centring on GPS, framing a
    // route — must never rewrite the pickup.
    if (!_userMovedMap) return;

    // Ignore settles that barely moved: a few metres is not a new pickup, and
    // every lookup costs money.
    final previous = _lastResolvedCentre;
    if (previous != null) {
      final moved = (previous.latitude - centre.latitude).abs() +
          (previous.longitude - centre.longitude).abs();
      if (moved < 0.0004) return; // roughly 40 m
    }
    _lastResolvedCentre = centre;

    setState(() {
      _pickupPoint = centre;
      _resolvingPin = true;
    });

    final address = await _places.reverseGeocode(
      centre.latitude,
      centre.longitude,
    );
    if (!mounted) return;

    final label = address.isNotEmpty
        ? address
        : '${centre.latitude.toStringAsFixed(5)}, '
            '${centre.longitude.toStringAsFixed(5)}';

    setState(() {
      _pickup.text = label;
      _resolvedPlaceName = label;
      _resolvingPin = false;
    });

    // Nearby vehicles are measured from the pickup, so they follow the pin.
    await _refreshNearby();
  }

  /// Selects one of the alternative routes.
  ///
  /// Deliberately does not re-frame the camera. The customer is comparing two
  /// roads on screen; moving the map under them while they choose would undo
  /// the comparison they are in the middle of.
  void _selectRoute(int index) {
    if (index < 0 || index >= _routeResult.routes.length) return;
    setState(() => _selectedRoute = index);
  }

  /// Fetches the driving route once both ends are known, then frames it.
  ///
  /// Called on destination change rather than on a timer: a route between two
  /// fixed points does not move, and Directions is billed per request.
  Future<void> _refreshRoute() async {
    final destination = _destinationPoint;
    if (destination == null) {
      setState(() {
        _routeResult = const TripRouteResult();
        _selectedRoute = 0;
      });
      return;
    }

    setState(() => _routeLoading = true);
    final result = await _routes.route(
      origin: _pickupPoint,
      destination: destination,
    );
    if (!mounted) return;

    setState(() {
      _routeResult = result;
      _selectedRoute = 0;
      _routeLoading = false;
    });

    // Frame the whole trip so the customer sees where they are going, not just
    // where they are standing.
    final points = result.best?.points;
    if (points != null && points.isNotEmpty) {
      await _mapController.fitBounds(points, padding: 70);
    } else {
      await _mapController.fitBounds([_pickupPoint, destination], padding: 80);
    }
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
      tourOnly: _service.isTour,
    );
    if (!mounted) return;
    setState(() {
      _nearby = results;
      _nearbyLoading = false;
      _clampBookingType();
    });
  }

  /// Loads the published tour prices once, when Tour is first chosen.
  ///
  /// Not polled: a driver's asking price is not live data, and another timer on
  /// a screen that already runs several would buy nothing.
  Future<void> _loadTourGuide() async {
    if (_tourGuide.isNotEmpty || !mounted) return;

    final controller = AppControllerScope.of(context);
    final guide = await TourRatesRepository(controller.apiClient).guide(
      latitude: _pickupPoint.latitude,
      longitude: _pickupPoint.longitude,
    );

    if (!mounted || guide.isEmpty) return;
    setState(() => _tourGuide = guide);
  }

  List<NearbyVehicle> get _visibleVehicles {
    if (!_service.isVehicle) return const [];
    // Tour is not a vehicle category: any vehicle the driver opted into tours
    // qualifies, whatever its make.
    if (_service.isTour) {
      return _nearby
          .where((vehicle) => vehicle.availableForTour)
          .toList(growable: false);
    }
    return _nearby
        .where((vehicle) => vehicle.service == _service)
        .toList(growable: false);
  }

  /// Booking types the vehicles actually nearby can offer.
  ///
  /// Derived from real capacity rather than assumed from the service: a
  /// 7-seat van under "Car" can still be sold by the seat. With nothing nearby
  /// yet, whole vehicle is the safe default — it is always allowed.
  List<BookingType> get _availableBookingTypes {
    if (!_service.isVehicle) return const [BookingType.wholeVehicle];

    final vehicles = _visibleVehicles;
    if (vehicles.isEmpty) return const [BookingType.wholeVehicle];

    final anyShareable = vehicles.any(
      (vehicle) =>
          SeatRules.allowsPerSeat(vehicle.passengerCapacity) &&
          vehicle.bookingMode.allowsPerSeat,
    );
    return anyShareable
        ? BookingType.values
        : const [BookingType.wholeVehicle];
  }

  /// Snaps the selection back to something legal after the fleet changes.
  void _clampBookingType() {
    if (!_availableBookingTypes.contains(_bookingType)) {
      _bookingType = _availableBookingTypes.first;
    }
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
    if (mounted) {
      setState(() {
        _locating = true;
        _locationError = null;
      });
    }
    _pickup.text = 'Finding your location…';

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setPickupFailure('Location services are off. Turn them on, or set a pickup manually.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _setPickupFailure('Location permission is blocked. Allow it in your browser or device settings.');
        return;
      }
      if (permission == LocationPermission.denied) {
        _setPickupFailure('Allow location access to use your current position.');
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
        _setPickupFailure('Could not read your location. Try again, or set a pickup manually.');
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

      // Seed the pin's guard with this point: the camera move that follows
      // fires an idle event, and without the seed the pin would immediately
      // reverse-geocode the position we just resolved.
      _lastResolvedCentre = point;

      await _mapController.moveTo(point, zoom: AppConfig.pickupZoom);
    } catch (_) {
      _setPickupFailure('Could not read your location. Try again, or set a pickup manually.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _setPickupFailure(String message) {
    if (!mounted) return;
    setState(() {
      _locationError = message;
      // Leave the field empty rather than filling it with an instruction. An
      // empty pickup is honestly empty; a sentence there looks like an address
      // the customer might accept without reading.
      _pickup.text = '';
      _resolvedPlaceName = 'Location unavailable';
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
    if (_service.isTour) {
      final offer = int.tryParse(_tourOffer.text.trim());
      return offer != null && offer > 0;
    }
    return true;
  }

  /// The label on the button that sends the request.
  ///
  /// "Find Now" for every vehicle, rather than naming the one currently
  /// selected. The vehicle is chosen on the next screen anyway, so spelling it
  /// out here promised a decision that had not been made — and the label
  /// changing under the customer's thumb as they switched products made the
  /// button look like a different button each time.
  ///
  /// Hotel and Tour keep their own words because they lead somewhere genuinely
  /// different.
  String get _ctaLabel {
    if (_service == HomeService.hotel) return 'Find Hotels';
    if (_service.isTour) return 'Find Tour Vehicle';
    if (_bookingType == BookingType.perSeat) {
      return 'Find $_seats seat${_seats == 1 ? '' : 's'}';
    }
    return 'Find Now';
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

    if (_service.isTour) {
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
  /// True while a push is in flight, so a fast double tap cannot stack two
  /// copies of the vehicle screen.
  bool _openingVehicles = false;

  Future<void> _openVehicleSelection() async {
    if (_openingVehicles) return;
    _openingVehicles = true;
    try {
      await _pushVehicleSelection();
    } finally {
      _openingVehicles = false;
    }
  }

  Future<void> _pushVehicleSelection() async {
    final destinationPoint = await _resolveDestination();
    if (!mounted) return;

    // With both ends placed, go straight to choosing a vehicle and naming a
    // price. The route is handed over so that screen does not pay for a second
    // Directions call to draw a line we already have.
    if (destinationPoint != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VehicleChoiceScreen(
            pickupLabel: _pickup.text.trim(),
            destinationLabel: _destination.text.trim(),
            pickupPoint: _pickupPoint,
            destinationPoint: destinationPoint,
            route: _activeRoute,
            service: _service,
            bookingType: _bookingType,
            seats: _seats,
          ),
        ),
      );
      return;
    }

    // The typed address could not be geocoded. Fall back to the full route
    // screen, pre-filled, rather than blocking the customer on a place the
    // geocoder does not know.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UDriveRouteFlowScreen(
          serviceType: _bookingType == BookingType.wholeVehicle
              ? UDriveServiceType.privateVehicle
              : UDriveServiceType.city,
          pickupLabel: _pickup.text.trim(),
          pickupPoint: _pickupPoint,
          initialDestinationLabel: _destination.text.trim(),
          onlyVehicleKey: _service.vehicleFilterKey,
          skipRouteEntry: false,
        ),
      ),
    );
  }

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
        'bookingType': _bookingType.apiValue,
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

  /// Raises the card and leaves it raised.
  ///
  /// Called when a destination is chosen. From that point the card carries the
  /// route, the vehicle panel and the button, and letting it settle back over
  /// the map would drop the button under the fold — the customer would pick a
  /// place and then have to scroll to act on it. The handle still works, so
  /// anyone who wants the map back can have it; it just no longer happens on
  /// its own.
  void _liftSheet() {
    if (_sheetLifted || !mounted) return;
    setState(() => _sheetLifted = true);
  }

  /// Raises or lowers the booking card over the map.
  ///
  /// The keyboard is dismissed first: leaving it up while the panel resizes
  /// makes the card jump twice for one gesture.
  void _toggleSheet() {
    FocusScope.of(context).unfocus();
    setState(() => _sheetLifted = !_sheetLifted);
  }

  Future<void> _toggleLanguage(AppController controller) async {
    final next = controller.locale.languageCode == 'ur' ? 'en' : 'ur';
    await controller.setLanguage(next);
  }

  // ------------------------------------------------------------------ building

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final height = MediaQuery.sizeOf(context).height;

    // Lifted, the map keeps just enough of itself to stay a map — the pin, the
    // vehicles around it and the locate button. Hiding it entirely would leave
    // the customer setting a pickup they cannot see.
    final mapHeight = _sheetLifted
        ? (height * .20).clamp(150.0, 230.0)
        : (height * .52).clamp(320.0, 560.0);

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SizedBox(
                height: 40,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UDriveMark(
                      size: 38,
                      // Already home, so this clears anything stacked on top
                      // rather than pushing another copy of it.
                      onTap: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                    ),
                    const Spacer(),
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
              ),
            ),

            AnimatedContainer(
              duration: AppConfig.panelSwitch,
              curve: Curves.easeOutCubic,
              height: mapHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildMap(),

                  if (_pinActive)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: _CentrePin(
                            lifted: _draggingMap,
                            label: _pickup.text.trim(),
                            resolving: _resolvingPin,
                          ),
                        ),
                      ),
                    ),

                  // Fades the map into the sheet so the join does not read as a
                  // hard edge between two panels.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 56,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.background.withValues(alpha: 0),
                              AppColors.background.withValues(alpha: .75),
                              AppColors.background,
                            ],
                            stops: const [0, .6, 1],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floats on the map rather than occupying a strip of its own.
                  Positioned(
                    right: 14,
                    bottom: 60,
                    child: _LocateButton(
                      busy: _locating,
                      onTap: _loadLocation,
                    ),
                  ),

                  if (_service.isVehicle && _pinActive)
                    Positioned(
                      left: 14,
                      bottom: 62,
                      right: 70,
                      child: _NearbyCountChip(
                        service: _service,
                        count: _visibleVehicles.length,
                        loading: _nearbyLoading,
                        offline: _offline,
                      ),
                    ),
                ],
              ),
            ),

            Expanded(child: _buildSheet()),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final vehicles = _visibleVehicles;

    return UdMap(
      controller: _mapController,
      initialCenter: _pickupPoint,
      zoom: AppConfig.pickupZoom,
      myLocation: _pickupPoint,
      onCameraMoveStarted: _onMapDragStart,
      onCameraIdle: _onMapSettled,
      routeOrigin: _pickupPoint,
      routeDestination: _destinationPoint ?? _pickupPoint,
      circles: [
        // The search ring only makes sense while browsing. Once a trip is
        // plotted it just clutters the route.
        if (_activeRoute == null)
          UdCircle(
            id: 'radius',
            centre: _pickupPoint,
            radiusMetres: AppConfig.nearbyVehiclesRadiusKm * 1000,
          ),
      ],
      polylines: [
        // Alternatives first so they sit underneath, muted and tappable. The
        // customer picks a road by pointing at it, as they would in any taxi
        // app, rather than reading a list of street names.
        for (var i = _routeResult.routes.length - 1; i >= 0; i--)
          if (i != _selectedRoute)
            UdPolyline(
              id: 'route-$i',
              points: _routeResult.routes[i].points,
              color: AppText.disabled,
              width: 5,
              onTap: () => _selectRoute(i),
            ),
        // The chosen route is drawn twice: a dark casing and the brand green on
        // top. A single stroke disappears against roads of a similar tone.
        if (_activeRoute != null) ...[
          UdPolyline(
            id: 'route-casing',
            points: _activeRoute!.points,
            color: AppColors.primary,
            width: 10,
          ),
          UdPolyline(
            id: 'route-active',
            points: _activeRoute!.points,
            color: AppColors.secondary,
            width: 6,
          ),
        ],
      ],
      markers: [
        // Drawn as top-down vehicles lying on the road, rotated to the way
        // the driver is facing — not as pins. A pin says something is here; a
        // car pointing down a street says a driver is here and moving, which
        // is what the customer is looking for. Tapping one still opens its
        // details, so nothing is lost by dropping the caption.
        for (final vehicle in vehicles)
          UdMarker(
            id: vehicle.id,
            position: vehicle.point,
            sprite: vehicle.sprite,
            headingDegrees: vehicle.headingDegrees,
            onTap: () => _showVehicleSheet(vehicle),
          ),
        if (_destinationPoint != null)
          UdMarker(
            id: 'destination',
            position: _destinationPoint!,
            label: _destination.text.trim(),
            hue: UdMarkerHue.danger,
          ),
        // With a destination set the pin is gone, so pickup needs its own
        // marker again.
        if (!_pinActive)
          UdMarker(
            id: 'pickup',
            position: _pickupPoint,
            label: _pickup.text.trim(),
          ),
      ],
    );
  }

  /// The panel that rides on top of the map.
  ///
  /// Search-first: one question ("where are you going?") and a weighted set of
  /// services, rather than four controls the customer must fill before anything
  /// happens. Service, booking type and seats are decided on the next screen,
  /// where the route and the real vehicles are known.
  Widget _buildSheet() {
    final hotel = _service == HomeService.hotel;

    // Hotel asks for a city and dates, not a destination, so it opens its own
    // panel straight away. Previously it waited on a destination it never
    // used, which left the product selectable and then apparently inert.
    final planning = hotel || _destination.text.trim().isNotEmpty;

    return ColoredBox(
      // The page behind the panels, not the panels themselves. Two dark greys
      // one step apart is what gives the layout its depth; a single flat
      // surface made every block run into the next.
      color: AppColors.background,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Outside the scroll view, so it stays reachable however far down
            // the card the customer has scrolled.
            _SheetHandle(lifted: _sheetLifted, onToggle: _toggleSheet),
            Expanded(
              child: SingleChildScrollView(
                controller: _sheetScroll,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_activeTrip != null) ...[
                      _ActiveTripBanner(
                        trip: _activeTrip!,
                        onTrack: _openActiveTrip,
                      ),
                      const SizedBox(height: 10),
                    ],

                    // What you are booking.
                    _SheetPanel(
                      child: _ServiceCards(
                        selected: _service,
                        onSelect: _selectService,
                        nearbyCount: _visibleVehicles.length,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Where you are going, and — once that is known —
                    // everything needed to send the request.
                    _SheetPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_locationError != null) ...[
                            _LocationErrorBanner(
                              message: _locationError!,
                              busy: _locating,
                              onRetry: _loadLocation,
                            ),
                            const SizedBox(height: 12),
                          ],

                          if (!planning) ...[
                            // One control, one question, and it is the question
                            // this app actually asks: where, and for how much.
                            // A separate pickup row above it was two fields to
                            // read before the customer could start.
                            _SearchPill(
                              onTap: () =>
                                  _openSearch(RouteFieldKind.destination),
                            ),
                            const SizedBox(height: 10),
                            _PickupRow(
                              label: _pickup.text,
                              busy: _locating || _resolvingPin,
                              onTap: () => _openSearch(RouteFieldKind.pickup),
                            ),
                            if (_recent.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              // Most trips repeat, so the fastest path for a
                              // regular is the one they took last time.
                              ..._recent.map(
                                (place) => _RecentRow(
                                  place: place,
                                  onTap: () => _useRecent(place),
                                ),
                              ),
                            ],
                          ] else ...[
                            if (!hotel) ...[
                              // Both ends stay visible and editable. Hiding
                              // pickup once a destination existed meant a wrong
                              // pickup could not be corrected, which is exactly
                              // when it matters.
                              _RouteSummaryFields(
                                pickupLabel: _pickup.text,
                                destinationLabel: _destination.text,
                                locating: _locating || _resolvingPin,
                                onUseMyLocation: _loadLocation,
                                onEditPickup: () =>
                                    _openSearch(RouteFieldKind.pickup),
                                onEditDestination: () =>
                                    _openSearch(RouteFieldKind.destination),
                              ),
                              _TripSummary(
                                loading: _routeLoading,
                                result: _routeResult,
                                selected: _selectedRoute,
                                hasDestination: true,
                              ),
                            ],
                            const SizedBox(height: 12),
                            AnimatedSize(
                              duration: AppConfig.panelSwitch,
                              curve: Curves.easeOut,
                              alignment: Alignment.topCenter,
                              child: hotel
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectService(HomeService service) {
    FocusScope.of(context).unfocus();
    // Hotel opens its own panel straight away, so it needs the room now rather
    // than after a destination it never asks for.
    if (service == HomeService.hotel) _liftSheet();
    // Tour is priced by drivers, so the customer needs to know what they ask
    // before naming an offer.
    if (service.isTour) unawaited(_loadTourGuide());
    setState(() {
      _service = service;
      if (service == HomeService.hotel) {
        _bookingType = BookingType.wholeVehicle;
      }
      _clampBookingType();
    });
    // Tour queries a different vehicle set, so the map has to refetch.
    _refreshNearby();

    // Choosing a product is the customer saying what they want; the next thing
    // they have to give is where they are going. Opening the destination
    // search straight away with the cursor already in the field removes the
    // separate tap on the To row that used to sit between the two.
    //
    // This now happens whether or not a destination is already set: tapping a
    // product means they are starting the trip again, and re-entering with the
    // old text selected is faster than clearing it by hand. Hotels are the
    // exception — that flow asks for dates and a city, not a destination.
    if (service != HomeService.hotel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_sheetScroll.hasClients) {
          _sheetScroll.animateTo(
            _sheetScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
        _openSearch(RouteFieldKind.destination);
      });
    }
  }

  Future<void> _useRecent(RecentPlace place) async {
    setState(() {
      _destination.text = place.title;
      _destinationPoint = place.point;
    });
    await _refreshRoute();
    _liftSheet();

    // A recent is a destination the customer has already been to and has just
    // named again. Stopping here to make them press a second button would be
    // asking them to confirm something they have already said.
    if (!mounted) return;
    if (_destinationPoint != null && _service != HomeService.hotel) {
      await _openVehicleSelection();
    }
  }

  Widget _buildVehiclePanel() {
    return Column(
      key: const ValueKey('vehicle-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BookingTypeSelector(
          value: _bookingType,
          available: _availableBookingTypes,
          onChanged: (mode) => setState(() => _bookingType = mode),
        ),
        AnimatedSize(
          duration: AppConfig.panelSwitch,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: switch (_bookingType) {
            BookingType.perSeat => Padding(
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
            BookingType.wholeVehicle => const SizedBox.shrink(),
          },
        ),
        // Tour adds its own dates, days, passengers and offer.
        if (_service.isTour) _buildTourPanel(),
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
          editingPickup: field == RouteFieldKind.pickup,
          pickupLabel: _pickup.text.trim(),
          destinationLabel: _destination.text.trim(),
          initialQuery: field == RouteFieldKind.pickup
              ? _pickup.text.trim()
              : _destination.text.trim(),
          bias: _pickupPoint,
        ),
      ),
    );
    if (result == null || !mounted) return;

    // "Use my current location" re-reads GPS rather than trusting a label.
    if (result.useCurrentLocation) {
      await _loadLocation();
      if (!mounted) return;
      // Nearby vehicles are measured from the pickup, so both refresh.
      await _refreshNearby();
      await _refreshRoute();
      return;
    }

    // The search screen lets the customer switch ends, so use what it reports
    // rather than the field we opened it for.
    final wasPickup = result.forPickup;

    setState(() {
      if (wasPickup) {
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

    // Only remember places with coordinates — a name we cannot place again is
    // no use as a shortcut.
    if (!wasPickup && result.point != null) {
      await RecentPlacesStore.remember(
        RecentPlace(
          title: result.label,
          subtitle: '',
          latitude: result.point!.latitude,
          longitude: result.point!.longitude,
        ),
      );
      final refreshed = await RecentPlacesStore.load();
      if (mounted) setState(() => _recent = refreshed);
    }

    if (wasPickup && result.point != null) {
      await _refreshNearby();
    }
    // A route needs both ends; _refreshRoute clears itself when one is missing.
    await _refreshRoute();

    // With a destination the card carries the route, the vehicle panel and the
    // button, so it comes up over the map and stays there.
    if (_destination.text.trim().isNotEmpty) _liftSheet();

    // Picking a destination is the customer saying where they want to go, so
    // carry them straight to choosing a vehicle. Requiring a separate button
    // afterwards was a step that asked them to confirm something they had just
    // done.
    //
    // Hotels are excluded: that flow needs dates and guests first.
    if (!wasPickup &&
        mounted &&
        _destinationPoint != null &&
        _service != HomeService.hotel) {
      await _openVehicleSelection();
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
                    _refreshRoute();
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
          if (_tourGuide.isNotEmpty) ...[
            const SizedBox(height: 9),
            _TourRateGuideCard(guide: _tourGuide, days: _tourDays),
          ],
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
/// The grab handle above "Where to?".
///
/// Tapping it lifts the booking card over the map or drops it back; dragging it
/// does the same, because a bar that looks draggable and is not reads as a
/// broken control. The label states which way the next press goes rather than
/// showing a bare chevron nobody has to guess about.
/// A rounded block on the page.
///
/// The sheet is two of these — what you are booking, then where you are going.
/// Grouping them this way is what makes the screen readable at a glance: one
/// long column of controls all on the same surface gave the eye nowhere to
/// stop.
/// What tour drivers around here charge per day.
///
/// Shown instead of a recommended fare, because there is no recommendation to
/// make: tourism is priced by each driver for their own vehicle, and the
/// platform quoting a figure would be inventing a price nobody set.
///
/// The range is the honest shape of that. A single average would read as an
/// official rate and hide that a Coster and a car are different propositions.
class _TourRateGuideCard extends StatelessWidget {
  const _TourRateGuideCard({required this.guide, required this.days});

  final List<TourRateGuide> guide;
  final int days;

  static String _money(double value) {
    final rounded = (value / 100).round() * 100;
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.sell_outlined, size: 15, color: AppText.disabled),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  days > 1
                      ? 'What drivers ask · $days days'
                      : 'What drivers ask · per day',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppText.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in guide) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      entry.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'PKR ${_money(entry.lowestPerDay * days)}'
                      ' – ${_money(entry.highestPerDay * days)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.vehicleCount}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppText.disabled,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Each driver sets their own tour price. Offer what you think the '
            'trip is worth — drivers reply with theirs.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppText.disabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetPanel extends StatelessWidget {
  const _SheetPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.panel),
      ),
      child: child,
    );
  }
}

/// The one question the app asks.
///
/// "Where to & for how much?" rather than "Where to?" because naming the price
/// is the whole model — a customer who does not know that until the next screen
/// is being asked to discover it.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: AppRadii.all(AppRadii.largeCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.largeCard),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 24, color: AppText.primary),
              SizedBox(width: 13),
              Expanded(
                child: Text(
                  'Where to & for how much?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                    color: AppText.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pickup as one quiet line under the search control.
///
/// The map already shows the pickup on its own pin, so repeating it as a full
/// field competed with the question above it. It stays tappable because a
/// wrong pickup has to be fixable without first choosing a destination.
class _PickupRow extends StatelessWidget {
  const _PickupRow({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = label.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text.isEmpty ? 'Set a pickup point' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppText.secondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Text(
                'Change',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.lifted, required this.onToggle});

  final bool lifted;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: lifted ? 'Show more map' : 'Show more of the booking card',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        // A drag in the direction it is not already in toggles it. Dragging
        // the way it already sits does nothing, so the gesture cannot fight
        // itself mid-flick.
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -80 && !lifted) onToggle();
          if (velocity > 80 && lifted) onToggle();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedRotation(
                turns: lifted ? .5 : 0,
                duration: AppConfig.panelSwitch,
                child: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: AppText.disabled,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                lifted ? 'Show map' : 'More',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppText.disabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            const UDriveMark(size: 38),
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
      HomeService.tour => count == 1 ? 'tour vehicle' : 'tour vehicles',
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
            // Which build is actually running. Checking this first turns "the
            // fix did not work" into "the fix is not deployed" in one glance.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Text(
                AppConfig.buildLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppText.disabled,
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
/// Per seat / whole vehicle.
///
/// Only the types the nearby vehicles can actually offer are shown. With five
/// seats or fewer there is nothing to share, so per seat is hidden rather than
/// shown-and-rejected — a disabled control the customer cannot use is worse
/// than one that was never there.
/// Pickup pin fixed at the centre of the map.
///
/// The map moves beneath it, the pin does not — the same interaction every
/// major map app uses, because it lets someone place a pickup precisely without
/// having to hit a small target with their thumb.
///
/// While dragging, the pin lifts and its label hides: the address underneath is
/// unknown until the map settles, and showing a stale one would be a lie.
class _CentrePin extends StatelessWidget {
  const _CentrePin({
    required this.lifted,
    required this.label,
    required this.resolving,
  });

  final bool lifted;
  final String label;
  final bool resolving;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: lifted ? 0 : 1,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 230),
            padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pickup point',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppText.secondary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      resolving
                          ? const SizedBox(
                              height: 15,
                              width: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              label.isEmpty ? 'Move the map' : label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: AppText.primary,
                              ),
                            ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppText.secondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        // A white tile with a waiting passenger on it, not a coloured teardrop.
        // The map underneath is dark and full of green route line and green
        // vehicle lamps; a green pin on top of that disappears into its own
        // app. White is the one tone nothing else on this map uses.
        //
        // The head lifts on drag while the dot below stays on the ground point,
        // so the customer can see exactly which spot will be used.
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, lifted ? -7 : 0, 0),
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            boxShadow: AppShadows.card,
          ),
          child: const Icon(
            Icons.emoji_people_rounded,
            size: 22,
            color: AppColors.primary,
          ),
        ),
        Container(width: 2, height: 12, color: Colors.white),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.info,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ],
    );
  }
}

/// Ride, Tour and Hotel, weighted and colour-coded.
///
/// Ride takes the tall card on the left because it is most of the traffic;
/// Tour and Hotel stack beside it at half height. Each owns a hue, so the three
/// products read as three things rather than three shades of the brand.
///
/// Per-seat is not a card here — it is how you buy a ride, not a separate
/// product, so it lives in the booking-type row once a destination is set.
class _ServiceCards extends StatelessWidget {
  const _ServiceCards({
    required this.selected,
    required this.onSelect,
    required this.nearbyCount,
  });

  final HomeService selected;
  final ValueChanged<HomeService> onSelect;
  final int nearbyCount;

  bool get _rideSelected =>
      selected == HomeService.car ||
      selected == HomeService.bus ||
      selected == HomeService.bike;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 27,
            child: _ProductCard(
              title: 'Ride now',
              subtitle: nearbyCount > 0
                  ? 'Car · Bike · Coster · Hiace  ·  $nearbyCount nearby'
                  : 'Car · Bike · Coster · Hiace',
              icon: Icons.directions_car_rounded,
              surface: AppProduct.rideSurface,
              accent: AppProduct.rideAccent,
              titleInk: AppProduct.rideTitle,
              subInk: AppProduct.rideSub,
              selected: _rideSelected,
              large: true,
              onTap: () => onSelect(HomeService.car),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ProductCard(
                    title: 'Tour',
                    subtitle: 'Multi-day',
                    icon: Icons.terrain_rounded,
                    surface: AppProduct.tourSurface,
                    accent: AppProduct.tourAccent,
                    titleInk: AppProduct.tourTitle,
                    subInk: AppProduct.tourSub,
                    selected: selected == HomeService.tour,
                    large: false,
                    onTap: () => onSelect(HomeService.tour),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _ProductCard(
                    title: 'Hotel',
                    subtitle: 'Stays',
                    icon: Icons.apartment_rounded,
                    surface: AppProduct.hotelSurface,
                    accent: AppProduct.hotelAccent,
                    titleInk: AppProduct.hotelTitle,
                    subInk: AppProduct.hotelSub,
                    selected: selected == HomeService.hotel,
                    large: false,
                    onTap: () => onSelect(HomeService.hotel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.surface,
    required this.accent,
    required this.titleInk,
    required this.subInk,
    required this.selected,
    required this.large,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color surface;
  final Color accent;
  final Color titleInk;
  final Color subInk;
  final bool selected;
  final bool large;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Unselected tiles drop to the neutral surface and muted ink, so the chosen
    // product is unmistakable rather than one of three bright boxes.
    final background = selected ? surface : AppColors.surfaceAlt;

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(large ? 20 : 16),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.4,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Oversized artwork bleeding off the bottom corner, with the
              // label reading from the top. The eye lands on the word first
              // and the picture only confirms it — the other way round, four
              // tiles read as four pictures with captions.
              Positioned(
                right: large ? -18 : -10,
                bottom: large ? -16 : -10,
                child: Icon(
                  icon,
                  size: large ? 104 : 58,
                  color: accent.withValues(alpha: selected ? .38 : .16),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(large ? 14 : 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: large ? 17 : 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                        color: selected ? titleInk : AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: large ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: large ? 11.5 : 10.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: selected ? subInk : AppText.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationErrorBanner extends StatelessWidget {
  const _LocationErrorBanner({
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
      decoration: BoxDecoration(
        color: AppTint.warning,
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_rounded,
              size: 17, color: AppTint.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppTint.warningText,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppTint.warningText,
              minimumSize: const Size(0, 34),
            ),
            child: Text(busy ? '…' : 'Retry'),
          ),
        ],
      ),
    );
  }
}

/// A destination used before. One tap sets it and plots the route.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.place, required this.onTap});

  final RecentPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.row),
      child: Padding(
        // No divider and no trailing chevron. Inside a panel the rows already
        // read as a list, and two extra marks per row on the busiest part of
        // the screen bought nothing.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.history_rounded,
                size: 21, color: AppText.disabled),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    place.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppText.primary,
                    ),
                  ),
                  if (place.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      place.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppText.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.loading,
    required this.result,
    required this.selected,
    required this.hasDestination,
  });

  final bool loading;
  final TripRouteResult result;
  final int selected;
  final bool hasDestination;

  @override
  Widget build(BuildContext context) {
    if (!hasDestination) return const SizedBox.shrink();

    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: AppRadii.all(AppRadii.row),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 11),
              Text(
                'Working out the route…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppText.secondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!result.hasRoute) {
      final message = switch (result.failure) {
        RouteFailure.noKey =>
          'Travel time is unavailable until an admin adds the Google key.',
        RouteFailure.notFound =>
          'No driving route found between these two points.',
        _ => 'Could not work out the route.',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: AppTint.warning,
            borderRadius: AppRadii.all(AppRadii.row),
          ),
          child: Row(
            children: [
              const Icon(Icons.route_outlined,
                  size: 16, color: AppTint.warningText),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppTint.warningText,
                      ),
                    ),
                    if (result.detail != null &&
                        result.detail!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        result.detail!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppText.disabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final active = result.routes[selected.clamp(0, result.routes.length - 1)];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTint.brand,
              borderRadius: AppRadii.all(AppRadii.row),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: .35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 19, color: AppColors.secondary),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${active.durationLabel}  ·  ${active.distanceLabel}',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppText.primary,
                        ),
                      ),
                      if (active.summary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'via ${active.summary}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // No chips for the alternatives.
          //
          // They are chosen by tapping the road on the map, which is more
          // direct and how every taxi app works. A duplicate list here would be
          // a second way to do the same thing, and a second thing to keep in
          // step with the map.
          if (result.routes.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.alt_route_rounded,
                    size: 14, color: AppText.disabled),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${result.routes.length - 1} other '
                    '${result.routes.length == 2 ? 'route' : 'routes'} — tap '
                    'one on the map',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppText.disabled,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BookingTypeSelector extends StatelessWidget {
  const _BookingTypeSelector({
    required this.value,
    required this.available,
    required this.onChanged,
  });

  final BookingType value;
  final List<BookingType> available;
  final ValueChanged<BookingType> onChanged;

  @override
  Widget build(BuildContext context) {
    if (available.length < 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(available.first.icon, size: 18, color: AppColors.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                available.first == BookingType.wholeVehicle
                    ? 'Whole vehicle — nearby vehicles seat 5 or fewer'
                    : 'Per seat only',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppText.secondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: available.map((mode) {
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
                    color:
                        selected ? AppColors.secondary : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        mode.icon,
                        size: 19,
                        color:
                            selected ? AppText.onBrand : AppText.disabled,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mode.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    placeholder: locating
                        ? 'Finding your location…'
                        : 'Set a pickup point',
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
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
