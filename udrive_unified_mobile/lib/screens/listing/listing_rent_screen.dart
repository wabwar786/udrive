import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/money.dart';
import '../../core/listings/listing_repository.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/vehicles/vehicle_usage_repository.dart';
import '../../core/widgets/ud_kit.dart';
import 'assign_driver_sheet.dart';
import 'listing_handover_screen.dart';
import 'listing_rent_calendar_screen.dart';
import 'listing_rent_settings_screen.dart';
import 'rent_tour_kit.dart';

/// R1 — one vehicle's rentals, as the owner runs them.
///
/// New requests first, with the clock running: the owner confirms or rejects
/// before the deadline, or the server rejects for them and refunds the
/// customer. Then what is confirmed (hand the car over), what is out (take it
/// back), what is next and what is finished.
class ListingRentScreen extends StatefulWidget {
  const ListingRentScreen({
    required this.vehicle,
    required this.drivers,
    super.key,
  });

  final ListingVehicle vehicle;
  final List<FleetDriver> drivers;

  @override
  State<ListingRentScreen> createState() => _ListingRentScreenState();
}

class _ListingRentScreenState extends State<ListingRentScreen> {
  RentalRepository? _repository;

  List<RentalBooking> _bookings = const [];
  bool _loading = true;
  String? _error;

  /// Booking ids with an answer on its way, so a double tap sends one.
  final Set<String> _working = {};

  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _expiryReloadQueued = false;

  late bool _rentOn = widget.vehicle.availableForRent;
  late double? _withDriver = widget.vehicle.withDriverDaily;
  late double? _selfDrive = widget.vehicle.selfDriveDaily;

  final TextEditingController _reason = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository = RentalRepository(AppControllerScope.of(context).apiClient);
      _load();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _reason.dispose();
    super.dispose();
  }

  bool _mine(RentalBooking b) {
    final v = widget.vehicle;
    if (b.vehicleId.isNotEmpty) return b.vehicleId == v.id;
    return b.registrationNumber.trim().isNotEmpty &&
        b.registrationNumber.trim().toLowerCase() ==
            v.registrationNumber.trim().toLowerCase();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await repository.ownerRentals();
      if (!mounted) return;
      setState(() {
        _bookings = all.where(_mine).toList(growable: false);
        _loading = false;
        _expiryReloadQueued = false;
      });
      _syncTicker();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// A one-second clock, only while something is waiting for an answer.
  void _syncTicker() {
    final waiting = _bookings.any((b) => b.isPendingOwner);
    if (!waiting) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final lapsed = _bookings.any((b) =>
          b.isPendingOwner &&
          b.ownerRespondBy != null &&
          !b.ownerRespondBy!.isAfter(_now));
      if (lapsed && !_expiryReloadQueued) {
        _expiryReloadQueued = true;
        // The server expires it; read back what it decided.
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted) _load();
        });
      }
    });
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _confirm(RentalBooking booking) async {
    final repository = _repository;
    if (repository == null || _working.contains(booking.id)) return;

    String? driverId;
    if (!booking.isSelfDrive) {
      final driver = await showAssignDriverSheet(
        context,
        drivers: widget.drivers,
        title: rentRange(booking.startDate, booking.endDate),
        subtitle: '${widget.vehicle.name} · with driver · '
            '${booking.counterpartName}',
      );
      if (driver == null || !mounted) return;
      driverId = driver.id;
    }

    setState(() {
      _working.add(booking.id);
      _error = null;
    });
    try {
      await repository.respond(booking.id,
          accept: true, fleetDriverId: driverId);
      if (!mounted) return;
      setState(() => _working.remove(booking.id));
      await _load();
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _working.remove(booking.id);
        _error = refusal.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working.remove(booking.id);
        _error = '$error';
      });
    }
  }

  Future<void> _reject(RentalBooking booking) async {
    final repository = _repository;
    if (repository == null || _working.contains(booking.id)) return;
    _reason.clear();

    final go = await showUdDialog<bool>(
      context: context,
      title: 'Reject this booking?',
      message: 'The customer is told at once and their advance of '
          '${Money.amount(booking.advanceAmount)} is refunded in full.',
      content: UdTextField(
        controller: _reason,
        label: 'Reason',
        labelSuffix: 'optional',
        hint: 'e.g. the car is in the workshop',
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        Builder(
          builder: (dialogContext) => UdButton.dark(
            label: 'Reject',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ),
        Builder(
          builder: (dialogContext) => UdButton.ghost(
            label: 'Keep it',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
        ),
      ],
    );
    if (go != true || !mounted) return;

    setState(() {
      _working.add(booking.id);
      _error = null;
    });
    try {
      await repository.respond(booking.id,
          accept: false, reason: _reason.text);
      if (!mounted) return;
      setState(() => _working.remove(booking.id));
      await _load();
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _working.remove(booking.id);
        _error = refusal.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working.remove(booking.id);
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

  Future<void> _openHandover(RentalBooking booking, String phase) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ListingHandoverScreen(booking: booking, phase: phase),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openCalendar() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ListingRentCalendarScreen(vehicle: widget.vehicle),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openSettings() async {
    final usage = await Navigator.push<VehicleUsage>(
      context,
      MaterialPageRoute(
        builder: (_) => ListingRentSettingsScreen(vehicle: widget.vehicle),
      ),
    );
    if (usage == null || !mounted) return;
    setState(() {
      _rentOn = usage.availableForRent;
      _withDriver = usage.rentWithDriverDaily;
      _selfDrive = usage.rentSelfDriveDaily;
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  String get _headerLine {
    final state = _rentOn ? 'live' : 'off';
    if ((_selfDrive ?? 0) > 0) {
      return 'Rent · $state · ${Money.amount(_selfDrive!)} self-drive / day';
    }
    if ((_withDriver ?? 0) > 0) {
      return 'Rent · $state · ${Money.amount(_withDriver!)} with driver / day';
    }
    return 'Rent · $state · no rate set';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final today = rentDayOnly(DateTime.now());
    final soon = today.add(const Duration(days: 2));

    final pending = _bookings.where((b) => b.isPendingOwner).toList()
      ..sort((a, b) => (a.ownerRespondBy ?? a.startDate)
          .compareTo(b.ownerRespondBy ?? b.startDate));
    final confirmed =
        _bookings.where((b) => b.status == 'Confirmed').toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final ready = confirmed
        .where((b) => !rentDayOnly(b.startDate).isAfter(soon))
        .toList();
    final next = confirmed
        .where((b) => rentDayOnly(b.startDate).isAfter(soon))
        .toList();
    final out = _bookings.where((b) => b.status == 'HandedOver').toList()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));
    final finished = _bookings
        .where((b) => !b.isLive)
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    final empty = pending.isEmpty &&
        confirmed.isEmpty &&
        out.isEmpty &&
        finished.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          RentNavyHeader(
            title: v.year > 0 ? '${v.name} ${v.year}' : v.name,
            subtitle: _headerLine,
            bottom: Row(
              children: [
                Expanded(
                  child: RentHeaderButton(
                    label: 'Calendar',
                    lime: true,
                    onTap: _openCalendar,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RentHeaderButton(
                    label: 'Rates & rules',
                    onTap: _openSettings,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _bookings.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.navy),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.navy,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: UdBanner(tone: UdTone.err, text: _error),
                          ),
                        if (empty && _error == null)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                            child: UdEmptyState(
                              icon: Icons.vpn_key_outlined,
                              title: 'No bookings yet',
                              text: 'When a customer books this car you get a '
                                  'WhatsApp and it shows here to confirm.',
                            ),
                          ),
                        if (pending.isNotEmpty) ...[
                          const RentSectionLabel('NEW — CONFIRM OR REJECT'),
                          for (final b in pending)
                            _PendingCard(
                              booking: b,
                              now: _now,
                              busy: _working.contains(b.id),
                              onReject: () => _reject(b),
                              onConfirm: () => _confirm(b),
                            ),
                        ],
                        if (ready.isNotEmpty) ...[
                          const RentSectionLabel('CONFIRMED'),
                          for (final b in ready)
                            _ConfirmedCard(
                              booking: b,
                              onCall: () => _call(b.counterpartPhone),
                              onHandOver: () => _openHandover(b, 'handover'),
                            ),
                        ],
                        if (out.isNotEmpty) ...[
                          const RentSectionLabel('OUT NOW'),
                          for (final b in out)
                            _OutRow(
                              booking: b,
                              onBack: () => _openHandover(b, 'return'),
                            ),
                        ],
                        if (next.isNotEmpty) ...[
                          const RentSectionLabel('NEXT'),
                          for (final b in next)
                            _CompactRow(
                              title: '${rentRange(b.startDate, b.endDate)} · '
                                  '${b.isSelfDrive ? 'self-drive' : 'with driver'}',
                              subtitle: [
                                b.counterpartName,
                                if (!b.isSelfDrive && b.driverName != null)
                                  'Driver: ${b.driverName}',
                                'advance paid',
                              ].where((s) => s.trim().isNotEmpty).join(' · '),
                              onCall: b.counterpartPhone == null
                                  ? null
                                  : () => _call(b.counterpartPhone),
                            ),
                        ],
                        if (finished.isNotEmpty) ...[
                          const RentSectionLabel('FINISHED'),
                          for (final b in finished.take(12))
                            _CompactRow(
                              title: rentRange(b.startDate, b.endDate),
                              subtitle: [
                                b.counterpartName,
                                b.statusLabel,
                              ].where((s) => s.trim().isNotEmpty).join(' · '),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "h:mm:ss" or "m:ss" until [deadline].
String _countdown(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  if (left.isNegative) return '0:00';
  final h = left.inHours;
  final m = left.inMinutes.remainder(60);
  final s = left.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.booking,
    required this.now,
    required this.busy,
    required this.onReject,
    required this.onConfirm,
  });

  final RentalBooking booking;
  final DateTime now;
  final bool busy;
  final VoidCallback onReject;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final deadline = b.ownerRespondBy;
    final lapsed = deadline != null && !deadline.isAfter(now);
    final details = [
      b.counterpartName,
      if (b.isSelfDrive && b.customerDocumentsVerified) 'documents verified',
      'advance ${Money.amount(b.advanceAmount)} held by UDrive',
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppTint.pendingBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              RentTag(
                deadline == null
                    ? 'Answer soon'
                    : lapsed
                        ? 'Time is up'
                        : 'Answer within ${_countdown(deadline, now)}',
                background: AppTint.pendingSurface,
                ink: AppTint.pending,
              ),
              RentTag(b.isSelfDrive ? 'Self-drive' : 'With driver'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${rentRange(b.startDate, b.endDate)} · ${b.days} '
            '${b.days == 1 ? 'day' : 'days'}',
            style: AppType.listTitle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            details,
            style: AppType.caption.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: AppTint.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.all(14),
                    side: const BorderSide(
                        color: AppTint.dangerBorder, width: 1.5),
                  ),
                  child: InkWell(
                    onTap: busy || lapsed ? null : onReject,
                    customBorder:
                        RoundedRectangleBorder(borderRadius: AppRadii.all(14)),
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      child: Text(
                        'Reject',
                        style: AppType.small.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTint.dangerText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: UdButton.primary(
                  label: 'Confirm',
                  busy: busy,
                  onPressed: lapsed ? null : onConfirm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No answer in time = rejected automatically and the advance is '
            'refunded.',
            style: AppType.caption.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppText.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedCard extends StatelessWidget {
  const _ConfirmedCard({
    required this.booking,
    required this.onCall,
    required this.onHandOver,
  });

  final RentalBooking booking;
  final VoidCallback onCall;
  final VoidCallback onHandOver;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final who = [
      b.counterpartName,
      if (b.counterpartPhone != null) b.counterpartPhone!,
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.limeLine, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              const RentTag(
                'Confirmed · advance paid',
                background: AppColors.brandWash,
                ink: AppColors.brandInk,
              ),
              RentTag(b.isSelfDrive ? 'Self-drive' : 'With driver'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${rentRange(b.startDate, b.endDate)} · ${b.days} '
            '${b.days == 1 ? 'day' : 'days'}',
            style: AppType.listTitle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            who,
            style: AppType.caption.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppText.secondary,
            ),
          ),
          if (!b.isSelfDrive && b.driverName != null) ...[
            const SizedBox(height: 2),
            Text(
              'Driver: ${b.driverName}',
              style: AppType.caption.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppText.secondary,
              ),
            ),
          ],
          if (b.isSelfDrive && b.customerDocumentsVerified) ...[
            const SizedBox(height: 8),
            const Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                RentTag('CNIC verified',
                    background: AppColors.brandWash, ink: AppColors.brandInk),
                RentTag('Licence verified',
                    background: AppColors.brandWash, ink: AppColors.brandInk),
                RentTag('Selfie on file',
                    background: AppColors.brandWash, ink: AppColors.brandInk),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Total ${Money.amount(b.subtotal)} · advance '
            '${Money.amount(b.advanceAmount)}'
            '${b.securityDeposit > 0 ? ' · deposit ${Money.amount(b.securityDeposit)} at pickup' : ''}',
            style: AppType.small.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: UdButton.outline(
                  label: 'Call customer',
                  size: UdButtonSize.small,
                  onPressed: b.counterpartPhone == null ? null : onCall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: UdButton.dark(
                  label: 'Hand over',
                  trailingIcon: Icons.chevron_right_rounded,
                  size: UdButtonSize.small,
                  onPressed: onHandOver,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutRow extends StatelessWidget {
  const _OutRow({required this.booking, required this.onBack});

  final RentalBooking booking;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final today = rentDayOnly(DateTime.now());
    final end = rentDayOnly(b.endDate);
    final when = end == today
        ? 'Returns today'
        : end.isBefore(today)
            ? 'Was due back ${rentRange(end, end)}'
            : 'Returns ${rentRange(end, end)}';
    final sub = [
      b.counterpartName,
      if (!b.isSelfDrive && b.driverName != null)
        'with driver: ${b.driverName}',
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when,
                  style: AppType.listTitle.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: end.isBefore(today)
                        ? AppTint.dangerText
                        : AppText.primary,
                  ),
                ),
                Text(
                  sub,
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          UdButton.primary(
            label: 'Car back',
            size: UdButtonSize.small,
            expand: false,
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.title,
    required this.subtitle,
    this.onCall,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.listTitle.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (onCall != null)
            UdIconButton(
              icon: Icons.call_rounded,
              tooltip: 'Call customer',
              onPressed: onCall,
            ),
        ],
      ),
    );
  }
}
