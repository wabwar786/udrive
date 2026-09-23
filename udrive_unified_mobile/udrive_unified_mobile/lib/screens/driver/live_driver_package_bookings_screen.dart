import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';

class LiveDriverPackageBookingsScreen extends StatefulWidget {
  const LiveDriverPackageBookingsScreen({super.key});

  @override
  State<LiveDriverPackageBookingsScreen> createState() =>
      _LiveDriverPackageBookingsScreenState();
}

class _LiveDriverPackageBookingsScreenState
    extends State<LiveDriverPackageBookingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() =>
      AppControllerScope.of(context).loadDriverMarketplace();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final bookings = controller.liveDriverPackageBookings;
    final waitlist = controller.liveDriverPackageWaitlist;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Row(
              children: [
                const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 38,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          context,
                          'Package passengers',
                          'پیکج مسافر',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(
                          context,
                          'Confirmed bookings, masked passenger manifests and waiting-list demand.',
                          'تصدیق شدہ بکنگ، محفوظ مسافر فہرست اور ویٹنگ لسٹ کی طلب۔',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: _t(
              context,
              'Confirmed package bookings',
              'تصدیق شدہ پیکج بکنگ',
            ),
          ),
          const SizedBox(height: 8),
          if (bookings.isEmpty)
            PremiumCard(
              child: Text(
                _t(
                  context,
                  'No confirmed package bookings yet.',
                  'ابھی کوئی تصدیق شدہ پیکج بکنگ نہیں۔',
                ),
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            ...bookings.map(
              (booking) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DriverPackageBookingCard(
                  booking: booking,
                ),
              ),
            ),
          const SizedBox(height: 20),
          SectionHeader(
            title: _t(context, 'Waiting-list demand', 'ویٹنگ لسٹ کی طلب'),
          ),
          const SizedBox(height: 8),
          if (waitlist.isEmpty)
            PremiumCard(
              child: Text(
                _t(
                  context,
                  'No customers are waiting for package availability.',
                  'کوئی کسٹمر پیکج کی دستیابی کا انتظار نہیں کر رہا۔',
                ),
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            ...waitlist.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DriverWaitlistCard(entry: entry),
              ),
            ),
        ],
      ),
    );
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _DriverPackageBookingCard extends StatelessWidget {
  const _DriverPackageBookingCard({required this.booking});

  final LiveBooking booking;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.bookingReference,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StatusPill(
                label: booking.status,
                color: _statusColor(booking.status),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '${booking.pickupLabel} → ${booking.destinationLabel}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 9),
          _Fact(
            Icons.calendar_month_rounded,
            DateFormat('dd MMM yyyy · hh:mm a').format(booking.pickupAt),
          ),
          _Fact(
            Icons.event_seat_rounded,
            '${booking.bookingType} · ${booking.seatsBooked} seat(s)',
          ),
          _Fact(
            Icons.groups_rounded,
            booking.partyType.isEmpty ? 'Tour passengers' : booking.partyType,
          ),
          const Divider(height: 25),
          Row(
            children: [
              Expanded(
                child: _Money(
                  label: 'Total',
                  value: booking.totalAmount,
                ),
              ),
              Expanded(
                child: _Money(
                  label: 'Advance',
                  value: booking.advanceAmount,
                ),
              ),
              Expanded(
                child: _Money(
                  label: 'Balance',
                  value: booking.remainingAmount,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: () => _showManifest(context),
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Open passenger manifest'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManifest(BuildContext context) async {
    try {
      final manifest = await AppControllerScope.of(context)
          .loadPassengerManifest(booking.id);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passenger manifest · ${manifest.bookingReference}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${manifest.passengers.length}/${manifest.seatsBooked} passenger profiles supplied',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                if (manifest.passengers.isEmpty)
                  const PremiumCard(
                    child: Text(
                      'Customer has not added passenger profiles yet.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                else
                  ...manifest.passengers.map(
                    (passenger) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: PremiumCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: .12),
                              child: Text(
                                passenger.fullName.isEmpty
                                    ? 'P'
                                    : passenger.fullName.characters.first,
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    passenger.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${passenger.ageGroup}${passenger.gender == null ? '' : ' · ${passenger.gender}'}${passenger.phoneNumberMasked == null ? '' : ' · ${passenger.phoneNumberMasked}'}',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (passenger.identityVerified)
                              const Icon(
                                Icons.verified_rounded,
                                color: AppColors.success,
                              ),
                            if (passenger.emergencyContact)
                              const Padding(
                                padding: EdgeInsets.only(left: 5),
                                child: Icon(
                                  Icons.emergency_rounded,
                                  color: AppColors.danger,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Color _statusColor(String status) {
    if (status == 'Cancelled') return AppColors.danger;
    if (status == 'Completed') return AppColors.success;
    return AppColors.primary;
  }
}

class _DriverWaitlistCard extends StatelessWidget {
  const _DriverWaitlistCard({required this.entry});

  final LivePackageWaitlist entry;

  @override
  Widget build(BuildContext context) => PremiumCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.packageTitle} · ${entry.bookingType} · ${entry.seatsRequested} seat(s)',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if (entry.notes?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.notes!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            StatusPill(label: entry.status, color: AppColors.warning),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Money extends StatelessWidget {
  const _Money({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final double value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'PKR ${NumberFormat('#,###').format(value)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      );
}
