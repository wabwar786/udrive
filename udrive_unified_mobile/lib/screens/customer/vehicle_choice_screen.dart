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
import '../../core/vehicles/vehicle_image_repository.dart';
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

  /// Admin-supplied photographs, keyed by setting name.
  Map<String, String> _images = const {};

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

  /// True while the hero area is showing the map instead of the photograph.
  bool _showMap = false;

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

  /// Drives the swipeable vehicle photographs.
  ///
  /// The photograph is the biggest thing on the screen, so it is also the most
  /// obvious thing to swipe. Making that gesture change the vehicle means the
  /// customer can compare four of them with their thumb where it already is,
  /// instead of reaching up to the pill row for every change.
  final PageController _pages = PageController();

  /// One key per pill, so a pill selected by swiping can be scrolled into view.
  ///
  /// Swiping to the fourth vehicle used to leave its pill off the right edge of
  /// the row, which made the row look like it had stopped responding.
  final Map<String, GlobalKey> _pillKeys = <String, GlobalKey>{};

  bool get _perSeat => _bookingType == BookingType.perSeat;

  int get _index {
    final selected = _selected;
    if (selected == null) return 0;
    final index =
        _options.indexWhere((option) => option.category == selected.category);
    return index < 0 ? 0 : index;
  }

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
    _pages.dispose();
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

    final images = VehicleImageRepository(controller.apiClient);
    // Paint from cache immediately, then refresh in the background. Waiting on
    // the network to show a picture the customer has already seen would be a
    // poor trade.
    final cachedImages = await images.cached();

    final options = await repository.optionsFor(
      distanceKm: distanceKm,
      durationMinutes: minutes,
      pickupLatitude: widget.pickupPoint.latitude,
      pickupLongitude: widget.pickupPoint.longitude,
    );
    if (!mounted) return;

    images.refresh().then((fresh) {
      if (mounted && fresh.isNotEmpty) setState(() => _images = fresh);
    });

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

    // Open the pager on the same vehicle, without an animation the customer
    // never asked for.
    //
    // Unconditionally, including index 0. PageController keeps its page across
    // a rebuild, so skipping the jump for the first vehicle left the pager
    // showing whatever had been swiped to while the pills and the fare panel
    // described a different one.
    if (preferred != null && options.isNotEmpty) {
      final index = options.indexOf(preferred);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients && index >= 0) {
          _pages.jumpToPage(index);
        }
      });
    }

    setState(() {
      _options = options;
      _selected = preferred;
      _images = cachedImages;
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

  /// Chosen from the pill row.
  ///
  /// Animates the photograph across so the two controls never disagree about
  /// which vehicle is showing.
  void _select(VehicleOption option) {
    final target =
        _options.indexWhere((item) => item.category == option.category);
    _apply(option);
    if (target >= 0 && _pages.hasClients) {
      _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Chosen by swiping the photograph.
  ///
  /// No animation call here — the page is already where the finger left it, and
  /// animating towards it would fight the gesture.
  void _onPageChanged(int index) {
    if (index < 0 || index >= _options.length) return;
    _apply(_options[index]);
  }

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
    final value = await showUdDialog<int>(
      context: context,
      title: 'Your offer',
      // The band is stated here rather than only enforced below. A customer
      // typing 40 and getting 50 back without a word looks like the app
      // ignoring them; the same number with the floor on screen does not.
      message: _minimum > 0
          ? 'Between PKR ${_minimum.round()} and PKR ${_maximum.round()}.'
          : null,
      content: UdTextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        label: 'Fare (PKR)',
        icon: Icons.payments_rounded,
      ),
      actions: [
        // Builder, so the buttons pop the dialog's own route rather than
        // whatever sits under this screen's context. Same shape as every other
        // showUdDialog in the app.
        Builder(
          builder: (dialogContext) => UdButtonRow(
            children: [
              UdButton.outline(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialogContext),
              ),
              UdButton.primary(
                label: 'Set',
                onPressed: () => Navigator.pop(
                  dialogContext,
                  int.tryParse(controller.text.trim()),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (value != null && value > 0 && mounted) {
      // Typed figures obey the same band as the stepper — and the same band
      // the API will check, so a number accepted here is never refused on the
      // next screen.
      final floor = _minimum > 0 ? _minimum : 50;
      setState(() => _fare = value.clamp(floor, _maximum));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // No outer SafeArea: the header draws its own top inset and the fare
      // panel its own bottom one, so wrapping the pair would inset twice.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RouteHeader(
            pickup: widget.pickupLabel,
            destination: widget.destinationLabel,
            route: _route,
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final selected = _selected;
    if (selected == null) return const SizedBox.shrink();

    // The photograph gets the largest single share of the screen. It is what
    // the customer is choosing between, and a vehicle shown at thumbnail size
    // is a label with a picture next to it rather than a picture.
    final heroHeight =
        (MediaQuery.sizeOf(context).height * .38).clamp(230.0, 400.0);

    return Column(
      // Stretch, so the fare panel and the rows above it span the screen
      // whatever constraints this column is handed. A Column's default is
      // centre, which gives its children loose width — and a child that sizes
      // itself from its constraints then collapses.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Route options, when there is more than one.
        //
        // Chips rather than only tapping the lines on the map. A route drawn on
        // a phone is a few pixels wide and two of them run together for most of
        // their length — a target nobody can hit reliably. The map still shows
        // which one is chosen; the chips are how it is chosen.
        if (_routes.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 12, AppSizes.sidePadding, 0),
            child: SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _routes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _RouteChip(
                  route: _routes[index],
                  // The first is the shortest by construction, and the one
                  // people take unless they have a reason not to.
                  shortest: index == 0,
                  selected: index == _routeIndex,
                  onTap: () => _selectRoute(index),
                ),
              ),
            ),
          ),

        // Every vehicle's fare, on its own pill.
        //
        // The comparison is the decision, and it used to be four swipes deep:
        // the customer had to page through the photographs one at a time to
        // find out what a Coster cost. Four numbers side by side answer it at a
        // glance, and the row still fits without scrolling because the labels
        // are short.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 12, AppSizes.sidePadding, 0),
          child: Row(
            children: [
              for (final option in _options) ...[
                Expanded(
                  child: _VehiclePill(
                    key: _pillKeys.putIfAbsent(option.category, GlobalKey.new),
                    option: option,
                    fare: _fareForOption(option),
                    selected: option.category == selected.category,
                    onTap: () => _select(option),
                  ),
                ),
                if (option != _options.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
            children: [
              // No separate Vehicle / Drivers toggle any more.
              //
              // It was a second row of controls under the pills, and the
              // driver count — the thing a waiting customer actually wants —
              // was hidden behind it. The count now sits on the photograph, and
              // tapping it turns the photograph into the map.
              SizedBox(
                height: heroHeight,
                child: _showMap
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.sidePadding),
                        child: ClipRRect(
                          borderRadius: AppRadii.all(AppRadii.largeCard),
                          child: UdMap(
                            controller: _mapController,
                            initialCenter: widget.pickupPoint,
                            zoom: 14.2,
                            // Interactive here, unlike the offers screen: the
                            // whole point is that the customer can zoom out to
                            // see how far the nearest driver really is.
                            showMyLocation: false,
                            // Every route, with the chosen one on top and in
                            // the accent colour.
                            //
                            // Drawn in reverse so the selected line paints last
                            // and is never buried under an alternative it
                            // overlaps — which is most of the way, for most
                            // pairs of routes.
                            polylines: [
                              for (var i = _routes.length - 1; i >= 0; i--)
                                if (i != _routeIndex)
                                  UdPolyline(
                                    id: 'route-$i',
                                    points: _routes[i].points,
                                    color: AppText.disabled,
                                    width: 3,
                                    onTap: () => _selectRoute(i),
                                  ),
                              if (_route != null)
                                UdPolyline(
                                  id: 'route-selected',
                                  points: _route!.points,
                                  color: AppColors.secondary,
                                  width: 5,
                                ),
                            ],
                            circles: [
                              UdCircle(
                                id: 'nearby-radius',
                                centre: widget.pickupPoint,
                                radiusMetres: _nearbyRadiusKm * 1000,
                              ),
                            ],
                            markers: [
                              UdMarker(
                                id: 'pickup',
                                position: widget.pickupPoint,
                                label: widget.pickupLabel,
                              ),
                              for (final vehicle in _nearby)
                                UdMarker(
                                  id: 'nearby-${vehicle.id}',
                                  position: vehicle.point,
                                  sprite: vehicle.sprite,
                                  headingDegrees: vehicle.headingDegrees,
                                ),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          PageView.builder(
                            controller: _pages,
                            itemCount: _options.length,
                            onPageChanged: _onPageChanged,
                            itemBuilder: (context, index) {
                              final option = _options[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSizes.sidePadding),
                                child: _VehiclePhoto(
                                  option: option,
                                  imageUrl: _images[
                                      VehicleImageRepository.settingKeyFor(
                                              option.category) ??
                                          ''],
                                ),
                              );
                            },
                          ),

                          // Seats, bottom left. Two words of description under
                          // the photograph told the customer less than a number
                          // and a figure on top of it.
                          Positioned(
                            left: 32,
                            bottom: 14,
                            child: _PhotoBadge(
                              icon: Icons.people_alt_rounded,
                              label: '${selected.seats}',
                            ),
                          ),

                          // Drivers nearby, bottom right, tappable.
                          //
                          // Always visible, so the answer to "is anyone around"
                          // does not need a tab. Tapping swaps the photograph
                          // for the map rather than opening another screen.
                          Positioned(
                            right: 32,
                            bottom: 14,
                            child: _PhotoBadge(
                              icon: Icons.my_location_rounded,
                              label: '${_nearby.length} nearby',
                              highlight: _nearby.isNotEmpty,
                              onTap: () => setState(() => _showMap = true),
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 12),
              if (!_showMap)
                _PageDots(count: _options.length, index: _index)
              else
                // The way back from the map. A view you can enter and not leave
                // is a trap, and the badge that opened it is now covered by it.
                Center(
                  child: UdButton.ghost(
                    label: 'Show the vehicle',
                    icon: Icons.photo_outlined,
                    size: UdButtonSize.small,
                    expand: false,
                    onPressed: () => setState(() => _showMap = false),
                  ),
                ),

              // Only a vehicle with seats to spare can be sold by the seat. For
              // everything else the row is absent rather than disabled: a
              // control that cannot be used is worse than one that was never
              // there.
              if (selected.allowsPerSeat) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.sidePadding),
                  child: _BookingTypeToggle(
                    value: _bookingType,
                    onChanged: _setBookingType,
                  ),
                ),
                if (_perSeat) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.sidePadding),
                    child: _SeatStepper(
                      seats: _seats,
                      maximum: selected.seats,
                      perSeatFare: selected.perSeatFare,
                      onChanged: _setSeats,
                    ),
                  ),
                ],
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.sidePadding),
                  child: UdBanner(
                    tone: UdTone.warn,
                    icon: Icons.error_outline_rounded,
                    text: _error!,
                  ),
                ),
              ],
            ],
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
          onSubmit: _findOffers,
        ),
      ],
    );
  }
}

/// The trip, stated plainly at the top of the screen.
///
/// This replaces a second map. The customer has just seen the route on Home;
/// what they need here is confirmation of where they are going and roughly how
/// long it takes, while they decide what to pay. Repeating the map would cost a
/// tile session and the space the vehicle list needs.
class _RouteHeader extends StatelessWidget {
  const _RouteHeader({
    required this.pickup,
    required this.destination,
    required this.route,
    required this.onBack,
  });

  final String pickup;
  final String destination;
  final TripRoute? route;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 12, AppSizes.sidePadding, 14),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UdIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: onBack,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 2),
                  // Both ends on one line.
                  //
                  // Two stacked From/To blocks spent about ninety pixels of a
                  // phone screen saying what an arrow says. The destination is
                  // the part that matters and keeps its weight; the pickup is
                  // where the customer is standing, and they know that already.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          pickup,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.small.copyWith(
                            fontSize: 13.5,
                            color: AppText.secondary,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 7),
                        child: Icon(Icons.arrow_forward_rounded,
                            size: 15, color: AppText.caption),
                      ),
                      Flexible(
                        flex: 2,
                        child: Text(
                          destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (route != null) ...[
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 16, color: AppColors.brandInk),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            '${route!.durationLabel}  ·  '
                            '${route!.distanceLabel}'
                            '${route!.summary.isEmpty ? '' : '  ·  via '
                                '${route!.summary.split('/').first.trim()}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.small.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ),
                      ],
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

/// A vehicle type in the pill row.
///
/// Selected is navy with a lime icon tile and a lime price. Not lime on lime,
/// and never white on lime — the only ink that goes on the brand colour is
/// navy, and the only ink that goes on navy is white or lime.
class _VehiclePill extends StatelessWidget {
  const _VehiclePill({
    required this.option,
    required this.fare,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final VehicleOption option;

  /// What this vehicle would cost for this trip.
  final int fare;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}, ${Money.amount(fare)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : AppColors.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.tile),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UdIconTile(
                icon: option.icon,
                tone: selected ? UdIconTone.lime : UdIconTone.neutral,
                size: UdIconTileSize.sm,
              ),
              const SizedBox(height: 7),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.overline.copyWith(
                  letterSpacing: 0,
                  color: selected ? AppText.onInkMuted : AppText.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Money.amount(fare),
                maxLines: 1,
                style: AppType.caption.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: selected ? AppColors.brand : AppText.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen vehicle, shown large.
///
/// This is the only picture on the screen and there is room for it, so it gets
/// real size — a small image floating in empty space reads as a placeholder
/// nobody finished.
/// The hero toggle, its `_Half` button and `_RateBasis` used to sit here.
///
/// All three are gone. The toggle was a second row of controls under the
/// pills whose only job was to reveal a driver count — that count is now a
/// badge on the photograph itself, which costs no height at all. `_RateBasis`
/// printed the per-kilometre rate, which is not something the customer was
/// asked to check.

/// One route option: how far, how long, and whether it is the short way.
class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.route,
    required this.shortest,
    required this.selected,
    required this.onTap,
  });

  final TripRoute route;
  final bool shortest;
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
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 13 : 14,
            vertical: selected ? 7 : 8,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandWash : AppColors.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.tile),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                shortest ? 'SHORTEST' : 'ALTERNATIVE',
                // AppType.overline's own 12.5, not 11: this label sits on a
                // route chip over a map, which is the worst reading condition
                // in the app, not a reason to make it smaller.
                style: AppType.overline.copyWith(
                  color: selected ? AppColors.brandInk : AppText.secondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${route.distanceKm.toStringAsFixed(route.distanceKm < 10 ? 1 : 0)} km'
                '  ·  $minutes min',
                style: AppType.small.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
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

/// A small label over the vehicle photograph.
///
/// On the picture rather than under it. The space beneath was a line of grey
/// text nobody read, and putting seats and the driver count where the eye
/// already is costs no extra height.
class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({
    required this.icon,
    required this.label,
    this.highlight = false,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Draws attention when the number is worth acting on — drivers are nearby.
  final bool highlight;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = highlight ? AppColors.brandInk : AppText.primary;

    return Material(
      color: AppColors.background,
      borderRadius: AppRadii.all(AppRadii.tile),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.tile),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadii.all(AppRadii.tile),
            boxShadow: AppShadows.floating,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: ink),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ink,
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

/// One vehicle photograph, filling its page.
///
/// The whole vehicle stays visible: `BoxFit.contain` inside a rounded frame,
/// never cropped. A cropped bike with its front wheel cut off looks like a
/// mistake, and this picture is the main thing the customer is judging.
class _VehiclePhoto extends StatelessWidget {
  const _VehiclePhoto({required this.option, this.imageUrl});

  final VehicleOption option;

  /// Admin-supplied photograph. Falls back to the bundled illustration, and
  /// then to an icon, so an unset or broken URL never leaves a hole.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.largeCard),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: url.isEmpty
          ? _bundled()
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _bundled(),
              // The outline, not the stock photograph, while the real one
              // loads. Showing _bundled() here meant a slow connection
              // displayed a generic car for a second and then swapped it —
              // which reads as the app having shown the wrong vehicle.
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _placeholder(),
            ),
    );
  }

  Widget _bundled() {
    if (option.asset.isEmpty) return _placeholder();
    return Image.asset(
      option.asset,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  /// Shown when there is no photograph for this vehicle.
  ///
  /// An outline of the right vehicle rather than a photograph of the wrong one.
  Widget _placeholder() => Center(
        child: Icon(
          option.icon,
          size: 104,
          color: AppColors.borderStrong,
        ),
      );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? AppColors.navy : AppColors.borderStrong,
              borderRadius: AppRadii.all(3),
            ),
          ),
      ],
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

class _SeatStepper extends StatelessWidget {
  const _SeatStepper({
    required this.seats,
    required this.maximum,
    required this.perSeatFare,
    required this.onChanged,
  });

  final int seats;
  final int maximum;
  final int perSeatFare;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return UdCard(
      tone: UdCardTone.tint,
      radius: AppRadii.tile,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$seats ${seats == 1 ? 'seat' : 'seats'}',
                  style: AppType.listTitle.copyWith(
                    fontSize: 16,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'About PKR $perSeatFare each',
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
              ],
            ),
          ),
          UdIconButton(
            icon: Icons.remove_rounded,
            small: true,
            tooltip: 'One seat fewer',
            onPressed: seats > 1 ? () => onChanged(seats - 1) : null,
          ),
          const SizedBox(width: 4),
          UdIconButton(
            icon: Icons.add_rounded,
            small: true,
            tooltip: 'One seat more',
            onPressed: seats < maximum ? () => onChanged(seats + 1) : null,
          ),
        ],
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
    if (recommended == 0) return '';
    // At the floor, say so plainly. "31% below" reads like there is further to
    // go; there is not, and the customer pressing minus again needs to know
    // why nothing moves.
    if (minimum > 0 && fare <= minimum) {
      return 'Minimum fare for this trip · may take longer';
    }
    if (fare == recommended) {
      return perSeat ? 'Recommended for $seats seats' : 'Recommended fare';
    }
    final difference = ((fare - recommended) / recommended * 100).round();
    if (difference > 0) return '$difference% above · faster pickup';
    return '${difference.abs()}% below · may take longer';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 12, AppSizes.sidePadding, 14),
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

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 15, color: AppText.caption),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    _isFixed
                        ? 'Set fare for this route · not negotiable'
                        : 'Tolls, parking and entry fees are not included',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(color: AppText.caption),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 14),
            UdButton.primary(
              label: vehicleLabel.isEmpty
                  ? 'Find offers'
                  : 'Find offers · $vehicleLabel',
              trailingIcon: Icons.chevron_right_rounded,
              busy: submitting,
              onPressed: onSubmit,
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
