import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking/booking_options.dart';
import '../../core/booking/booking_repository.dart';
import '../../core/maps/ud_map.dart';
import '../../core/routing/route_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
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

  final HomeService service;
  final BookingType bookingType;
  final int seats;

  @override
  State<VehicleChoiceScreen> createState() => _VehicleChoiceScreenState();
}

class _VehicleChoiceScreenState extends State<VehicleChoiceScreen> {
  final _mapController = UdMapController();

  List<VehicleOption> _options = const [];
  VehicleOption? _selected;
  int _fare = 0;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  bool get _perSeat => widget.bookingType == BookingType.perSeat;

  /// How much each tap of the stepper moves the fare.
  ///
  /// Proportional rather than fixed: 50 rupees is a meaningful nudge on a
  /// PKR 600 city ride and meaningless on a PKR 24,000 tour.
  int get _step {
    if (_fare >= 10000) return 500;
    if (_fare >= 3000) return 100;
    return 50;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = AppControllerScope.of(context);
    final repository = VehicleOptionsRepository(controller.apiClient);

    final route = widget.route;
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
      perSeat: _perSeat,
      seats: widget.seats,
    );
    if (!mounted) return;

    // Open on the vehicle matching the service they chose on Home, so the
    // screen continues their decision rather than restarting it.
    final preferred = options.firstWhere(
      (option) => option.service == widget.service,
      orElse: () => options.isEmpty
          ? const VehicleOption(
              category: 'Car',
              label: 'Car',
              description: '',
              seats: 4,
              icon: Icons.directions_car_rounded,
              recommendedFare: 500,
              service: HomeService.car,
            )
          : options.first,
    );

    setState(() {
      _options = options;
      _selected = preferred;
      _fare = preferred.recommendedFare;
      _loading = false;
    });

    final points = route?.points;
    if (points != null && points.isNotEmpty) {
      await _mapController.fitBounds(points, padding: 60);
    } else {
      await _mapController.fitBounds(
        [widget.pickupPoint, widget.destinationPoint],
        padding: 60,
      );
    }
  }

  void _select(VehicleOption option) {
    setState(() {
      _selected = option;
      // Reset to the recommendation for the new vehicle. Carrying a coaster
      // price onto a bike would be nonsense.
      _fare = option.recommendedFare;
    });
  }

  void _nudge(int direction) {
    final option = _selected;
    if (option == null) return;
    setState(() {
      // Never below half the recommendation: an offer that low will not be
      // answered, and letting it be made wastes the customer's time.
      final floor = (option.recommendedFare * 0.5).round();
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
        'bookingType': widget.bookingType.apiValue,
        'seatsRequested': _perSeat ? widget.seats : 1,
        'adults': _perSeat ? widget.seats : 1,
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

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final mapHeight = (height * .38).clamp(220.0, 400.0);
    final route = widget.route;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: mapHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  UdMap(
                    controller: _mapController,
                    initialCenter: widget.pickupPoint,
                    zoom: 12,
                    showMyLocation: false,
                    routeOrigin: widget.pickupPoint,
                    routeDestination: widget.destinationPoint,
                    polylines: [
                      if (route != null && route.points.isNotEmpty)
                        UdPolyline(
                          id: 'trip',
                          points: route.points,
                          color: AppColors.secondary,
                          width: 6,
                        ),
                    ],
                    markers: [
                      UdMarker(
                        id: 'pickup',
                        position: widget.pickupPoint,
                        label: widget.pickupLabel,
                      ),
                      UdMarker(
                        id: 'destination',
                        position: widget.destinationPoint,
                        label: widget.destinationLabel,
                        hue: UdMarkerHue.danger,
                      ),
                    ],
                  ),
                  Positioned(
                    top: 10,
                    left: 12,
                    child: _RoundButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 62,
                    right: 12,
                    child: _TripHeader(
                      pickup: widget.pickupLabel,
                      destination: widget.destinationLabel,
                      route: route,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet() {
    final selected = _selected;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            children: [
              if (selected != null) ...[
                _SelectedVehicleCard(
                  option: selected,
                  perSeat: _perSeat,
                  seats: widget.seats,
                ),
                const SizedBox(height: 12),
                _FareStepper(
                  fare: _fare,
                  recommended: selected.recommendedFare,
                  onDecrease: () => _nudge(-1),
                  onIncrease: () => _nudge(1),
                  onEdit: _editFare,
                ),
                const SizedBox(height: 18),
              ],

              ..._options
                  .where((option) => option.category != selected?.category)
                  .map(
                    (option) => _VehicleRow(
                      option: option,
                      perSeat: _perSeat,
                      seats: widget.seats,
                      onTap: () => _select(option),
                    ),
                  ),

              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: AppRadii.all(AppRadii.row),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: AppText.disabled),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Fare does not include tolls, parking or entry fees. '
                        'Settle those with your driver.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppText.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
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

        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: AppShadows.navBar,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // No auto-accept toggle here.
                //
                // The API has no such flag, and a switch that silently did
                // nothing would be worse than its absence: the customer would
                // believe a ride had been agreed when it had not. Accepting an
                // offer stays a deliberate tap on the next screen.
                //
                // Adding it properly means a server-side rule — accept the
                // first offer at or below this fare — which is a real feature,
                // not a checkbox.
                SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: Material(
                    color: AppColors.secondary,
                    borderRadius: AppRadii.all(AppRadii.cta),
                    child: InkWell(
                      onTap: _submitting ? null : _findOffers,
                      borderRadius: AppRadii.all(AppRadii.cta),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppText.onBrand,
                                ),
                              )
                            : const Text(
                                'Find offers',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
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
        ),
      ],
    );
  }

  /// Lets the fare be typed, for when the stepper would take too many taps.
  Future<void> _editFare() async {
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
      setState(() => _fare = value.clamp(50, 500000));
    }
  }
}

class _TripHeader extends StatelessWidget {
  const _TripHeader({
    required this.pickup,
    required this.destination,
    required this.route,
  });

  final String pickup;
  final String destination;
  final TripRoute? route;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .92),
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.trip_origin_rounded,
                  size: 13, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pickup,
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
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.square_rounded, size: 11, color: Colors.white),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                ),
              ),
              if (route != null) ...[
                const SizedBox(width: 8),
                Text(
                  '~${route!.durationLabel}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedVehicleCard extends StatelessWidget {
  const _SelectedVehicleCard({
    required this.option,
    required this.perSeat,
    required this.seats,
  });

  final VehicleOption option;
  final bool perSeat;
  final int seats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTint.brand,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(option.icon, size: 27, color: AppColors.secondary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 14, color: AppText.secondary),
                    const SizedBox(width: 3),
                    Text(
                      perSeat ? '$seats seats' : '${option.seats}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppText.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  option.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppText.disabled,
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

class _FareStepper extends StatelessWidget {
  const _FareStepper({
    required this.fare,
    required this.recommended,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEdit,
  });

  final int fare;
  final int recommended;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEdit;

  /// Tells the customer how their offer compares, so a number well under the
  /// recommendation does not look like it will be answered as quickly.
  String get _caption {
    if (fare == recommended) return 'Recommended fare';
    final difference = ((fare - recommended) / recommended * 100).round();
    if (difference > 0) return '$difference% above recommended · faster pickup';
    return '${difference.abs()}% below recommended · may take longer';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.remove_rounded, onTap: onDecrease),
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PKR ${_grouped(fare)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.5,
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
          _StepButton(icon: Icons.add_rounded, onTap: onIncrease),
        ],
      ),
    );
  }

  static String _grouped(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, size: 22, color: AppText.primary),
        ),
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({
    required this.option,
    required this.perSeat,
    required this.seats,
    required this.onTap,
  });

  final VehicleOption option;
  final bool perSeat;
  final int seats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(option.icon, size: 23, color: AppText.secondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'PKR ${_FareStepper._grouped(option.recommendedFare)}',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: .92),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 21, color: AppText.primary),
        ),
      ),
    );
  }
}
