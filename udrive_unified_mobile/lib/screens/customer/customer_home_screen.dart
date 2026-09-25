import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/maps/ud_map.dart';
import '../../core/places/place_name.dart';
import '../../core/routing/route_repository.dart';
import '../../core/services/service_availability_repository.dart';
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
import '../../core/widgets/steering_wheel_icon.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/route_fields.dart';
import '../../core/widgets/home_service.dart';
import '../../core/widgets/ud_controls.dart';
import '../../core/widgets/ud_kit.dart';
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
  const CustomerHomeScreen({
    required this.onNavigate,
    this.onOpenMenu,
    super.key,
  });

  final ValueChanged<String> onNavigate;

  /// Opens the shell's drawer.
  ///
  /// Home is the one customer screen with no AppBar, so Scaffold never inserts
  /// the hamburger — and the map swallows the edge-drag that would otherwise
  /// open the drawer. The result was a menu attached to the screen with no way
  /// to reach it. Passed in the same way as onNavigate rather than reaching
  /// for a Scaffold this widget sits below.
  final VoidCallback? onOpenMenu;

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

  /// Which services the admin has open, keyed as the portal keys them.
  ///
  /// Empty means everything is open — see [ServiceAvailabilityRepository]. A
  /// failed call must not close the app.
  Map<String, ServiceAvailability> _availability = const {};
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
  /// The booking card starts raised, showing everything from the products down
  /// to the recent destinations.
  ///
  /// It used to start low, with the card cut off below the fold and a handle to
  /// pull it up. That put the ordinary path — pick a product, name a
  /// destination — behind a gesture, and the map it was making room for is not
  /// what a customer opens the app to look at.
  bool _sheetLifted = true;

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
    // Everything from a driver being assigned to the trip ending.
    //
    // `Confirmed` and `DriverAssigned` were missing, which is why a second
    // booking could still be started while a car was already on its way — the
    // banner appeared, but nothing treated that as "a ride is running".
    //
    // `DriverAccepted` is the status trip_operations is actually created with
    // when a customer picks an offer (BookingService.SelectDriverOffer). It was
    // absent from every client-side "is a ride running?" set while the driver
    // side has always included it, so between accepting an offer and the driver
    // pressing "on my way" the app believed nothing was happening. Matches the
    // driver-busy list in BookingService.
    'DriverAccepted',
    'Confirmed',
    'DriverAssigned',
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocation();
      _loadAvailability(AppControllerScope.of(context));
    });
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
      radiusKm: ServiceAvailabilityRepository.nearbyRadiusKm,
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
    showUdSheet<void>(
      context: context,
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

      // The pickup point, so it is worth waiting for a good fix.
      //
      // `best` rather than `high`: this single reading decides where a driver
      // is sent, and a hundred metres of error is the difference between the
      // right gate and the wrong street. It is taken once, not continuously,
      // so the battery cost is a rounding error.
      //
      // The last-known fallback is kept for the case where no fix arrives at
      // all — a stale pickup the customer can correct beats a blank map — but
      // it is only reached after the good one has failed.
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        // A stale fix is worse than no fix here.
        //
        // `getLastKnownPosition` returns wherever the phone was when it last
        // looked, which may be an hour ago and a street away — and there is
        // nothing in the answer to say so. The customer sees a confident
        // pickup on the wrong road and sends a driver there.
        //
        // Only accepted when it is recent. Beyond two minutes they are asked
        // to try again instead, which is honest about not knowing.
        final last = await Geolocator.getLastKnownPosition();
        final age = last?.timestamp == null
            ? null
            : DateTime.now().difference(last!.timestamp);
        if (last != null && age != null && age.inMinutes < 2) {
          position = last;
        }
      }

      if (position == null) {
        _setPickupFailure('Could not read your location. Try again, or set a pickup manually.');
        return;
      }

      // A fix the phone itself calls vague is not a pickup point.
      //
      // `accuracy` is the radius the device believes it is within. Above about
      // 60 metres that circle covers more than one street, which is exactly
      // the "it says Street 20 and I am on Street 19" case — so the pin is
      // shown where it is, and the customer is told to check it rather than
      // being handed a precise-looking address that is not.
      _pickupUncertain = position.accuracy > 60;

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
      // The same one-ride-at-a-time guard the vehicle path uses. It used to
      // live only inside _pushVehicleSelection, and this branch returns before
      // ever reaching it — so a tour could be requested on top of a running
      // ride, and the server's refusal arrived after the whole form was filled.
      if (await _blockedByActiveRide()) return;
      await _submitTour();
      return;
    }

    await _openVehicleSelection();
  }

  /// True when a ride is already under way, after showing the customer why.
  ///
  /// Opens the running ride rather than only refusing: that is what they would
  /// have to do next anyway, and it answers the question instead of blocking it.
  Future<bool> _blockedByActiveRide() async {
    if (_activeTrip == null) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You already have a ride under way. Finish or cancel it before '
          'booking another.',
        ),
      ),
    );
    await _openActiveTrip();
    return true;
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
    // One ride at a time, stopped here rather than at the end.
    //
    // The server refuses a second booking, but only after the customer has
    // picked a destination, chosen a vehicle, named a fare and pressed Find
    // offers. Being told "no" at the end of all that is worse than not being
    // offered the path — they have to work out what they did wrong, and the
    // answer is a ride they may have forgotten is running.
    //
    // So it opens the ride instead. That is what they would have to do next
    // anyway, and it answers the question rather than blocking it.
    if (await _blockedByActiveRide()) return;
    if (!mounted) return;

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
            // All of them, so the next screen can offer the choice and reprice
            // against it. Fetched once here; a second call would cost money to
            // return the same answer.
            routes: _routeResult.routes,
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
  /// Lowers the card. It does not raise it again.
  ///
  /// One direction on purpose. The handle exists so someone can get a longer
  /// look at the map; raising the card back is what tapping anything on it
  /// already does, and a control that means two opposite things depending on
  /// hidden state is a control people stop trusting.




  // ------------------------------------------------------------------ building

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.paddingOf(context).top;

    // The design's map band is 300px on a 390-wide artboard. Kept as a
    // proportion so it is still a map on a small phone and still leaves room
    // for the booking card on a tall one, plus the status bar the controls
    // float under.
    final mapHeight = (height * .32).clamp(250.0, 340.0) + topInset;

    // How far the booking card rides up over the map. The design's -24.
    const overlap = 24.0;

    return ColoredBox(
      color: AppColors.background,
      // Every child of this Stack is positioned, so the Stack has no size of
      // its own and would collapse under loose constraints. `expand` gives it
      // whatever the parent allows, whether that parent hands down tight
      // constraints or not.
      child: SizedBox.expand(
        child: Stack(
        children: [
          // The map, fixed at the top, with everything that floats on it.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: mapHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildMap(),

                if (_pinActive)
                  Positioned.fill(
                    // No offset. The pin marks the map's centre, and the map's
                    // centre is the pickup point — so the pin has to sit
                    // exactly there or it is pointing at somewhere else.
                    //
                    // An earlier fix pushed it down to clear the header, which
                    // moved it off the centre it represents. That is why the
                    // pin appeared on Street 20 while the blue dot — the real
                    // position — sat on Street 19: the dot was right, the pin
                    // was drawn a header's height away from what it meant.
                    child: IgnorePointer(
                      child: Center(
                        child: _CentrePin(
                          lifted: _draggingMap,
                          label: _shortPlace(_pickup.text),
                          resolving: _resolvingPin,
                        ),
                      ),
                    ),
                  ),

                // Everything that floats on the map, in one column.
                //
                // These were four separate `Positioned` widgets at fixed
                // offsets, and when the map shrank they landed on top of one
                // another. A column cannot overlap itself: the header takes the
                // height it needs, the spacer absorbs what is left, and the
                // recentre button sits above the map's edge at any map height.
                SafeArea(
                  bottom: false,
                  child: Padding(
                    // Bottom padding clears the booking card, which rides up
                    // over the last 24px of the map.
                    padding: const EdgeInsets.fromLTRB(
                        16, 10, 16, overlap + 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _mapControls(controller),
                        const Spacer(),
                        Row(
                          children: [
                            const Spacer(),
                            _LocateButton(
                              busy: _locating,
                              onTap: _loadLocation,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // The page under the card. It starts at the map's bottom edge, so the
          // 24px the card overlaps by still shows map on either side of its
          // rounded corners — which is what makes the card read as sitting on
          // the map rather than below it.
          Positioned(
            top: mapHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: const ColoredBox(color: AppColors.surface),
          ),

          // The scrolling page. Transparent, and it begins one overlap above
          // the seam.
          Positioned(
            top: mapHeight - overlap,
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildSheet(),
          ),
        ],
        ),
      ),
    );
  }

  /// The row of controls floating on the map: the menu and the mark on the
  /// left, driver mode and notifications on the right.
  Widget _mapControls(AppController controller) {
    return Row(
      children: [
        if (widget.onOpenMenu != null) ...[
          UdIconButton(
            icon: Icons.menu_rounded,
            variant: UdIconButtonVariant.float,
            tooltip: 'Open menu',
            onPressed: widget.onOpenMenu!,
          ),
          const SizedBox(width: 10),
        ],
        // The mark and the wordmark in one white pill, as the design draws it.
        GestureDetector(
          // Already home, so this clears anything stacked on top rather than
          // pushing another copy.
          onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: AppSizes.iconButton,
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadii.all(15),
              boxShadow: AppShadows.floating,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const UDriveMark(size: 30),
                const SizedBox(width: 7),
                Text(
                  AppConfig.appName,
                  style: AppType.listTitle.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        UdFloatButton(
          // A steering wheel, not a car. Material has no steering-wheel glyph
          // and `drive_eta` is a car seen from the side, which reads as "a
          // vehicle" rather than "you are driving it" — and that distinction is
          // the whole point of this button.
          child: const SteeringWheelIcon(size: 22, color: AppColors.navy),
          onPressed: () => controller.switchMode(UserMode.driver),
          tooltip: 'Switch to driver mode',
        ),
        const SizedBox(width: 10),
        UdIconButton(
          icon: Icons.notifications_none_rounded,
          variant: UdIconButtonVariant.float,
          badgeDot: _unreadNotifications,
          tooltip: 'Notifications',
          onPressed: _openNotifications,
        ),
      ],
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
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: _sheetScroll,
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 0, AppSizes.sidePadding, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The hero slot. A ride already under way takes it: booking a
            // second one is refused by `_blockedByActiveRide` anyway, so the
            // ordinary "Where to?" form here would be a question with a
            // foregone answer. The card that replaces it goes where the
            // customer is already looking.
            if (_activeTrip != null)
              _ActiveTripBanner(trip: _activeTrip!, onTrack: _openActiveTrip)
            else
              _bookingCard(),

            const SizedBox(height: 22),

            if (_offline) ...[
              const _OfflineNotice(),
              const SizedBox(height: 16),
            ],

            const UdSectionHeader(title: 'Services'),
            const SizedBox(height: 12),

            _ServiceCards(
              selected: _service,
              cityRides: _availabilityOf('cityRides'),
              tour: _availabilityOf('tour'),
              cityToCity: _availabilityOf('cityToCity'),
              onSelect: _selectService,
              onClosed: _serviceClosed,
              nearbyCount: _visibleVehicles.length,
            ),
            const SizedBox(height: 12),

            // The second rank: things people reach for less often, as icons
            // rather than cards. A card carries a title, a subtitle and a
            // picture, and four of them side by side is four things competing.
            _QuickRow(
              selected: _service,
              hotels: _availabilityOf('hotels'),
              carRental: _availabilityOf('carRental'),
              coster: _availabilityOf('coster'),
              explore: _availabilityOf('explore'),
              onSelect: _selectService,
              onExplore: _openExplore,
              onClosed: _serviceClosed,
            ),

            const SizedBox(height: 16),
            // `_shareApp` has been in this file all along with nothing calling
            // it — the invite row it belonged to was lost in an earlier pass.
            // The design has it back.
            _InviteRow(onTap: _shareApp),
          ],
        ),
      ),
    );
  }

  /// The white card that overlaps the map: one question, and everything needed
  /// to answer it.
  Widget _bookingCard() {
    final hotel = _service == HomeService.hotel;

    // Hotel asks for a city and dates, not a destination, so it opens its own
    // panel straight away. Previously it waited on a destination it never used,
    // which left the product selectable and then apparently inert.
    final planning = hotel || _destination.text.trim().isNotEmpty;

    return UdCard(
      tone: UdCardTone.raised,
      radius: AppRadii.largeCard,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hotel ? 'Where are you staying?' : 'Where to?',
            style: AppType.h2.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 14),

          if (_locationError != null) ...[
            _LocationErrorBanner(
              message: _locationError!,
              busy: _locating,
              onRetry: _loadLocation,
            ),
            const SizedBox(height: 14),
          ],

          if (!planning) ...[
            // One control, one question, and it is the question this app
            // actually asks. A separate pickup row above it was two fields to
            // read before the customer could start.
            _SearchPill(onTap: () => _openSearch(RouteFieldKind.destination)),
            const SizedBox(height: 10),
            _PickupRow(
              uncertain: _pickupUncertain,
              label: _pickup.text,
              busy: _locating || _resolvingPin,
              onTap: () => _openSearch(RouteFieldKind.pickup),
            ),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 4),
              // Most trips repeat, so the fastest path for a regular is the one
              // they took last time.
              ..._recent.map(
                (place) => _RecentRow(
                  place: place,
                  onTap: () => _useRecent(place),
                ),
              ),
            ],
          ] else ...[
            if (!hotel) ...[
              // Both ends stay visible and editable. Hiding pickup once a
              // destination existed meant a wrong pickup could not be
              // corrected, which is exactly when it matters.
              _RouteSummaryFields(
                pickupLabel: _pickup.text,
                destinationLabel: _destination.text,
                locating: _locating || _resolvingPin,
                onUseMyLocation: _loadLocation,
                onEditPickup: () => _openSearch(RouteFieldKind.pickup),
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
            const SizedBox(height: 14),
            AnimatedSize(
              duration: AppConfig.panelSwitch,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: hotel ? _buildHotelPanel() : _buildVehiclePanel(),
            ),
            const SizedBox(height: 18),
            _StickyCta(
              label: _ctaLabel,
              enabled: _ctaEnabled,
              busy: _submitting,
              onTap: _submit,
            ),
          ],
        ],
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

  /// Car rental is on the home screen before it exists.
  ///
  /// Shown with a badge and a plain answer rather than hidden, because the
  /// question "can I rent a car myself" is one customers ask and the app
  /// currently gives no answer to at all — not even "no". A tile that says
  /// "not yet" is more use than an absence they have to guess at.
  ///
  /// It does nothing else on purpose. A form that collects interest and posts
  /// it nowhere would be worse than this.
  /// True when the fix was too vague to name a street with.
  ///
  /// Drives a prompt to check the pin. It is not an error — a vague fix in a
  /// narrow street is normal — but presenting it as a confident address is how
  /// a driver ends up one road over.
  bool _pickupUncertain = false;

  /// The place name, from the shared helper.
  ///
  /// This used to be a private copy here. The destination screen needed the
  /// same thing and did not have it, which is how one screen ended up showing
  /// "Unity Plaza" and the other a Plus Code for the same point.
  static String _shortPlace(String address) => shortPlaceName(address);

  /// Loads the service switches: cache first, then the server.
  Future<void> _loadAvailability(AppController controller) async {
    final cached = await ServiceAvailabilityRepository.readCache();
    if (cached.isNotEmpty && mounted) {
      setState(() => _availability = cached);
    }

    final fresh =
        await ServiceAvailabilityRepository(controller.apiClient).refresh();
    if (fresh.isNotEmpty && mounted) {
      setState(() => _availability = fresh);
    }
  }

  /// The switch for one service, or an open default.
  ///
  /// Defaulting to open matters: a key the server has not heard of, or a call
  /// that failed, leaves the service working. Closing on absence would mean one
  /// bad response takes the whole home screen down.
  ServiceAvailability _availabilityOf(String key) =>
      _availability[key] ??
      ServiceAvailability(
        key: key,
        isOpen: true,
        badgeLabel: 'SOON',
        closedMessage: 'This service is not open yet.',
      );

  /// Tapping a closed tile says why, in the admin's own words.
  void _serviceClosed(ServiceAvailability service) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(service.closedMessage)),
    );
  }

  void _carRentalNotReady() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Self-drive car rental is not open yet. It is being worked on.',
        ),
      ),
    );
  }

  void _openExplore() {
    // Explore lives in the drawer today, so this points at the nearest thing
    // that exists rather than at a screen that does not.
    _selectService(HomeService.tour);
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
                        fontSize: 14,
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
                    fontSize: 13,
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
                        fontSize: 14,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.vehicleCount}',
                    style: const TextStyle(
                      fontSize: 13,
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
              fontSize: 12,
              height: 1.4,
              color: AppText.disabled,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one question the app asks, before a destination is known.
///
/// A `.field`-shaped inset: the same 58px box and 16px radius as every other
/// input in the app, so it reads as something to fill in rather than as a
/// button that happens to have a magnifier on it.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.all(AppRadii.field),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.field),
        child: SizedBox(
          height: AppSizes.field,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 22, color: AppText.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Where to & for how much?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.listTitle.copyWith(
                      fontSize: 16.5,
                      color: AppText.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pickup as one quiet line under the search control.
///
/// The map already shows the pickup on its own pin, so repeating it as a full
/// field competed with the question above it. It stays tappable because a wrong
/// pickup has to be fixable without first choosing a destination.
class _PickupRow extends StatelessWidget {
  const _PickupRow({
    required this.label,
    required this.busy,
    required this.uncertain,
    required this.onTap,
  });

  final String label;
  final bool busy;

  /// The phone reported a fix too vague to name a street with.
  final bool uncertain;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = label.trim();

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            children: [
              // The route rail's start marker, on its own: a navy ring.
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTint.pinPickupFill, width: 3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.isEmpty ? 'Set a pickup point' : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  // Louder when the fix was vague. "Change" is an option;
                  // "Check this" is a request, and the difference matters when
                  // the address on screen may be a street out.
                  uncertain ? 'Check this' : 'Change',
                  style: AppType.caption.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: uncertain
                        ? AppTint.warningText
                        : AppColors.brandInk,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdFloatButton(
        tooltip: 'Centre the map on my location',
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location_rounded,
                size: 22, color: AppColors.navy),
      );
}

/// What one nearby vehicle is — screen C-06.
///
/// No driver name, no plate, no CTA. The API withholds identity before a
/// booking exists, so there is nothing here to book with and nothing to
/// pretend otherwise.
class _VehicleMarkerSheet extends StatelessWidget {
  const _VehicleMarkerSheet({required this.vehicle});

  final NearbyVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final mode = vehicle.bookingMode;
    final String modeLine;
    if (mode.allowsPerSeat && mode.allowsWholeVehicle) {
      modeLine = 'Per seat or whole vehicle.';
    } else if (mode.allowsPerSeat) {
      modeLine = 'Offered per seat.';
    } else {
      modeLine = 'Booked as a whole vehicle.';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            UdIconTile(icon: _icon, tone: UdIconTone.soft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    vehicle.category,
                    style: AppType.h3.copyWith(
                      fontSize: 18.5,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${vehicle.distanceKm.toStringAsFixed(1)} km away  ·  '
                    'about ${vehicle.etaMinutes} min',
                    style: AppType.small.copyWith(
                      fontSize: 14.5,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (vehicle.rating > 0) ...[
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded,
                      size: 18, color: AppTint.star),
                  const SizedBox(width: 4),
                  Text(
                    vehicle.rating.toStringAsFixed(1),
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        UdBanner(icon: Icons.event_seat_outlined, text: modeLine),
        const SizedBox(height: 14),
        Text(
          'Driver details are shared once your booking is confirmed.',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(color: AppText.caption),
        ),
      ],
    );
  }

  IconData get _icon {
    final category = vehicle.category.toLowerCase();
    if (category.contains('bike')) return Icons.two_wheeler_rounded;
    if (category.contains('coaster') ||
        category.contains('coster') ||
        category.contains('bus')) {
      return Icons.airport_shuttle_rounded;
    }
    if (category.contains('hiace') || category.contains('van')) {
      return Icons.airport_shuttle_outlined;
    }
    if (category.contains('rickshaw')) return Icons.electric_rickshaw_rounded;
    return Icons.directions_car_rounded;
  }
}

/// Language switch shown as a labelled pill/// The EN/اردو pill used to sit here.
///
/// Removed from the home screen. Language is set once and then never again,
/// and it was taking a permanent seat in the header next to the two controls
/// people use every day. It belongs in Settings.

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
                        fontSize: 18.5,
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
                          fontSize: 15.5,
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
                          fontSize: 13.5,
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
                  fontSize: 12,
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
    // Anchored on the dot, not on the middle of the column.
    //
    // This is a label, a head, a stem and then a dot — and the dot is the
    // point being chosen. Centring the whole column put its *middle* on the
    // map centre, which left the dot roughly half a pin below where the map
    // said it was. That is the gap between the blue location dot on one street
    // and the pin on the next.
    //
    // `FractionalTranslation(-0.5)` lifts the column by half its own height, so
    // its bottom edge lands on the centre; the 5px back down puts the dot's
    // middle exactly there. Fractional because the label's height changes with
    // the address in it, and a fixed offset would only be right for one of
    // them.
    return FractionalTranslation(
      translation: const Offset(0, -.5),
      child: Transform.translate(
        offset: const Offset(0, 5),
        child: _pin(),
      ),
    );
  }

  Widget _pin() {
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
                          fontSize: 11.5,
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
                                fontSize: 15,
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
    required this.cityRides,
    required this.tour,
    required this.cityToCity,
    required this.onSelect,
    required this.onClosed,
    required this.nearbyCount,
  });

  final HomeService selected;
  final ServiceAvailability cityRides;
  final ServiceAvailability tour;
  final ServiceAvailability cityToCity;
  final ValueChanged<HomeService> onSelect;
  final ValueChanged<ServiceAvailability> onClosed;
  final int nearbyCount;

  bool get _rideSelected =>
      selected == HomeService.car ||
      selected == HomeService.bus ||
      selected == HomeService.bike;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Taller again, for v2's type. 148 was set when titles were 15pt and
      // subtitles 10.5; the large card's title is 24 now and its subtitle
      // wraps to two lines.
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ProductCard(
              title: 'City rides',
              // The driver count when there is one, because "3 nearby" is the
              // single most useful thing this tile can say — and the vehicle
              // list is on the next screen anyway.
              subtitle: nearbyCount > 0
                  ? '$nearbyCount nearby now'
                  : 'Car · Bike · Coster · Hiace',
              icon: Icons.directions_car_rounded,
              surface: AppProduct.rideSurface,
              accent: AppProduct.rideAccent,
              titleInk: AppProduct.rideTitle,
              subInk: AppProduct.rideSub,
              selected: _rideSelected,
              large: true,
              secondaryIcon: Icons.two_wheeler_rounded,
              service: cityRides,
              onClosed: onClosed,
              onTap: () => onSelect(HomeService.car),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                    service: tour,
                    onClosed: onClosed,
                    onTap: () => onSelect(HomeService.tour),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  // Hotels moved down to the icon row, so this slot carries
                  // the other kind of ride: out of the city rather than across
                  // it. Both are cards because both start a booking.
                  child: _ProductCard(
                    title: 'City to city',
                    subtitle: 'Longer trips',
                    icon: Icons.alt_route_rounded,
                    surface: AppProduct.hotelSurface,
                    accent: AppProduct.hotelAccent,
                    titleInk: AppProduct.hotelTitle,
                    subInk: AppProduct.hotelSub,
                    selected: false,
                    large: false,
                    service: cityToCity,
                    onClosed: onClosed,
                    onTap: () => onSelect(HomeService.car),
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

/// The second rank of services, as icons.
class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.selected,
    required this.hotels,
    required this.carRental,
    required this.coster,
    required this.explore,
    required this.onSelect,
    required this.onExplore,
    required this.onClosed,
  });

  final HomeService selected;
  final ServiceAvailability hotels;
  final ServiceAvailability carRental;
  final ServiceAvailability coster;
  final ServiceAvailability explore;
  final ValueChanged<HomeService> onSelect;
  final VoidCallback onExplore;
  final ValueChanged<ServiceAvailability> onClosed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickTile(
            icon: Icons.apartment_rounded,
            label: 'Hotels',
            service: hotels,
            selected: selected == HomeService.hotel,
            onTap: () => onSelect(HomeService.hotel),
            onClosed: onClosed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickTile(
            icon: Icons.vpn_key_rounded,
            label: 'Car rental',
            service: carRental,
            selected: false,
            // Never opens: there is no screen behind it yet, so the closed
            // path is the only one. When one exists, the admin switch is all
            // that has to change.
            onTap: () {},
            onClosed: onClosed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickTile(
            icon: Icons.airport_shuttle_rounded,
            label: 'Coster',
            service: coster,
            selected: selected == HomeService.bus,
            onTap: () => onSelect(HomeService.bus),
            onClosed: onClosed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickTile(
            icon: Icons.explore_rounded,
            label: 'Explore',
            service: explore,
            selected: false,
            onTap: onExplore,
            onClosed: onClosed,
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.service,
    required this.selected,
    required this.onTap,
    required this.onClosed,
  });

  final IconData icon;
  final String label;

  /// The admin's switch for this service.
  final ServiceAvailability service;

  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<ServiceAvailability> onClosed;

  @override
  Widget build(BuildContext context) {
    final closed = !service.isOpen;

    return Semantics(
      button: true,
      selected: selected,
      label: closed ? '$label, ${service.badgeLabel}' : label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A closed tile still responds — it explains itself. A dead tap leaves
        // the customer wondering whether the app is broken.
        onTap: closed ? () => onClosed(service) : onTap,
        child: Opacity(
          opacity: closed ? .55 : 1,
          child: Stack(
            // Passthrough, not the default.
            //
            // A Stack hands its non-positioned children *loose* constraints, so
            // the card below was sizing to its own label — which is why the
            // four tiles came out four different widths, "Car rental" wide and
            // "Hotels" narrow, instead of each filling its equal share.
            // Passthrough gives the card the tight width the Expanded above
            // already worked out.
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.brandWash
                      : AppColors.surfaceHigh,
                  borderRadius: AppRadii.all(18),
                  border: Border.all(
                    color: selected ? AppColors.navy : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 26,
                      color: selected
                          ? AppColors.brandInk
                          : AppColors.navy,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.brandInk
                            : AppText.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (closed)
                Positioned(
                  top: -6,
                  right: -4,
                  child: UdBadge(label: service.badgeLabel),
                ),
            ],
          ),
        ),
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
    this.secondaryIcon,
    required this.service,
    required this.onTap,
    required this.onClosed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color surface;
  final Color accent;
  final Color titleInk;
  final Color subInk;
  final bool selected;

  /// The tall left-hand card. The two on the right are the small form.
  final bool large;

  /// A second vehicle drawn beside [icon] on the large tile.
  ///
  /// Only used by City rides, where one car misrepresented a category that also
  /// covers bikes, Costers and Hiaces.
  final IconData? secondaryIcon;

  /// The admin's switch for this service.
  final ServiceAvailability service;

  final VoidCallback onTap;
  final ValueChanged<ServiceAvailability> onClosed;

  @override
  Widget build(BuildContext context) {
    final closed = !service.isOpen;

    // Selection is a navy border, not a change of fill.
    //
    // The tiles used to drop to a washed-out version of their own colour when
    // unselected, which is why the row looked like one coloured box and three
    // empty ones. In v2 the brand tile keeps its lime and the others stay
    // white; what moves is the border.
    return Semantics(
      button: true,
      selected: selected,
      label: closed ? '$title, ${service.badgeLabel}' : title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A closed tile explains itself rather than doing nothing.
        onTap: closed ? () => onClosed(service) : onTap,
        child: Opacity(
          opacity: closed ? .55 : 1,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: AppRadii.all(large ? AppRadii.largeCard : 18),
                  border: Border.all(
                    color: selected ? AppColors.navy : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: AppShadows.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: large ? _large() : _small(),
              ),
              if (closed)
                Positioned(
                  top: 10,
                  right: 10,
                  child: UdBadge(label: service.badgeLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Title at the top, artwork in the bottom-right corner, out of the words'
  /// way. It used to be oversized and bleeding behind them, which worked at the
  /// old type size and stopped working at this one: the car printed straight
  /// through "Car · Bike · Coster · Hiace".
  Widget _large() => Stack(
        children: [
          Positioned(
            right: 14,
            bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (secondaryIcon != null) ...[
                  Icon(secondaryIcon, size: 28, color: accent),
                  const SizedBox(width: 6),
                ],
                Icon(icon, size: 34, color: accent),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.h2.copyWith(
                    fontSize: 24,
                    letterSpacing: -0.6,
                    color: titleInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: subInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  /// Words on the left, one icon tile on the right.
  Widget _small() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.listTitle.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: titleInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.small.copyWith(color: subInk),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            UdIconTile(
              icon: icon,
              tone: UdIconTone.neutral,
              size: UdIconTileSize.sm,
            ),
          ],
        ),
      );
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
  Widget build(BuildContext context) => UdBanner(
        tone: UdTone.warn,
        icon: Icons.location_off_rounded,
        text: message,
        trailing: UdButton(
          label: 'Retry',
          variant: UdButtonVariant.ghost,
          size: UdButtonSize.xs,
          expand: false,
          busy: busy,
          onPressed: onRetry,
        ),
      );
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
                size: 21, color: AppText.caption),
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
                      fontSize: 16,
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
                        fontSize: 13.5,
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

/// Time, distance and which road — the answer to "how far is it?".
///
/// The alternatives are not listed. They are chosen by tapping the road on the
/// map, which is more direct and how every taxi app works; a duplicate list
/// here would be a second way to do the same thing and a second thing to keep
/// in step with the map. The line under the figures says how many there are.
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
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: UdBanner(
          text: 'Working out the route…',
          icon: Icons.schedule_rounded,
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
        child: UdBanner(
          tone: UdTone.warn,
          icon: Icons.route_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              if (result.detail != null && result.detail!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  result.detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: AppTint.warningText,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final active = result.routes[selected.clamp(0, result.routes.length - 1)];

    final detail = StringBuffer();
    if (active.summary.isNotEmpty) detail.write('via ${active.summary}');
    if (result.routes.length > 1) {
      if (detail.isNotEmpty) detail.write('  ·  ');
      detail
        ..write(result.routes.length - 1)
        ..write(result.routes.length == 2 ? ' other route' : ' other routes')
        ..write(' on the map');
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTint.success,
          borderRadius: AppRadii.all(AppRadii.field),
          border: Border.all(color: AppTint.successBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: AppSizes.iconTileSm,
              height: AppSizes.iconTileSm,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadii.all(12),
              ),
              child: const Icon(Icons.schedule_rounded,
                  size: 20, color: AppColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${active.durationLabel}  ·  ${active.distanceLabel}',
                    style: AppType.h2.copyWith(
                      fontSize: 20,
                      letterSpacing: -0.3,
                      color: AppText.primary,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.small.copyWith(
                        color: AppColors.brandInk,
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

/// Per seat or the whole vehicle.
///
/// When only one mode is on offer there is nothing to choose, so it states the
/// fact instead of drawing a control with one option in it.
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
      final whole = available.first == BookingType.wholeVehicle;
      return UdBanner(
        icon: available.first.icon,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: whole ? 'Whole vehicle' : 'Per seat only',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (whole)
                const TextSpan(
                  text: ' — nearby vehicles seat 5 or fewer, so you book '
                      'the full car.',
                ),
            ],
          ),
        ),
      );
    }

    return UdSegmented(
      options: available.map((mode) => mode.label).toList(growable: false),
      index: available.indexOf(value).clamp(0, available.length - 1),
      onChanged: (index) => onChanged(available[index]),
    );
  }
}

/// The from/to block, plus the one-tap way to reset the start.
///
/// The rail tells the two ends apart by shape rather than by hue: an open navy
/// ring for where you are, a lime square with a navy border for where you are
/// going. That replaced a green dot and an orange square, which were the only
/// two colours left in the app belonging to no part of the brand — and which a
/// colour-blind rider could not tell apart anyway.
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
        UdCard(
          tone: UdCardTone.tint,
          radius: AppRadii.field,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: UdRouteBlock(
            fromLabel: 'From',
            fromValue: pickupLabel,
            fromPlaceholder:
                locating ? 'Finding your location…' : 'Set a pickup point',
            onTapFrom: onEditPickup,
            toLabel: 'To',
            toValue: destinationLabel,
            toPlaceholder: 'Where are you going?',
            onTapTo: onEditDestination,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: UdButton(
            label: locating ? 'Locating…' : 'Use my location',
            icon: Icons.my_location_rounded,
            variant: UdButtonVariant.ghost,
            size: UdButtonSize.small,
            expand: false,
            busy: locating,
            onPressed: onUseMyLocation,
          ),
        ),
      ],
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
                fontSize: 14,
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
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 17.5,
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
                fontSize: 14.5,
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
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
          Row(
            children: [
              const Text(
                'PKR',
                style: TextStyle(
                  fontSize: 16.5,
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
                    fontSize: 17.5,
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
                      fontSize: 14.5,
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
                      fontSize: 13.5,
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
                      fontSize: 16.5,
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

/// The button that sends the request.
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
  Widget build(BuildContext context) => UdButton.primary(
        label: label,
        trailingIcon: Icons.arrow_forward_rounded,
        busy: busy,
        onPressed: enabled ? onTap : null,
      );
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) => const UdBanner(
        tone: UdTone.warn,
        icon: Icons.cloud_off_rounded,
        text: 'You are offline. Saved maps are in use and bookings will need '
            'a connection.',
      );
}

/// The hero card when a ride is already under way — screen C-07.
///
/// It takes the slot the "Where to?" card normally owns, and it is outlined in
/// the lime line rather than the hairline grey, because it is the one thing on
/// the screen that is happening right now.
class _ActiveTripBanner extends StatelessWidget {
  const _ActiveTripBanner({required this.trip, required this.onTrack});

  final MobileTrip trip;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.largeCard),
        border: Border.all(color: AppColors.limeLine, width: 1.5),
        boxShadow: AppShadows.panel,
      ),
      child: Row(
        children: [
          const UdIconTile(
            icon: Icons.directions_car_rounded,
            tone: UdIconTone.lime,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TRIP IN PROGRESS',
                  style: AppType.overline.copyWith(color: AppText.secondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${trip.pickupLabel} → ${trip.destinationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.listTitle.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          UdButton.dark(
            label: 'Track',
            size: UdButtonSize.small,
            expand: false,
            onPressed: onTrack,
          ),
        ],
      ),
    );
  }
}

/// "Invite friends", at the foot of Home.
///
/// Wired to `_shareApp`, which has been in this file all along with nothing
/// calling it.
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const UdIconTile(
              icon: Icons.card_giftcard_rounded,
              tone: UdIconTone.soft,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Invite friends',
                    style: AppType.listTitle.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Earn points for every referral',
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 22, color: AppText.caption),
          ],
        ),
      );
}
