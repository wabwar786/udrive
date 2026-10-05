import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/money.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// C-36 — right after paying the advance: waiting for the owner to confirm.
///
/// The owner has a fixed time to answer. The clock runs here, the booking is
/// re-read every 20 seconds, and the screen turns into the answer: the
/// owner's number once confirmed, or "advance refunded" if the owner said no
/// or let the time run out.
///
/// Pops `true` from "Find other cars" so a caller that is not the rental list
/// can step back to it.
class RentalWaitingScreen extends StatefulWidget {
  const RentalWaitingScreen({required this.booking, super.key});

  final RentalBooking booking;

  @override
  State<RentalWaitingScreen> createState() => _RentalWaitingScreenState();
}

class _RentalWaitingScreenState extends State<RentalWaitingScreen> {
  RentalRepository? _repository;

  late RentalBooking _booking = widget.booking;

  Timer? _clock;
  Timer? _poll;
  DateTime _now = DateTime.now();
  bool _cancelling = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository = RentalRepository(AppControllerScope.of(context).apiClient);
      _startTimers();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _startTimers() {
    if (!_booking.isPendingOwner) return;
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _poll ??= Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  void _stopTimers() {
    _clock?.cancel();
    _clock = null;
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final all = await repository.myBookings();
      if (!mounted) return;
      RentalBooking? found;
      for (final b in all) {
        if (b.id == _booking.id) found = b;
      }
      if (found == null) return;
      setState(() {
        _booking = found!;
        _error = null;
      });
      if (!_booking.isPendingOwner) _stopTimers();
    } catch (_) {
      // A missed poll is not worth a message; the next one tries again.
    }
  }

  Future<void> _cancel() async {
    final repository = _repository;
    if (repository == null || _cancelling) return;

    final go = await showUdDialog<bool>(
      context: context,
      title: 'Cancel this booking?',
      message: 'The owner hasn\'t answered yet, so your advance of '
          '${Money.amount(_booking.advanceAmount)} is refunded in full.',
      actions: [
        Builder(
          builder: (dialogContext) => UdButton.dark(
            label: 'Yes, cancel',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ),
        Builder(
          builder: (dialogContext) => UdButton.ghost(
            label: 'Keep waiting',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
        ),
      ],
    );
    if (go != true || !mounted) return;

    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      final updated = await repository.cancel(_booking.id);
      if (!mounted) return;
      _stopTimers();
      setState(() {
        _booking = updated;
        _cancelling = false;
      });
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _error = refusal.message;
      });
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _error = '$error';
      });
    }
  }

  Future<void> _call(String? phone) async {
    final number = (phone ?? '').trim();
    if (number.isEmpty) return;
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer.')),
      );
    }
  }

  void _findOther() => Navigator.pop(context, true);

  static String _range(DateTime start, DateTime end) {
    final same = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (same) return DateFormat('EEE d MMM').format(start);
    final sameMonth = start.month == end.month && start.year == end.year;
    return '${DateFormat(sameMonth ? 'EEE d' : 'EEE d MMM').format(start)} – '
        '${DateFormat('EEE d MMM').format(end)}';
  }

  String get _countdown {
    final deadline = _booking.ownerRespondBy;
    if (deadline == null) return '—';
    final left = deadline.difference(_now);
    if (left.isNegative) return '0:00';
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    final s = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final pending = b.isPendingOwner;
    final confirmed = b.status == 'Confirmed' || b.status == 'HandedOver';
    final refunded = b.isRefusedByOwner || b.status == 'Cancelled';
    final lapsed = pending &&
        b.ownerRespondBy != null &&
        !b.ownerRespondBy!.isAfter(_now);

    final title = pending
        ? 'Waiting for the owner'
        : confirmed
            ? 'Confirmed — owner\'s number'
            : b.status == 'Declined'
                ? 'The owner said no'
                : b.status == 'Expired'
                    ? 'The owner didn\'t answer in time'
                    : b.status == 'Cancelled'
                        ? 'Booking cancelled'
                        : b.statusLabel;

    final summary = '${b.vehicleName} · ${_range(b.startDate, b.endDate)} · '
        '${b.isSelfDrive ? 'self-drive' : 'with driver'}.';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(onBack: () => Navigator.maybePop(context)),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 8, AppSizes.sidePadding, 24),
                children: [
                  if (pending)
                    Text(
                      'RIGHT AFTER PAYING THE ADVANCE',
                      style: AppType.caption.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4,
                        color: AppText.secondary,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: AppType.h1.copyWith(color: AppText.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pending
                        ? '$summary The owner has been told on WhatsApp.'
                        : summary,
                    style: AppType.body2.copyWith(color: AppText.secondary),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    UdBanner(tone: UdTone.err, text: _error),
                    const SizedBox(height: 14),
                  ],
                  if (pending) _clockCard(lapsed),
                  if (confirmed) _confirmedCard(),
                  if (refunded)
                    UdBanner(
                      tone: UdTone.ok,
                      icon: Icons.check_circle_outline_rounded,
                      text: 'Advance refunded — '
                          '${Money.amount(b.advanceAmount)} goes back to you '
                          'in full.',
                    ),
                  if (!pending && !confirmed && !refunded)
                    UdBanner(tone: UdTone.gray, text: b.statusLabel),
                  const SizedBox(height: 22),
                  _Progress(
                    done: [
                      true,
                      confirmed || b.status == 'Returned',
                      b.status == 'HandedOver' || b.status == 'Returned',
                    ],
                    failed: refunded,
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: pending
                  ? Row(
                      children: [
                        Expanded(
                          child: UdButton.outline(
                            label: 'Cancel',
                            busy: _cancelling,
                            onPressed: _cancel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: UdButton.soft(
                            label: 'Find other cars',
                            onPressed: _findOther,
                          ),
                        ),
                      ],
                    )
                  : confirmed
                      ? UdButton.primary(
                          label: 'Done',
                          onPressed: () => Navigator.maybePop(context),
                        )
                      : UdButton.primary(
                          label: 'Find other cars',
                          onPressed: _findOther,
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clockCard(bool lapsed) {
    final b = _booking;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lapsed ? 'Checking…' : _countdown,
            textAlign: TextAlign.center,
            style: AppType.display.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'If the owner says no or doesn\'t answer in time, '
                      'your advance ',
                ),
                TextSpan(
                  text: Money.amount(b.advanceAmount),
                  style: AppType.body2.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const TextSpan(text: ' is refunded in full.'),
              ],
            ),
            textAlign: TextAlign.center,
            style: AppType.body2.copyWith(color: AppText.secondary),
          ),
        ],
      ),
    );
  }

  Widget _confirmedCard() {
    final b = _booking;
    final ownerPhone = b.counterpartPhone;
    final driverPhone = b.driverPhone;
    return UdListGroup(
      children: [
        UdListRow(
          title: b.counterpartName.isEmpty ? 'Owner' : b.counterpartName,
          subtitle: ownerPhone ?? 'Owner',
          leading: const UdIconTile(
            icon: Icons.person_outline_rounded,
            tone: UdIconTone.neutral,
          ),
          trailing: ownerPhone == null
              ? null
              : UdIconButton(
                  icon: Icons.call_rounded,
                  tooltip: 'Call the owner',
                  onPressed: () => _call(ownerPhone),
                ),
        ),
        if (!b.isSelfDrive && b.driverName != null)
          UdListRow(
            title: b.driverName!,
            subtitle: driverPhone ?? 'Your driver',
            leading: const UdIconTile(
              icon: Icons.airline_seat_recline_normal_rounded,
              tone: UdIconTone.neutral,
            ),
            trailing: driverPhone == null
                ? null
                : UdIconButton(
                    icon: Icons.call_rounded,
                    tooltip: 'Call the driver',
                    onPressed: () => _call(driverPhone),
                  ),
          ),
        if (b.pickupPoint != null)
          UdListRow(
            title: b.pickupPoint!,
            subtitle: 'Collect from',
            leading: const UdIconTile(
              icon: Icons.place_outlined,
              tone: UdIconTone.neutral,
            ),
          ),
        UdListRow(
          title: '${Money.amount(b.balanceDue)} on collection',
          subtitle: b.securityDeposit > 0
              ? 'Plus ${Money.amount(b.securityDeposit)} refundable deposit, '
                  'in cash to the owner.'
              : 'In cash to the owner.',
        ),
      ],
    );
  }
}

/// Booking sent → owner confirms → pick up the car.
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.failed});

  final List<bool> done;
  final bool failed;

  static const _steps = [
    'Booking sent, advance paid',
    'Owner confirms',
    'Pick up the car · owner\'s number shown here',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done[i]
                        ? AppColors.brand
                        : (failed && i == 1)
                            ? AppTint.danger
                            : AppColors.surfaceAlt,
                  ),
                  child: done[i]
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: AppColors.navy)
                      : (failed && i == 1)
                          ? const Icon(Icons.close_rounded,
                              size: 16, color: AppTint.dangerText)
                          : Text(
                              '${i + 1}',
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppText.secondary,
                              ),
                            ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _steps[i],
                    style: AppType.body2.copyWith(
                      fontWeight: done[i] ? FontWeight.w800 : FontWeight.w600,
                      color: done[i] ? AppText.primary : AppText.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
