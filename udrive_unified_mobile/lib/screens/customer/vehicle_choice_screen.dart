import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking/booking_options.dart';
import '../../core/format/money.dart';
import '../../core/routing/route_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/maps/ud_map.dart';
import '../../core/pricing/fare_quote.dart';
import '../../core/pricing/fare_quote_repository.dart';
import '../../core/vehicles/nearby_repository.dart';
import '../../core/vehicles/nearby_vehicle.dart';
import '../../core/vehicles/seat_fares_repository.dart';
import '../../core/vehicles/vehicle_options_repository.dart';
import '../../core/widgets/home_service.dart';
import '../../models/auth_models.dart';
import 'driver_offers_screen.dart';

/// Choose a vehicle and name a price.
///
/// This is where UDrive differs from a metered service: the customer proposes
/// a fare rather than accepting one. The recommended figure is a starting point
/// computed from the admin's rates and the real road distance — the customer is
/// free to offer less and wait, or more and be picked up sooner.
class VehicleChoiceScreen extends StatefulWidget {
  const VehicleChoiceScreen({
    required this.pickupLabel,
    required this.destinationLabel,
    required this.pickupPoint,
    required this.destinationPoint,
    required this.route,
    this.routes = const [],
    required this.service,
    required this.bookingType,
    required this.seats,
    super.key,
  });

  final String pickupLabel;
  final String destinationLabel;
  final LatLng pickupPoint;
  final LatLng destinationPoint;

  /// The route already computed on Home, so this screen does not pay for a
  /// second Directions call to draw the same line.
  final TripRoute? route;

  /// Every route the directions service offered.
  ///
  /// Passed through for the same reason as [route]: Home already made the call
  /// and asked for alternatives, so a second one would spend money to return
  /// the same answer. Empty falls back to [route] alone.
  final List<TripRoute> routes;

  final HomeService service;
  final BookingType bookingType;
  final int seats;

  @override
  State<VehicleChoiceScreen> createState() => _VehicleChoiceScreenState();
}

class _VehicleChoiceScreenState extends State<VehicleChoiceScreen> {
  List<VehicleOption> _options = const [];
  VehicleOption? _selected;

  /// Per seat or the whole vehicle, for the vehicle currently shown.
  ///
  /// Held per screen rather than per vehicle: switching from a coaster to a car
  /// has to fall back to whole vehicle, because a car cannot be sold by the
  /// seat. `_clampBooking` enforces that on every change.
  late BookingType _bookingType = widget.bookingType;

  late int _seats = widget.seats;
  int _fare = 0;

  /// Fixed per-seat fares for this route, keyed by vehicle category.
  ///
  /// A Coster running per seat charges a known fare for a known route. Where
  /// the admin has listed it, that fare is the fare — no distance arithmetic
  /// and no bidding, because nobody haggles over a seat on a scheduled run.
  final Map<String, SeatFareQuote> _seatFares = <String, SeatFareQuote>{};

  /// The server's answer for the vehicle, seat count and route on screen.
  ///
  /// Null while it is in flight or after it has failed. Everything the
  /// customer can actually do with a fare — the floor on the stepper, the
  /// keypad's bounds, the request itself — reads from here, so a missing quote
  /// means the screen shows a price but will not send one.
  FareQuote? _quote;
  bool _quoting = false;
  String? _quoteError;

  /// Cancels a quote whose answer arrived after the question changed.
  ///
  /// The same guard the seat fares use, for the same reason: the customer
  /// changes vehicle twice in a second and the slower of two replies must not
  /// overwrite the faster.
  int _quoteGeneration = 0;

  /// Which route the customer has chosen.
  ///
  /// The fare follows it. A longer way round costs more because it *is* more —
  /// more kilometres for the driver, more fuel, more time — and quoting one
  /// price for two different journeys would make the shorter one subsidise the
  /// longer.
  int _routeIndex = 0;

  /// The routes to offer, shortest first.
  ///
  /// Google returns its own order, which favours time. The customer is being
  /// charged by distance, so distance is the order that matches what they are
  /// about to pay — and the shortest is selected by default.
  late final List<TripRoute> _routes = () {
    final List<TripRoute> all = widget.routes.isNotEmpty
        ? [...widget.routes]
        : [if (widget.route != null) widget.route!];
    all.sort((a, b) => a.distanceMetres.compareTo(b.distanceMetres));
    return all;
  }();

  TripRoute? get _route => _routes.isEmpty
      ? widget.route
      : _routes[_routeIndex.clamp(0, _routes.length - 1)];

  /// Drivers within a short drive of the pickup.
  ///
  /// Shown because "how long until someone comes" is the question sitting
  /// underneath the fare, and a photograph of a car cannot answer it. Seeing
  /// four of them a street away is the difference between naming a low fare
  /// confidently and not naming one at all.
  List<NearbyVehicle> _nearby = const [];

  final _mapController = UdMapController();

  /// How far around the pickup counts as nearby, in kilometres.
  ///
  /// One kilometre, not three. At three the circle covered most of a town and
  /// a car on the far side of it read as "nearby" when it was twenty minutes
  /// away. One is the distance a customer can reasonably expect someone to
  /// reach them from.
  static const double _nearbyRadiusKm = 1;

  Timer? _nearbyTimer;

  /// The admin's fixed fare for a vehicle, or null if the route has none.
  ///
  /// The map is keyed lower-case (see _loadSeatFares), and categories arrive
  /// capitalised — 'Car', 'Coster'. One caller used to index it with the raw
  /// category, which therefore never matched: the pill fell back to the metered
  /// whole-vehicle price while the panel below showed the fixed per-seat fare,
  /// and the two numbers disagreed on screen. Every lookup goes through here.
  SeatFareQuote? _seatFareFor(VehicleOption option) =>
      _seatFares[option.category.toLowerCase()];

  /// The fixed fare covering the vehicle currently shown, if there is one.
  SeatFareQuote? get _fixedSeatFare {
    final option = _selected;
    if (option == null || !_perSeat) return null;
    return _seatFareFor(option);
  }

  /// Bumped every time the fixed fares are reloaded, so an older in-flight
  /// load can tell that it is no longer the current one.
  int _seatFaresGeneration = 0;

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  /// One key per vehicle card, so a selected card in a scrolling row (more
  /// vehicles than fit across the screen) can be scrolled into view.
  final Map<String, GlobalKey> _pillKeys = <String, GlobalKey>{};

  bool get _perSeat => _bookingType == BookingType.perSeat;

  int get _step {
    if (_fare >= 10000) return 500;
    if (_fare >= 3000) return 100;
    return 50;
  }

  /// What the fare box opens at.
  ///
  /// The server's figure when there is one. The local calculation is still
  /// here and still runs, but only to put a number under the customer's eye
  /// while the quote is in flight — it is a placeholder, and `_findOffers`
  /// will not send a request without a real quote behind it.
  int get _recommended {
    final quote = _quote;
    if (quote != null) return quote.recommended;
    final fixed = _fixedSeatFare;
    if (fixed != null) return fixed.perSeatFare * _seats;
    return _selected?.fareFor(perSeat: _perSeat, seats: _seats) ?? 0;
  }

  /// The most the customer may offer.
  ///
  /// A guard against a mistyped amount rather than a limit on generosity — it
  /// sits at several times the suggestion. Without a quote there is no ceiling
  /// to enforce, and the old hard-coded 500000 stands in.
  int get _maximum => _quote?.maximum ?? 500000;

  /// True once the screen has a fare the server will actually honour.
  bool get _hasUsableQuote {
    final quote = _quote;
    return quote != null && quote.isUsable;
  }

  /// What one vehicle would cost, for the price shown on its pill.
  ///
  /// Always the whole-vehicle fare, whatever the customer has chosen for the
  /// selected one. The pills are a comparison between vehicles, and comparing a
  /// Coster priced for two seats against a whole Car is not a comparison — it
  /// is two different questions with one number each.
  int _fareForOption(VehicleOption option) {
    // Priced on the basis the customer is currently buying on, so the number
    // on a pill is the number they will see in the panel when they select it.
    //
    // It used to be whole-vehicle always, on the argument that comparing a
    // Coster priced for two seats against a whole Car is not a comparison.
    // True, but it produced the reported bug: in per-seat mode the panel
    // showed the fixed per-seat fare and the pill showed the metered
    // whole-vehicle price, and the two disagreed on the same screen. Making
    // both pills answer the same question keeps the comparison honest AND
    // keeps the card and the summary in step.
    //
    // (The lookup below also used the raw category against a lower-cased map,
    // so it never matched at all — see _seatFareFor.)
    if (_perSeat && option.allowsPerSeat) {
      // The seats this vehicle can actually take, not the count chosen for
      // whichever vehicle happens to be selected.
      final seats = _seats > option.seats ? option.seats : _seats;
      final fixed = _seatFareFor(option);
      if (fixed != null) return fixed.perSeatFare * seats;
      return option.fareFor(perSeat: true, seats: seats);
    }
    return option.fareFor(perSeat: false, seats: option.seats);
  }

  /// The lowest offer this vehicle will take, from the admin's own rate table.
  ///
  /// This replaces the old floor of half the recommendation. Half was a guess;
  /// the admin has set an actual figure, and an offer below it is one no driver
  /// answers.
  int get _minimum {
    final quote = _quote;
    if (quote != null) return quote.minimum;
    // A fixed route fare is its own floor and its own ceiling.
    final fixed = _fixedSeatFare;
    if (fixed != null) return fixed.perSeatFare * _seats;
    return _selected?.minimumFor(perSeat: _perSeat, seats: _seats) ?? 0;
  }

  /// True when the fare is published rather than bid on.
  bool get _fareIsFixed =>
      _quote?.negotiable == false || _fixedSeatFare != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Picks a route, and reprices the trip against it.
  ///
  /// The whole point of offering a choice: a longer way round is a longer trip,
  /// and the fare has to say so before the customer sends it out. Reloading the
  /// options is what recomputes every vehicle's price from the new distance.
  Future<void> _selectRoute(int index) async {
    if (index == _routeIndex || index < 0 || index >= _routes.length) return;

    setState(() {
      _routeIndex = index;
      // Reloading resets the fare to the recommendation for the new distance.
      // That is right: an amount the customer set for a 24 km trip is not an
      // amount they set for a 31 km one, and silently carrying it over would
      // send out an offer they never actually made.
      _loading = true;
    });

    await _load();
  }

  /// Puts the fare back to the server's suggestion.
  void _useRecommended() {
    if (_fareIsFixed) return;
    final recommended = _recommended;
    if (recommended <= 0) return;
    setState(() => _fare = recommended.clamp(
          _minimum > 0 ? _minimum : recommended,
          _maximum,
        ));
  }

  /// Reads the drivers around the pickup, and keeps reading.
  ///
  /// Refreshed every five seconds. A driver who has moved on is worse than no
  /// driver at all: a customer counts the cars before deciding what to offer,
  /// and counting stale ones leads them to offer too little.
  Future<void> _loadNearby(AppController controller) async {
    final vehicles = await NearbyVehicleRepository(controller.apiClient).nearby(
      latitude: widget.pickupPoint.latitude,
      longitude: widget.pickupPoint.longitude,
      radiusKm: _nearbyRadiusKm,
    );
    if (!mounted) return;
    // An empty answer is an answer. Keeping the previous set on screen would
    // show cars that have gone.
    setState(() => _nearby = vehicles);
  }

  Future<void> _load() async {
    final controller = AppControllerScope.of(context);
    final repository = VehicleOptionsRepository(controller.apiClient);

    final route = _route;
    final distanceKm = route?.distanceKm ??
        const Distance().as(
              LengthUnit.Kilometer,
              widget.pickupPoint,
              widget.destinationPoint,
            ) *
            1.6;
    final minutes = route == null
        ? (distanceKm / 25 * 60).round()
        : (route.durationSeconds / 60).round();

    final options = await repository.optionsFor(
      distanceKm: distanceKm,
      durationMinutes: minutes,
      pickupLatitude: widget.pickupPoint.latitude,
      pickupLongitude: widget.pickupPoint.longitude,
    );
    if (!mounted) return;

    // Only the vehicles that can actually be sold by the seat are looked up.
    // Asking for a bike's route fare would be a request that can only ever come
    // back empty.
    unawaited(_loadNearby(controller));
    _nearbyTimer?.cancel();
    _nearbyTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_loadNearby(controller)),
    );
    unawaited(_loadSeatFares(
      controller,
      options.where((option) => option.allowsPerSeat),
    ));

    // Open on the vehicle matching the service chosen on Home, so this screen
    // continues that decision rather than restarting it — but only the first
    // time. _load also runs when the customer picks a different route, and
    // re-deriving the choice from widget.service there silently threw away the
    // vehicle they had just swiped to: prices appeared to change on their own
    // because the vehicle underneath them had changed.
    final keep = _selected?.category;
    final preferred = options.isEmpty
        ? null
        : options.firstWhere(
            (option) => keep != null
                ? option.category == keep
                : option.service == widget.service,
            orElse: () => options.firstWhere(
              (option) => option.service == widget.service,
              orElse: () => options.first,
            ),
          );

    setState(() {
      _options = options;
      _selected = preferred;
      _loading = false;
      if (preferred == null) {
        _error = 'No vehicles are available for this trip right now.';
      } else {
        _clampBooking();
        // The previous route's quote priced a different journey. Selecting a
        // longer way round and keeping the short route's floor is exactly the
        // hole the server cannot see, because the pickup and destination have
        // not moved.
        _quote = null;
        _fare = _recommended;
      }
    });

    if (_selected != null) unawaited(_loadQuote());
    _frameRoute();
  }

  /// Puts the chosen road in view, inside the part of the map above the panel.
  void _frameRoute() {
    final points = _route?.points ?? const <LatLng>[];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitBounds(
        points.length > 1
            ? points
            : [widget.pickupPoint, widget.destinationPoint],
        padding: 56,
      );
    });
  }

  /// Nearby vehicles of the same kind as [option].
  ///
  /// Categories arrive spelt both ways ("Coster" and "Coaster"), so both sides
  /// are normalised before comparing.
  List<NearbyVehicle> _nearbyFor(VehicleOption option) {
    String norm(String value) =>
        value.toLowerCase().replaceAll('coster', 'coaster').trim();
    final wanted = norm(option.category);
    return _nearby
        .where((vehicle) => norm(vehicle.category) == wanted)
        .toList(growable: false);
  }

  /// Minutes until the nearest vehicle of this kind could reach the pickup,
  /// or null when none is nearby.
  int? _etaFor(VehicleOption option) {
    final near = _nearbyFor(option);
    if (near.isEmpty) return null;
    var best = 1 << 30;
    for (final vehicle in near) {
      final minutes = vehicle.etaMinutes > 0
          ? vehicle.etaMinutes
          : (vehicle.distanceKm / 25 * 60).ceil();
      if (minutes < best) best = minutes;
    }
    return best < 1 ? 1 : best;
  }

  /// Asks the server what this trip costs, and holds the answer.
  ///
  /// Called wherever the question changes — the route, the vehicle, per seat
  /// versus whole vehicle, the seat count. Each call takes a generation number
  /// so a slow reply to an old question cannot land on a new one.
  ///
  /// A failure leaves [_quote] null and puts the server's own message on
  /// screen. That is deliberate: the alternative is to fall back to the
  /// client's own arithmetic, which is exactly how the app ended up with two
  /// pricing formulas that disagreed with each other and with the admin's
  /// rates.
  Future<void> _loadQuote() async {
    final option = _selected;
    final route = _route;
    if (option == null) return;

    final generation = ++_quoteGeneration;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });

    final controller = AppControllerScope.of(context);
    final repository = FareQuoteRepository(controller.apiClient);

    // Straight-line distance stands in when no route has been fetched. The
    // server checks the claim against the same straight line, so an honest
    // approximation is accepted and a wild one is not.
    final metres = route?.distanceMetres ??
        const Distance().as(
          LengthUnit.Meter,
          widget.pickupPoint,
          widget.destinationPoint,
        );
    final distanceKm = (metres / 1000).clamp(0.1, 5000).toDouble();
    final minutes = route == null
        ? distanceKm / 25 * 60
        : route.durationSeconds / 60;

    try {
      final quote = await repository.quote(
        // The same service type VehicleOptionsRepository asks for its rates
        // with. If that ever stops being fixed, both have to move together or
        // the quote prices a different rate card from the pills.
        serviceType: 'City',
        vehicleCategory: option.category,
        perSeat: _perSeat,
        seats: _perSeat ? _seats : 1,
        pickupLatitude: widget.pickupPoint.latitude,
        pickupLongitude: widget.pickupPoint.longitude,
        destinationLatitude: widget.destinationPoint.latitude,
        destinationLongitude: widget.destinationPoint.longitude,
        distanceKm: distanceKm,
        durationMinutes: minutes.clamp(1, 6000).toDouble(),
      );

      if (!mounted || generation != _quoteGeneration) return;
      setState(() {
        _quote = quote;
        _quoting = false;
        // The customer's own number is kept when it still sits inside the new
        // band — they chose it, and a reprice that quietly resets it would
        // undo a deliberate decision. Outside the band it has to move.
        _fare = _fare <= 0
            ? quote.recommended
            : _fare.clamp(quote.minimum, quote.maximum);
        if (!quote.negotiable) _fare = quote.recommended;
      });
    } catch (error) {
      if (!mounted || generation != _quoteGeneration) return;
      setState(() {
        _quote = null;
        _quoting = false;
        _quoteError = error is ApiException
            ? error.message
            : 'The fare could not be checked. Try again.';
      });
    }
  }

  /// Reads the fixed route fares for the seat-sellable vehicles.
  ///
  /// Runs after the options are on screen rather than blocking them. A customer
  /// should not wait on a lookup that usually comes back empty, and when it
  /// does return a fare the panel simply updates.
  Future<void> _loadSeatFares(
    AppController controller,
    Iterable<VehicleOption> options,
  ) async {
    final repository = SeatFaresRepository(controller.apiClient);

    // Cleared first. The map outlived every reload, so a fixed fare the admin
    // had deleted kept being applied for as long as the screen stayed open.
    if (mounted) setState(_seatFares.clear);

    // Clearing alone is not enough: this runs unawaited, one network call per
    // category, so a loop started for the previous route is still alive and
    // would write its stale quotes back in after the clear. Each run carries
    // the generation it started in and stops as soon as a newer one begins.
    final generation = ++_seatFaresGeneration;

    for (final option in options) {
      if (generation != _seatFaresGeneration) return;
      final quote = await repository.quote(
        category: option.category,
        fromLatitude: widget.pickupPoint.latitude,
        fromLongitude: widget.pickupPoint.longitude,
        toLatitude: widget.destinationPoint.latitude,
        toLongitude: widget.destinationPoint.longitude,
      );
      if (!mounted || generation != _seatFaresGeneration) return;
      if (quote == null) continue;

      setState(() {
        _seatFares[option.category.toLowerCase()] = quote;
        // If the customer is already looking at per seat on this vehicle, the
        // price on screen is now wrong. Correct it rather than leaving a
        // negotiable figure where a fixed one belongs.
        if (_perSeat && _selected?.category == option.category) {
          _fare = _recommended;
        }
      });
    }
  }

  /// Keeps the booking type legal for the vehicle on screen.
  void _clampBooking() {
    final option = _selected;
    if (option == null) return;
    if (!option.allowsPerSeat) _bookingType = BookingType.wholeVehicle;
    if (_seats > option.seats) _seats = option.seats;
  }

  /// Chosen from the vehicle row.
  void _select(VehicleOption option) => _apply(option);

  void _apply(VehicleOption option) {
    if (_selected?.category == option.category) return;
    setState(() {
      _selected = option;
      _clampBooking();
      // Reset to the recommendation for the new vehicle. Carrying a coaster
      // price onto a bike would be nonsense.
      _quote = null;
      _fare = _recommended;
    });
    unawaited(_loadQuote());
    _revealPill(option);
  }

  void _revealPill(VehicleOption option) {
    final key = _pillKeys[option.category];
    final target = key?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      alignment: .5,
    );
  }

  void _setBookingType(BookingType type) {
    setState(() {
      _bookingType = type;
      if (type == BookingType.perSeat && _seats < 1) _seats = 1;
      _quote = null;
      _fare = _recommended;
    });
    unawaited(_loadQuote());
  }

  void _setSeats(int value) {
    final option = _selected;
    setState(() {
      _seats = value.clamp(1, option?.seats ?? 12);
      // Recomputed either way: on a fixed route this is the listed fare times
      // the seats, and off one it is the recommendation for the new count.
      _quote = null;
      _fare = _recommended;
    });
    unawaited(_loadQuote());
  }

  void _nudge(int direction) {
    if (_selected == null) return;
    // Belt and braces. The buttons are hidden on a fixed route, but the state
    // is what actually protects the fare and the widget tree is not the place
    // to enforce a pricing rule.
    if (_fareIsFixed) return;
    setState(() {
      // Never below the server's minimum for this trip, and never above its
      // ceiling. Both are the same figures the API will check.
      _fare = (_fare + direction * _step).clamp(_minimum, _maximum);
    });
  }

  Future<void> _findOffers() async {
    final option = _selected;
    if (option == null || _submitting) return;

    // No quote, no request.
    //
    // Without this the button is live while the quote is in flight, after it
    // has failed, and after it has expired — and in each of those the screen
    // falls back to the figures it works out itself, which is the state this
    // whole change exists to end. The comment on _recommended promises the
    // request will not go out without a real quote behind it; this is the line
    // that keeps the promise.
    if (!_hasUsableQuote) {
      setState(() {
        _error = _quoteError ?? 'Checking the fare — one moment.';
      });
      if (!_quoting) unawaited(_loadQuote());
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final controller = AppControllerScope.of(context);

      // Through the controller, not BookingRepository directly. Creating the
      // request here without telling the controller left _liveRideRequests
      // unaware of a search the server had just opened, so the Trips tab could
      // not offer to resume or cancel it.
      final request = await controller.createLiveRideRequest({
        'pickupLabel': widget.pickupLabel,
        'destinationLabel': widget.destinationLabel,
        'pickupLatitude': widget.pickupPoint.latitude,
        'pickupLongitude': widget.pickupPoint.longitude,
        'destinationLatitude': widget.destinationPoint.latitude,
        'destinationLongitude': widget.destinationPoint.longitude,
        'pickupAt': DateTime.now().toUtc().toIso8601String(),
        'bookingType': _bookingType.apiValue,
        'seatsRequested': _perSeat ? _seats : 1,
        'adults': _perSeat ? _seats : 1,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': _fare,
        'quoteToken': _quote?.token,
        // Which rate card the quote came from. Must match what _loadQuote
        // asked for, or the server refuses the pair.
        'serviceType': 'City',
        'vehicleCategory': option.category,
        'partyType': 'Any',
        'familyOnly': false,
        'womenOnly': false,
        // Without this the API rejects the request: an advance booking must be
        // at least 30 minutes ahead, and this pickup is now.
        'instantRide': true,
      });

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverOffersScreen(
            rideRequestId: request.id,
            pickup: widget.pickupLabel,
            destination: widget.destinationLabel,
            customerOffer: _fare,
            vehicleName: option.label,
            pickupPoint: widget.pickupPoint,
            destinationPoint: widget.destinationPoint,
            routePoints: _route?.points,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _submitting = false;
      });

      // "Cancel that request before starting a new one" is only useful if the
      // customer can reach the request. Offer the way there rather than leaving
      // them to find a screen that used to be unreachable.
      if (error is ApiException && error.code == 'request_already_open') {
        await _offerToResumeOpenSearch();
      }
    }
  }

  /// Takes the customer to the search the server is refusing to replace.
  Future<void> _offerToResumeOpenSearch() async {
    final controller = AppControllerScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Hoisted with the others: the action below runs when the customer taps it,
    // which may be seconds later and after this screen has gone.
    final navigator = Navigator.of(context);

    await controller.refreshCustomerRideState();
    if (!mounted) return;

    final open = controller.openRideRequests;
    if (open.isEmpty) return;
    final request = open.first;

    messenger.showSnackBar(
      SnackBar(
        content: const Text('You already have a search running.'),
        action: SnackBarAction(
          label: 'View it',
          onPressed: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => DriverOffersScreen(
                  rideRequestId: request.id,
                  pickup: request.pickupLabel,
                  destination: request.destinationLabel,
                  customerOffer: request.customerOffer.round(),
                  vehicleName: request.vehicleCategory,
                  pickupPoint:
                      LatLng(request.pickupLatitude, request.pickupLongitude),
                  destinationPoint: LatLng(
                    request.destinationLatitude,
                    request.destinationLongitude,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _editFare() async {
    // Nothing to type on a fixed route. The tap is already disabled, but the
    // state is what protects the fare — a widget tree is not the place to
    // enforce a pricing rule.
    if (_fareIsFixed) return;

    final controller = TextEditingController(text: '$_fare');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Your offer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: 'PKR '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              int.tryParse(controller.text.trim()),
            ),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value != null && value > 0 && mounted) {
      // Typed figures obey the same band as the stepper — and the same band
      // the API will check, so a number accepted here is never refused on the
      // next screen.
      final floor = _minimum > 0 ? _minimum : 50;
      final clamped = value.clamp(floor, _maximum);
      setState(() => _fare = clamped);

      // Said out loud. A figure outside the band used to be rewritten in
      // silence: the customer typed 300, closed the dialog, and found 500 on
      // the screen with no explanation of where their number had gone.
      if (clamped != value) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value < floor
                  ? 'The lowest offer on this route is PKR $floor, so that is '
                      'what has been set.'
                  : 'The highest offer on this route is PKR $_maximum, so that '
                      'is what has been set.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final route = _route;
    final maxSheet = MediaQuery.sizeOf(context).height * .66;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The map takes everything the panel does not. It runs a little
          // under the panel's rounded top, so the corners show map rather than
          // a strip of background.
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -24,
                  child: _buildMap(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _DestinationHeader(
                    destination: widget.destinationLabel,
                    route: route,
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                if (selected != null)
                  Positioned(
                    left: AppSizes.sidePadding,
                    bottom: 12,
                    child: _NearbyChip(
                      label: selected.label,
                      count: _nearbyFor(selected).length,
                      etaMinutes: _etaFor(selected),
                    ),
                  ),
                Positioned(
                  right: AppSizes.sidePadding,
                  bottom: 6,
                  child: UdFloatButton(
                    tooltip: 'Show the whole route',
                    onPressed: _frameRoute,
                    child: const Icon(Icons.my_location_rounded,
                        size: 22, color: AppColors.navy),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheet),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: AppShadows.floating,
              ),
              child: _loading || selected == null
                  ? SizedBox(
                      height: 220,
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : Padding(
                                padding: const EdgeInsets.all(
                                    AppSizes.sidePadding),
                                child: Text(
                                  _error ??
                                      'No vehicles are available for this trip right now.',
                                  textAlign: TextAlign.center,
                                  style: AppType.body2
                                      .copyWith(color: AppText.secondary),
                                ),
                              ),
                      ),
                    )
                  : _buildSheet(selected),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return UdMap(
      controller: _mapController,
      initialCenter: widget.pickupPoint,
      zoom: 13.5,
      showMyLocation: false,
      // The panel covers the bottom of the map; Google keeps the camera
      // centred in what is left.
      padding: const EdgeInsets.only(bottom: 24),
      polylines: [
        // Alternatives first and thin, so the chosen road is never buried
        // under one it overlaps for most of its length.
        for (var i = _routes.length - 1; i >= 0; i--)
          if (i != _routeIndex)
            UdPolyline(
              id: 'route-$i',
              points: _routes[i].points,
              color: AppText.disabled,
              width: 4,
              onTap: () => _selectRoute(i),
            ),
        if (_route != null) ...[
          UdPolyline(
            id: 'route-selected-casing',
            points: _route!.points,
            color: AppColors.brand,
            width: 10,
          ),
          UdPolyline(
            id: 'route-selected',
            points: _route!.points,
            color: AppColors.navy,
            width: 5,
          ),
        ],
      ],
      markers: [
        UdMarker(
          id: 'pickup',
          position: widget.pickupPoint,
          label: widget.pickupLabel,
          hue: UdMarkerHue.info,
        ),
        UdMarker(
          id: 'destination',
          position: widget.destinationPoint,
          label: widget.destinationLabel,
          hue: UdMarkerHue.brand,
        ),
        for (final vehicle in _nearby)
          UdMarker(
            id: 'nearby-${vehicle.id}',
            position: vehicle.point,
            sprite: vehicle.sprite,
            headingDegrees: vehicle.headingDegrees,
          ),
      ],
    );
  }

  Widget _buildSheet(VehicleOption selected) {
    final manyOptions = _options.length > 5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: AppRadii.all(2),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 12, AppSizes.sidePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Route options, when there is more than one. Chips rather
                // than only the lines on the map: two routes a few pixels
                // wide that run together are not a target anyone can hit.
                if (_routes.length > 1) ...[
                  Row(
                    children: [
                      for (var i = 0; i < _routes.length && i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _RouteChip(
                            route: _routes[i],
                            title: i == 0 ? 'SHORTEST' : 'ROUTE ${i + 1}',
                            selected: i == _routeIndex,
                            onTap: () => _selectRoute(i),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Every vehicle with its fare, seats and how far the nearest
                // one is. The comparison is the decision.
                if (manyOptions)
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _options.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final option = _options[index];
                        return SizedBox(
                          width: 72,
                          child: _vehicleCard(option, selected),
                        );
                      },
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final option in _options) ...[
                        Expanded(child: _vehicleCard(option, selected)),
                        if (option != _options.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),

                // Only a vehicle with seats to spare can be sold by the seat.
                // For everything else the row is absent rather than disabled.
                if (selected.allowsPerSeat) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _BookingTypeToggle(
                          value: _bookingType,
                          onChanged: _setBookingType,
                        ),
                      ),
                      if (_perSeat) ...[
                        const SizedBox(width: 10),
                        _SeatStepper(
                          seats: _seats,
                          maximum: selected.seats,
                          onChanged: _setSeats,
                        ),
                      ],
                    ],
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  UdBanner(
                    tone: UdTone.warn,
                    icon: Icons.error_outline_rounded,
                    text: _error!,
                  ),
                ],
              ],
            ),
          ),
        ),

        // The fare and the action never move. Whatever the customer changes
        // above, the thing they are actually deciding stays under their thumb.
        _FarePanel(
          fare: _fare,
          recommended: _recommended,
          minimum: _minimum,
          fixedRoute: _fixedSeatFare,
          quote: _quote,
          quoting: _quoting,
          quoteError: _quoteError,
          onRetryQuote: _loadQuote,
          perSeat: _perSeat,
          seats: _seats,
          submitting: _submitting,
          vehicleLabel: selected.label,
          onDecrease: () => _nudge(-1),
          onIncrease: () => _nudge(1),
          onEdit: _editFare,
          onUseRecommended: _useRecommended,
          onSubmit: _findOffers,
        ),
      ],
    );
  }

  Widget _vehicleCard(VehicleOption option, VehicleOption selected) {
    final eta = _etaFor(option);
    return _VehiclePill(
      key: _pillKeys.putIfAbsent(option.category, GlobalKey.new),
      option: option,
      fare: _fareForOption(option),
      etaMinutes: eta,
      nearby: eta != null,
      selected: option.category == selected.category,
      onTap: () => _select(option),
    );
  }
}

/// Where the trip goes, floating over the map.
///
/// Only the destination. The pickup is where the customer is standing, and
/// they know that already; the space is better spent on the name of the place
/// they are going, which is what they check before paying.
class _DestinationHeader extends StatelessWidget {
  const _DestinationHeader({
    required this.destination,
    required this.route,
    required this.onBack,
  });

  final String destination;
  final TripRoute? route;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final r = route;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 10, AppSizes.sidePadding, 0),
        // IntrinsicHeight, and it is not optional. This header sits in a
        // Positioned with no bottom, so its height is unbounded, and a
        // `stretch` Row under unbounded height cannot lay out: the whole
        // header — back button and destination — was never drawn.
        child: IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: AppColors.background,
              borderRadius: AppRadii.all(16),
              elevation: 0,
              child: InkWell(
                onTap: onBack,
                borderRadius: AppRadii.all(16),
                child: Ink(
                  width: 50,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.all(16),
                    boxShadow: AppShadows.floating,
                  ),
                  child: Tooltip(
                    message: MaterialLocalizations.of(context).backButtonTooltip,
                    child: const Icon(Icons.arrow_back_rounded,
                        size: 22, color: AppColors.navy),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: AppRadii.all(16),
                  boxShadow: AppShadows.floating,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: AppRadii.all(10),
                      ),
                      child: const Icon(Icons.place_rounded,
                          size: 19, color: AppColors.navy),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            destination,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                          if (r != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${r.durationLabel} · ${r.distanceLabel}'
                              '${r.summary.isEmpty ? '' : ' · via '
                                  '${r.summary.split('/').first.trim()}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.small.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
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
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// "Car · 8 nearby · ~4 min", over the bottom-left of the map.
class _NearbyChip extends StatelessWidget {
  const _NearbyChip({
    required this.label,
    required this.count,
    required this.etaMinutes,
  });

  final String label;
  final int count;
  final int? etaMinutes;

  @override
  Widget build(BuildContext context) {
    final any = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(999),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: any ? AppColors.success : AppText.disabled,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            any
                ? '$label · $count nearby'
                    '${etaMinutes == null ? '' : ' · ~$etaMinutes min'}'
                : 'No $label nearby yet',
            style: AppType.small.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppText.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A vehicle in the row: icon, name, fare, seats and how far the nearest is.
///
/// Selected is navy with a lime icon tile and a lime price. A vehicle with
/// none nearby is drawn quieter but stays tappable — a request still reaches
/// drivers further out.
class _VehiclePill extends StatelessWidget {
  const _VehiclePill({
    required this.option,
    required this.fare,
    required this.etaMinutes,
    required this.nearby,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final VehicleOption option;
  final int fare;
  final int? etaMinutes;
  final bool nearby;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quiet = !nearby && !selected;
    final seats = '${option.seats} seat${option.seats == 1 ? '' : 's'}';
    final detail = nearby ? '$seats · ${etaMinutes ?? 1} min' : 'None near';

    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}, ${Money.amount(fare)}, $detail',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.navy
                : quiet
                    ? AppColors.surfaceAlt
                    : AppColors.background,
            borderRadius: AppRadii.all(14),
            border: selected
                ? null
                : Border.all(
                    color: AppColors.border,
                    width: 1.5,
                  ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brand : AppColors.surfaceAlt,
                  borderRadius: AppRadii.all(9),
                ),
                child: Icon(
                  option.icon,
                  size: 18,
                  color: quiet ? AppText.caption : AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.small.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppText.onInk
                      : quiet
                          ? AppText.caption
                          : AppText.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Money.plain(fare),
                maxLines: 1,
                style: AppType.small.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? AppColors.brand
                      : quiet
                          ? AppText.caption
                          : AppText.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppText.onInkMuted : AppText.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One route option: how far and how long.
class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.route,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final TripRoute route;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = (route.durationSeconds / 60).round();

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandWash : AppColors.background,
            borderRadius: AppRadii.all(12),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                style: AppType.overline.copyWith(
                  fontSize: 10.5,
                  color: selected ? AppColors.brandInk : AppText.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${route.distanceKm.toStringAsFixed(route.distanceKm < 10 ? 1 : 0)} km'
                ' · $minutes min',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.small.copyWith(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: AppText.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per seat or whole vehicle. Only shown for vehicles with seats to spare.
///
/// The icons that used to sit beside each label are gone: the design's
/// segmented control carries words only, and "Whole vehicle" needs no picture.
class _BookingTypeToggle extends StatelessWidget {
  const _BookingTypeToggle({required this.value, required this.onChanged});

  final BookingType value;
  final ValueChanged<BookingType> onChanged;

  @override
  Widget build(BuildContext context) => UdSegmented(
        options: BookingType.values
            .map((type) => type.label)
            .toList(growable: false),
        index: BookingType.values.indexOf(value),
        onChanged: (index) => onChanged(BookingType.values[index]),
      );
}

/// A compact `−  N seats  +` control beside the booking-type toggle.
class _SeatStepper extends StatelessWidget {
  const _SeatStepper({
    required this.seats,
    required this.maximum,
    required this.onChanged,
  });

  final int seats;
  final int maximum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canLess = seats > 1;
    final canMore = seats < maximum;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(14),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SeatButton(
            icon: Icons.remove_rounded,
            tooltip: 'One seat fewer',
            onTap: canLess ? () => onChanged(seats - 1) : null,
          ),
          SizedBox(
            width: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$seats',
                  style: AppType.listTitle.copyWith(
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  seats == 1 ? 'seat' : 'seats',
                  style: AppType.caption.copyWith(
                    fontSize: 10,
                    height: 1,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          _SeatButton(
            icon: Icons.add_rounded,
            tooltip: 'One seat more',
            dark: true,
            onTap: canMore ? () => onChanged(seats + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _SeatButton extends StatelessWidget {
  const _SeatButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.dark = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final Color background = !enabled
        ? AppColors.surfaceAlt
        : dark
            ? AppColors.navy
            : AppColors.surfaceAlt;
    final Color ink = !enabled
        ? AppText.disabled
        : dark
            ? AppText.onInk
            : AppColors.navy;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: AppRadii.all(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(10),
          child: SizedBox(
            width: 36,
            height: 38,
            child: Icon(icon, size: 20, color: ink),
          ),
        ),
      ),
    );
  }
}

/// The fare and the action, pinned to the bottom.
///
/// Nothing here moves when the vehicle, booking type or seat count changes —
/// only the numbers do. The customer's thumb stays where the decision is.
class _FarePanel extends StatelessWidget {
  const _FarePanel({
    required this.fare,
    required this.recommended,
    required this.minimum,
    required this.fixedRoute,
    required this.quote,
    required this.quoting,
    required this.quoteError,
    required this.onRetryQuote,
    required this.perSeat,
    required this.seats,
    required this.submitting,
    required this.vehicleLabel,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEdit,
    required this.onUseRecommended,
    required this.onSubmit,
  });

  final int fare;
  final int recommended;
  final int minimum;

  /// Set when this route has a listed per-seat fare. The stepper and the keypad
  /// are hidden while it is, because the fare is not the customer's to move.
  final SeatFareQuote? fixedRoute;

  /// The server's answer. Null while it is in flight or after it failed.
  final FareQuote? quote;
  final bool quoting;
  final String? quoteError;
  final VoidCallback onRetryQuote;

  final bool perSeat;
  final int seats;
  final bool submitting;

  /// Named on the button, so the customer can see which vehicle they are about
  /// to send the request for without looking back up the screen.
  final String vehicleLabel;

  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEdit;

  /// Puts the suggested fare back after the customer moved away from it.
  final VoidCallback onUseRecommended;
  final VoidCallback onSubmit;

  bool get _isFixed => fixedRoute != null || quote?.negotiable == false;

  String get _caption {
    final route = fixedRoute;
    if (route != null) {
      return 'Fixed fare · ${route.routeLabel}'
          '${seats > 1 ? '  ·  $seats seats' : ''}';
    }
    final published = quote?.fixedRouteLabel;
    if (published != null && quote?.negotiable == false) {
      return 'Fixed fare · $published'
          '${seats > 1 ? '  ·  $seats seats' : ''}';
    }
    if (recommended == 0) return 'Tolls & parking extra';
    // At the floor, say so plainly. "31% below" reads like there is further to
    // go; there is not, and the customer pressing minus again needs to know
    // why nothing moves.
    if (minimum > 0 && fare <= minimum) {
      return 'Minimum fare · may take longer$_tolls';
    }
    if (fare == recommended) {
      return (perSeat ? 'Recommended for $seats seats' : 'Recommended fare') +
          _tolls;
    }
    final difference = ((fare - recommended) / recommended * 100).round();
    if (difference > 0) return '$difference% above · faster pickup$_tolls';
    return '${difference.abs()}% below · may take longer$_tolls';
  }

  /// Tolls used to have their own line; folded into the caption so the sheet
  /// leaves room for the map.
  static const String _tolls = ' · tolls & parking extra';

  bool get _showSuggested =>
      !_isFixed && recommended > 0 && fare != recommended;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 8, AppSizes.sidePadding, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Surge, said out loud.
            //
            // A fare that is higher than usual and does not say why is the
            // thing that makes people distrust a ride app. The reason comes
            // from the server with the quote and is shown as it was given.
            if (quote?.hasSurge == true) ...[
              UdBanner(
                tone: UdTone.warn,
                icon: Icons.trending_up_rounded,
                text: 'Busy right now — fares are '
                    '${quote!.surge.toStringAsFixed(2)}×'
                    '${quote!.breakdown?.surgeReason == null ? '' : ' · '
                        '${quote!.breakdown!.surgeReason}'}',
              ),
              const SizedBox(height: 10),
            ],

            // The fare could not be checked.
            //
            // Shown rather than hidden behind a silent fallback to the app's
            // own arithmetic — that fallback is how the app came to have two
            // pricing formulas that disagreed with the admin's rates and with
            // each other.
            if (quoteError != null) ...[
              UdBanner(
                tone: UdTone.err,
                icon: Icons.error_outline_rounded,
                text: quoteError!,
                trailing: UdButton(
                  label: 'Retry',
                  variant: UdButtonVariant.ghost,
                  size: UdButtonSize.xs,
                  expand: false,
                  busy: quoting,
                  onPressed: onRetryQuote,
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (_isFixed) ...[
              Text(
                'Set fare for this route · not negotiable',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: AppText.caption),
              ),
              const SizedBox(height: 4),
            ],
            Row(
              children: [
                // No stepper on a fixed route. Buttons that refuse to move are
                // worse than buttons that are not there — the customer presses
                // them, nothing happens, and they are left wondering whether
                // the app is broken.
                if (!_isFixed)
                  _StepButton(
                    icon: Icons.remove_rounded,
                    enabled: minimum <= 0 || fare > minimum,
                    onTap: onDecrease,
                  ),
                Expanded(
                  child: GestureDetector(
                    onTap: _isFixed ? null : onEdit,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Money.amount(fare),
                          maxLines: 1,
                          style: AppType.price.copyWith(
                            color: AppText.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _caption,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isFixed)
                  _StepButton(
                    icon: Icons.add_rounded,
                    dark: true,
                    onTap: onIncrease,
                  ),
              ],
            ),
            if (_showSuggested) ...[
              const SizedBox(height: 10),
              Center(
                child: Material(
                  color: AppColors.brandWash,
                  borderRadius: AppRadii.all(999),
                  child: InkWell(
                    onTap: onUseRecommended,
                    borderRadius: AppRadii.all(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 15, color: AppColors.brandInk),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Suggested fare ${Money.amount(recommended)}'
                              ' · tap to use',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption.copyWith(
                                color: AppColors.brandInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Taller than the kit's default: this is the one action on the
            // screen, and it sits where the thumb already is.
            SizedBox(
              height: 64,
              child: UdButton.primary(
                label: vehicleLabel.isEmpty
                    ? 'Find offers'
                    : 'Find offers · $vehicleLabel',
                trailingIcon: Icons.chevron_right_rounded,
                busy: submitting,
                onPressed: onSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The large round buttons either side of the fare.
///
/// The plus is navy and the minus is a plain outline: raising an offer is the
/// action that gets a driver, and the two should not look like the same button
/// mirrored.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.dark = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color background = !enabled
        ? AppColors.surfaceAlt
        : dark
            ? AppColors.navy
            : AppColors.background;
    final Color ink = !enabled
        ? AppText.disabled
        : dark
            ? AppText.onInk
            : AppColors.navy;

    return Material(
      color: background,
      shape: dark || !enabled
          ? const CircleBorder()
          : const CircleBorder(
              side: BorderSide(color: AppColors.borderStrong, width: 1.5),
            ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, size: 24, color: ink),
        ),
      ),
    );
  }
}
