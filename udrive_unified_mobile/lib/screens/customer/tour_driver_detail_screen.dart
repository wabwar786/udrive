import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/booking/booking_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/booking_models.dart';
import '../common/booking_chat_screen.dart';

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
        builder: (_) => BookingChatScreen(
          bookingId: widget.booking.id,
          bookingReference: widget.booking.bookingReference,
        ),
      ),
    );
  }

  Future<void> _openCancelSheet() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
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
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
                                  size: 15, color: Color(0xFFF5B942)),
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
                                fontSize: 11,
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
                        fontSize: 12, color: AppText.secondary),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _call,
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: const Text('Call'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _chat,
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 18),
                        label: const Text('Chat'),
                      ),
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
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.floating,
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        size: 19, color: AppColors.navy),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .04,
          color: AppText.secondary,
        ),
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
                  fontSize: 12, color: AppText.secondary),
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
        color: windowOpen ? Colors.white : AppTint.danger,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(
          color: windowOpen ? AppColors.border : AppColors.danger,
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
                size: 17,
                color: windowOpen ? AppText.secondary : AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  windowOpen
                      ? 'Free cancellation for $countdown'
                      : 'Cancellation window closed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: windowOpen ? AppText.primary : AppColors.danger,
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
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: windowOpen ? 1 : .45,
            child: SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: windowOpen && !busy ? onCancel : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cancel Ride'),
              ),
            ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
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
              'Why are you cancelling?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 12),
            ..._reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => Navigator.pop(context, reason),
                  borderRadius: AppRadii.all(AppRadii.field),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTint.surface,
                      borderRadius: AppRadii.all(AppRadii.field),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            reason,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppText.disabled),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
