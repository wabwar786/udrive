import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking/booking_options.dart';
import '../../core/booking/booking_repository.dart';
import '../../core/routing/route_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/maps/ud_map.dart';
import '../../core/vehicles/nearby_repository.dart';
import '../../core/vehicles/nearby_vehicle.dart';
import '../../core/vehicles/seat_fares_repository.dart';
import '../../core/vehicles/vehicle_image_repository.dart';
import '../../core/vehicles/vehicle_options_repository.dart';
import '../../core/widgets/home_service.dart';
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

  /// The fixed fare covering the vehicle currently shown, if there is one.
  SeatFareQuote? get _fixedSeatFare {
    final option = _selected;
    if (option == null || !_perSeat) return null;
    return _seatFares[option.category.toLowerCase()];
  }

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

  int get _recommended {
    final fixed = _fixedSeatFare;
    if (fixed != null) return fixed.perSeatFare * _seats;
    return _selected?.fareFor(perSeat: _perSeat, seats: _seats) ?? 0;
  }

  /// What one vehicle would cost, for the price shown on its pill.
  ///
  /// Always the whole-vehicle fare, whatever the customer has chosen for the
  /// selected one. The pills are a comparison between vehicles, and comparing a
  /// Coster priced for two seats against a whole Car is not a comparison — it
  /// is two different questions with one number each.
  int _fareForOption(VehicleOption option) {
    final fixed = _seatFares[option.category];
    if (fixed != null) return fixed.perSeatFare;
    return option.fareFor(perSeat: false, seats: option.seats);
  }

  /// The lowest offer this vehicle will take, from the admin's own rate table.
  ///
  /// This replaces the old floor of half the recommendation. Half was a guess;
  /// the admin has set an actual figure, and an offer below it is one no driver
  /// answers.
  int get _minimum {
    // A fixed route fare is its own floor and its own ceiling.
    final fixed = _fixedSeatFare;
    if (fixed != null) return fixed.perSeatFare * _seats;
    return _selected?.minimumFor(perSeat: _perSeat, seats: _seats) ?? 0;
  }

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
    // continues that decision rather than restarting it.
    final preferred = options.isEmpty
        ? null
        : options.firstWhere(
            (option) => option.service == widget.service,
            orElse: () => options.first,
          );

    // Open the pager on the same vehicle, without an animation the customer
    // never asked for.
    if (preferred != null && options.isNotEmpty) {
      final index = options.indexOf(preferred);
      if (index > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pages.hasClients) _pages.jumpToPage(index);
        });
      }
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
        _fare = _recommended;
      }
    });
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

    for (final option in options) {
      final quote = await repository.quote(
        category: option.category,
        fromLatitude: widget.pickupPoint.latitude,
        fromLongitude: widget.pickupPoint.longitude,
        toLatitude: widget.destinationPoint.latitude,
        toLongitude: widget.destinationPoint.longitude,
      );
      if (!mounted) return;
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
      _fare = _recommended;
    });
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
      _fare = _recommended;
    });
  }

  void _setSeats(int value) {
    final option = _selected;
    setState(() {
      _seats = value.clamp(1, option?.seats ?? 12);
      // Recomputed either way: on a fixed route this is the listed fare times
      // the seats, and off one it is the recommendation for the new count.
      _fare = _recommended;
    });
  }

  void _nudge(int direction) {
    if (_selected == null) return;
    // Belt and braces. The buttons are hidden on a fixed route, but the state
    // is what actually protects the fare and the widget tree is not the place
    // to enforce a pricing rule.
    if (_fixedSeatFare != null) return;
    setState(() {
      // Never below the admin's minimum for this vehicle.
      final floor = _minimum;
      _fare = (_fare + direction * _step).clamp(floor, 500000);
    });
  }

  Future<void> _findOffers() async {
    final option = _selected;
    if (option == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final controller = AppControllerScope.of(context);
      final repository = BookingRepository(controller.apiClient);

      final request = await repository.createRideRequest({
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
    }
  }

  Future<void> _editFare() async {
    // Nothing to type on a fixed route. The tap is already disabled, but the
    // state is what protects the fare — a widget tree is not the place to
    // enforce a pricing rule.
    if (_fixedSeatFare != null) return;

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

    if (value != null && value > 0 && mounted) {
      // Typed figures obey the same floor as the stepper. Allowing one route
      // around it would mean the customer waits for offers that never come.
      final floor = _minimum > 0 ? _minimum : 50;
      setState(() => _fare = value.clamp(floor, 500000));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
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
      children: [
        // Route options, when there is more than one.
        //
        // Chips rather than only tapping the lines on the map. A route drawn on
        // a phone is a few pixels wide and two of them run together for most of
        // their length — a target nobody can hit reliably. The map still shows
        // which one is chosen; the chips are how it is chosen.
        if (_routes.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: SizedBox(
              height: 54,
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
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
                if (option != _options.last) const SizedBox(width: 6),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
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
                            left: 26,
                            bottom: 12,
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
                            right: 26,
                            bottom: 12,
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
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showMap = false),
                    icon: const Icon(Icons.photo_outlined, size: 16),
                    label: const Text('Show the vehicle'),
                  ),
                ),

              // Only a vehicle with seats to spare can be sold by the seat. For
              // everything else the row is absent rather than disabled: a
              // control that cannot be used is worse than one that was never
              // there.
              if (selected.allowsPerSeat) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _BookingTypeToggle(
                    value: _bookingType,
                    onChanged: _setBookingType,
                  ),
                ),
                if (_perSeat) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTint.warning,
                      borderRadius: AppRadii.all(AppRadii.row),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: AppTint.warningText),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppTint.warningText,
                            ),
                          ),
                        ),
                      ],
                    ),
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
          perSeat: _perSeat,
          seats: _seats,
          submitting: _submitting,
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
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppText.primary,
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
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
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppText.secondary,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 14, color: AppText.disabled),
                    ),
                    Flexible(
                      flex: 2,
                      child: Text(
                        destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (route != null) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 14, color: AppColors.secondary),
                      const SizedBox(width: 6),
                      Text(
                        '${route!.durationLabel}  ·  ${route!.distanceLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                      if (route!.summary.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'via ${route!.summary.split('/').first.trim()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppText.secondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vehicle type in the pill row.
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
      label: '${option.label}, PKR $fare',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondary : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppText.onBrand : AppText.secondary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                NumberFormat('#,###').format(fare),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.2,
                  color: selected ? AppText.onBrand : AppText.primary,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTint.brand : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.secondary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shortest ? 'Shortest' : 'Alternative',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .3,
                  color: selected ? AppColors.secondary : AppText.disabled,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${route.distanceKm.toStringAsFixed(route.distanceKm < 10 ? 1 : 0)} km'
                '  ·  $minutes min',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppText.primary : AppText.secondary,
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
    final ink = highlight ? AppColors.secondary : AppText.secondary;

    return Material(
      color: AppColors.surface.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
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
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _bundled(),
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
          color: AppColors.secondary.withValues(alpha: .55),
        ),
      );
}

/// Which photograph of how many.
///
/// Swiping is not visible the way a button is, so the dots are there to say the
/// gesture exists — and to show that there is more than one vehicle without
/// making the customer count the pills.
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
              color: i == index ? AppColors.secondary : AppColors.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

/// Per seat or whole vehicle. Only shown for vehicles with seats to spare.
class _BookingTypeToggle extends StatelessWidget {
  const _BookingTypeToggle({required this.value, required this.onChanged});

  final BookingType value;
  final ValueChanged<BookingType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: BookingType.values.map((type) {
          final selected = type == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: type.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color:
                        selected ? AppColors.secondary : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        type.icon,
                        size: 17,
                        color: selected ? AppText.onBrand : AppText.disabled,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color:
                              selected ? AppText.onBrand : AppText.secondary,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$seats ${seats == 1 ? 'seat' : 'seats'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'About PKR $perSeatFare each',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          _SmallStep(
            icon: Icons.remove_rounded,
            enabled: seats > 1,
            onTap: () => onChanged(seats - 1),
          ),
          const SizedBox(width: 8),
          _SmallStep(
            icon: Icons.add_rounded,
            enabled: seats < maximum,
            onTap: () => onChanged(seats + 1),
          ),
        ],
      ),
    );
  }
}

class _SmallStep extends StatelessWidget {
  const _SmallStep({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 19,
            color: enabled ? AppText.primary : AppText.disabled,
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
    required this.perSeat,
    required this.seats,
    required this.submitting,
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

  final bool perSeat;
  final int seats;
  final bool submitting;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;

  bool get _isFixed => fixedRoute != null;

  String get _caption {
    final route = fixedRoute;
    if (route != null) {
      return 'Fixed fare · ${route.routeLabel}'
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

  static String grouped(int value) {
    final digits = value.toString();
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Directly above the amount, because it is a caveat about the
            // amount. Sitting at the bottom of a scrolling list it was reached
            // only by customers who happened to scroll — and never by the ones
            // who went straight to the fare, who are exactly the ones it is
            // for.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: AppText.disabled),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _isFixed
                        ? 'Set fare for this route · not negotiable'
                        : 'Tolls, parking and entry fees are not included',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: AppText.disabled,
                    ),
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
                          'PKR ${grouped(fare)}',
                          style: const TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.4,
                            color: AppText.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _caption,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isFixed)
                  _StepButton(icon: Icons.add_rounded, onTap: onIncrease),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: Material(
                color: AppColors.secondary,
                borderRadius: AppRadii.all(AppRadii.cta),
                child: InkWell(
                  onTap: submitting ? null : onSubmit,
                  borderRadius: AppRadii.all(AppRadii.cta),
                  child: Center(
                    child: submitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppText.onBrand,
                            ),
                          )
                        : Text(
                            'Find offers',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppText.onBrand,
                            ),
                          ),
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

/// The large circular buttons either side of the fare.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppText.primary : AppText.disabled,
          ),
        ),
      ),
    );
  }
}
