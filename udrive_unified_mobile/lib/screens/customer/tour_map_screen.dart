import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/maps/ud_map.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/rate_driver_card.dart';
import '../../models/booking_models.dart';
import 'tour_driver_detail_screen.dart';

/// Shows nearby drivers who received the tour request and lets the customer
/// pick whichever price suits them.
///
/// Offers arrive through the same `loadRideOffers` polling the on-demand
/// Driver Offers screen uses — no new API surface. Accepting opens the advance
/// payment sheet, which hands off to `selectLiveDriverOffer`.
class TourMapScreen extends StatefulWidget {
  const TourMapScreen({
    required this.rideRequestId,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.pickupPoint,
    required this.destinationPoint,
    required this.departureAt,
    required this.passengers,
    super.key,
  });

  final String rideRequestId;
  final String pickupLabel;
  final String destinationLabel;
  final LatLng pickupPoint;
  final LatLng destinationPoint;
  final DateTime departureAt;
  final int passengers;

  @override
  State<TourMapScreen> createState() => _TourMapScreenState();
}

class _TourMapScreenState extends State<TourMapScreen> {
  Timer? _poller;
  bool _loading = true;
  bool _accepting = false;
  final Set<String> _declined = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poller = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    final controller = AppControllerScope.of(context);
    try {
      await controller.loadRideOffers(widget.rideRequestId);
    } catch (_) {
      // Keep the last good list; a failed poll is not worth interrupting for.
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  List<LiveDriverOffer> _offers(AppController controller) => controller
      .liveDriverOffers
      .where((offer) =>
          offer.rideRequestId == widget.rideRequestId &&
          !_declined.contains(offer.id))
      .toList(growable: false);

  Future<void> _accept(LiveDriverOffer offer) async {
    final advance = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdvancePaymentSheet(
        offer: offer,
        passengers: widget.passengers,
      ),
    );
    if (advance != true || !mounted) return;

    setState(() => _accepting = true);
    final controller = AppControllerScope.of(context);
    try {
      final booking = await controller.selectLiveDriverOffer(
        rideRequestId: widget.rideRequestId,
        offerId: offer.id,
        advanceAmount: _advanceFor(offer.finalAmount),
      );
      if (!mounted) return;
      _poller?.cancel();
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TourDriverDetailScreen(
            booking: booking,
            offer: offer,
            pickupLabel: widget.pickupLabel,
            destinationLabel: widget.destinationLabel,
            departureAt: widget.departureAt,
            passengers: widget.passengers,
            advancePaid: _advanceFor(offer.finalAmount),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  static double _advanceFor(double fare) =>
      (fare * AppConfig.tourAdvancePercent).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final offers = _offers(controller);
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SizedBox(
            height: height * .52,
            width: double.infinity,
            child: UdMap(
              initialCenter: widget.pickupPoint,
              routeOrigin: widget.pickupPoint,
              routeDestination: widget.destinationPoint,
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
                  hue: UdMarkerHue.navy,
                ),
              ],
              polylines: [
                UdPolyline(
                  id: 'route',
                  points: [widget.pickupPoint, widget.destinationPoint],
                ),
              ],
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CircleBack(onTap: () => Navigator.maybePop(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RoutePill(
                      pickup: widget.pickupLabel,
                      destination: widget.destinationLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: .50,
            minChildSize: .34,
            maxChildSize: .54,
            snap: true,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: AppShadows.panel,
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Offers from nearby drivers',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                      if (offers.isNotEmpty)
                        Text(
                          '${offers.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppText.secondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (offers.isEmpty)
                    _WaitingPanel(loading: _loading)
                  else
                    ...offers.map(
                      (offer) => Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: RateDriverCard(
                          fareLabel:
                              'PKR ${_money.format(offer.finalAmount)}',
                          etaLabel: '${offer.estimatedArrivalMinutes} min away',
                          driverName: offer.driverName,
                          rating: offer.driverRating,
                          rideCount: offer.completedTrips,
                          vehicleLabel: offer.vehicle,
                          plateLabel: offer.registrationNumber,
                          verified: offer.safetyScore >= 80,
                          capacityChip: '${widget.passengers} passenger'
                              '${widget.passengers == 1 ? '' : 's'}',
                          busy: _accepting,
                          onAccept: () => _accept(offer),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final _money = NumberFormat.decimalPattern();
}

class _CircleBack extends StatelessWidget {
  const _CircleBack({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: AppShadows.floating,
          ),
          child: const Icon(Icons.arrow_back_rounded,
              size: 19, color: AppColors.navy),
        ),
      ),
    );
  }
}

class _RoutePill extends StatelessWidget {
  const _RoutePill({required this.pickup, required this.destination});

  final String pickup;
  final String destination;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .95),
        borderRadius: AppRadii.all(AppRadii.row),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$pickup  →  $destination',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Showing nearby drivers on the map',
            style: TextStyle(fontSize: 10.5, color: AppText.secondary),
          ),
        ],
      ),
    );
  }
}

class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(AppRadii.card),
      ),
      child: Column(
        children: [
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.travel_explore_rounded,
                size: 30, color: AppText.disabled),
          const SizedBox(height: 12),
          const Text(
            'Waiting for drivers near this route…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Offers appear here as drivers respond. You can keep this screen '
            'open.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, height: 1.4, color: AppText.disabled),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- advance payment

/// Bottom sheet shown before a tour driver is confirmed.
///
/// The advance defaults to [AppConfig.tourAdvancePercent] of the fare and can
/// be raised by the customer, never lowered — that is the agreed business rule.
class _AdvancePaymentSheet extends StatefulWidget {
  const _AdvancePaymentSheet({
    required this.offer,
    required this.passengers,
  });

  final LiveDriverOffer offer;
  final int passengers;

  @override
  State<_AdvancePaymentSheet> createState() => _AdvancePaymentSheetState();
}

class _AdvancePaymentSheetState extends State<_AdvancePaymentSheet> {
  late final TextEditingController _amount;
  late final double _minimum;
  final _money = NumberFormat.decimalPattern();
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _minimum =
        (widget.offer.finalAmount * AppConfig.tourAdvancePercent)
            .roundToDouble();
    _amount = TextEditingController(text: _minimum.round().toString());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _entered =>
      double.tryParse(_amount.text.trim()) ?? 0;

  bool get _valid =>
      _entered >= _minimum && _entered <= widget.offer.finalAmount;

  @override
  Widget build(BuildContext context) {
    final fare = widget.offer.finalAmount;
    final balance = (fare - _entered).clamp(0, fare);
    final percentLabel =
        '${(AppConfig.tourAdvancePercent * 100).round()}% minimum';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        decoration: BoxDecoration(
          color: Colors.white,
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
              const SizedBox(height: 16),
              const Text(
                'Advance payment',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 14),

              // Selected driver + vehicle summary.
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: AppTint.surface,
                  borderRadius: AppRadii.all(AppRadii.row),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.offer.driverName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.offer.vehicle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'PKR ${_money.format(fare)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppText.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: AppTint.success,
                  borderRadius: AppRadii.all(AppRadii.field),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 15, color: AppTint.successText),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This amount is held by UDrive and paid to your driver '
                        'on arrival. The balance is settled directly with the '
                        'driver.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppTint.successText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'Advance  ·  $percentLabel',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppText.secondary,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'PKR',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppText.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppText.primary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
              if (!_valid)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Enter between PKR ${_money.format(_minimum)} and '
                    'PKR ${_money.format(fare)}.',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Balance on arrival',
                    style: TextStyle(
                        fontSize: 12, color: AppText.secondary),
                  ),
                  Text(
                    'PKR ${_money.format(balance)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: Material(
                  color: _valid ? AppColors.navy : AppColors.border,
                  borderRadius: AppRadii.all(AppRadii.cta),
                  child: InkWell(
                    borderRadius: AppRadii.all(AppRadii.cta),
                    onTap: !_valid || _paying
                        ? null
                        : () {
                            setState(() => _paying = true);
                            Navigator.pop(context, true);
                          },
                    child: Center(
                      child: _paying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'Pay Advance & Confirm',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _valid
                                    ? Colors.white
                                    : AppText.disabled,
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
    );
  }
}
