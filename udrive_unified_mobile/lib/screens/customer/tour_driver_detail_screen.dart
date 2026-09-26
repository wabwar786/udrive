import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/booking/booking_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import '../operations/trip_chat_screen.dart';

/// Confirmation screen shown once a tour driver is booked and the advance paid.
///
/// The cancellation card runs a live countdown for
/// [AppConfig.tourFreeCancellationWindow]; once it elapses the card turns pale
/// red and the button is disabled. The timer is cancelled on dispose and on a
/// successful cancel, so it can never outlive the screen.
class TourDriverDetailScreen extends StatefulWidget {
  const TourDriverDetailScreen({
    required this.booking,
    required this.offer,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.departureAt,
    required this.passengers,
    required this.advancePaid,
    super.key,
  });

  final LiveBooking booking;
  final LiveDriverOffer offer;
  final String pickupLabel;
  final String destinationLabel;
  final DateTime departureAt;
  final int passengers;
  final double advancePaid;

  @override
  State<TourDriverDetailScreen> createState() => _TourDriverDetailScreenState();
}

class _TourDriverDetailScreenState extends State<TourDriverDetailScreen> {
  Timer? _ticker;
  late DateTime _deadline;
  Duration _remaining = AppConfig.tourFreeCancellationWindow;
  bool _cancelling = false;

  final _money = NumberFormat.decimalPattern();

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(AppConfig.tourFreeCancellationWindow);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _deadline.difference(DateTime.now());
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left.isNegative) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _windowOpen => _remaining > Duration.zero;

  String get _countdown {
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _call() async {
    final phone = widget.booking.driverPhone;
    if (phone == null || phone.isEmpty) {
      _snack('No phone number is available for this driver yet.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) _snack('Could not open the dialer.');
  }

  void _chat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        // TripChatScreen, not the old BookingChatScreen — one chat per trip
        // now, on the endpoint the driver's own screen reads.
        //
        // The name comes from the offer rather than the booking: the offer is
        // what this screen was opened with and its driverName is always
        // present, while the booking's is nullable until the server fills it.
        builder: (_) => TripChatScreen(
          bookingId: widget.booking.id,
          myRole: 'Customer',
          otherPartyName: widget.offer.driverName,
        ),
      ),
    );
  }

  Future<void> _openCancelSheet() async {
    final reason = await showUdSheet<String>(
      context: context,
      builder: (_) => const _CancelReasonSheet(),
    );
    if (reason == null || !mounted) return;
    await _cancel(reason);
  }

  Future<void> _cancel(String reason) async {
    setState(() => _cancelling = true);
    final controller = AppControllerScope.of(context);
    try {
      final repository = BookingRepository(controller.apiClient);
      await repository.cancelBooking(widget.booking.id, reason);
      _ticker?.cancel();
      _ticker = null;
      if (!mounted) return;
      await controller.refreshCustomerRideState();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      _snack('$error'.replaceFirst('Exception: ', ''));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final fare = widget.offer.finalAmount;
    final balance = (fare - widget.advancePaid).clamp(0, fare);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _DriverBanner(name: widget.offer.driverName),
          Container(
            color: AppColors.surfaceHigh,
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 16, AppSizes.sidePadding, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.offer.driverName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: AppText.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 15, color: AppTint.star),
                              const SizedBox(width: 4),
                              Text(
                                widget.offer.driverRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.primary,
                                ),
                              ),
                              const Text('  ·  ',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppText.secondary)),
                              Text(
                                '${widget.offer.completedTrips} rides',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppText.secondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.offer.safetyScore >= 80)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded,
                                size: 14, color: AppColors.info),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                const _SectionLabel('Vehicle'),
                const SizedBox(height: 7),
                Text(
                  widget.offer.vehicle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                if (widget.offer.registrationNumber.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.offer.registrationNumber,
                    style: const TextStyle(
                        fontSize: 13, color: AppText.secondary),
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                _KeyValue(
                  label: 'Route',
                  value: '${widget.pickupLabel} → ${widget.destinationLabel}',
                ),
                _KeyValue(
                  label: 'Departure',
                  value: DateFormat('EEE, d MMM yyyy · h:mm a')
                      .format(widget.departureAt),
                ),
                _KeyValue(
                  label: 'Passengers',
                  value: '${widget.passengers}',
                ),
                _KeyValue(
                  label: 'Total fare',
                  value: 'PKR ${_money.format(fare)}',
                ),
                _KeyValue(
                  label: 'Advance paid',
                  value: 'PKR ${_money.format(widget.advancePaid)}',
                  valueColor: AppColors.success,
                ),
                _KeyValue(
                  label: 'Balance on arrival',
                  value: 'PKR ${_money.format(balance)}',
                ),
                const SizedBox(height: 16),
                UdButtonRow(
                  children: [
                    UdButton.outline(
                      label: 'Call',
                      icon: Icons.call_rounded,
                      size: UdButtonSize.small,
                      onPressed: _call,
                    ),
                    UdButton.outline(
                      label: 'Chat',
                      icon: Icons.chat_bubble_outline_rounded,
                      size: UdButtonSize.small,
                      onPressed: _chat,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            child: _CancellationCard(
              windowOpen: _windowOpen,
              countdown: _countdown,
              busy: _cancelling,
              onCancel: _openCancelSheet,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverBanner extends StatelessWidget {
  const _DriverBanner({required this.name});

  final String name;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    return parts.isEmpty ? 'D' : parts.map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The offers API does not return driver photos yet, so this renders
          // a branded initials banner rather than a broken image slot.
          ColoredBox(
            color: AppColors.navy,
            child: Center(
              child: Text(
                _initials,
                // Lime on navy, 13.5:1. It was the deep lime ink, which is a
                // colour chosen to sit on white and measures about 2:1 here.
                style: AppType.display.copyWith(
                  fontSize: 56,
                  color: AppColors.brand,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: UdIconButton(
                  icon: Icons.arrow_back_rounded,
                  variant: UdIconButtonVariant.float,
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppType.overline.copyWith(color: AppText.secondary),
      );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppText.secondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: valueColor ?? AppText.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationCard extends StatelessWidget {
  const _CancellationCard({
    required this.windowOpen,
    required this.countdown,
    required this.busy,
    required this.onCancel,
  });

  final bool windowOpen;
  final String countdown;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: windowOpen ? AppTint.success : AppTint.danger,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(
          color: windowOpen ? AppTint.successBorder : AppTint.dangerBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                windowOpen
                    ? Icons.timer_outlined
                    : Icons.lock_clock_outlined,
                size: 20,
                color: windowOpen ? AppTint.successText : AppTint.dangerText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  windowOpen
                      ? 'Free cancellation for $countdown'
                      : 'Cancellation window closed',
                  style: AppType.listTitle.copyWith(
                    fontSize: 15,
                    color:
                        windowOpen ? AppTint.successText : AppTint.dangerText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            windowOpen
                ? 'Cancel now and your advance is refunded in full.'
                : 'Contact support if you still need to change this booking.',
            style: AppType.small.copyWith(
              color: windowOpen ? AppTint.successText : AppTint.dangerText,
            ),
          ),
          const SizedBox(height: 14),
          UdButton(
            label: 'Cancel Ride',
            icon: Icons.close_rounded,
            variant: UdButtonVariant.danger,
            size: UdButtonSize.small,
            busy: busy,
            // Disabled once the window has closed, rather than faded out with
            // an Opacity wrapper — the disabled fill is the design's own way of
            // saying a control is unavailable, and it keeps the label legible.
            onPressed: windowOpen ? onCancel : null,
          ),
        ],
      ),
    );
  }
}

class _CancelReasonSheet extends StatelessWidget {
  const _CancelReasonSheet();

  static const _reasons = [
    'Driver delayed',
    'Change of plans',
    'Found another ride',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    // The sheet's shape, handle and padding come from showUdSheet.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Why are you cancelling?',
          style: AppType.h2.copyWith(color: AppText.primary),
        ),
        const SizedBox(height: 16),
        UdListGroup(
          children: [
            for (final reason in _reasons)
              UdListRow(
                title: reason,
                showChevron: true,
                onTap: () => Navigator.pop(context, reason),
              ),
          ],
        ),
      ],
    );
  }
}
