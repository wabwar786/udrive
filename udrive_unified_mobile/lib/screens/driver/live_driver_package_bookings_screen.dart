import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';

/// D-33 — confirmed package bookings, their passenger manifests, and the
/// waiting list.
///
/// Not a page of its own: this is the second segment of [TourOperationsScreen],
/// which is why it has no bar and no `Scaffold`.
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
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 0, AppSizes.sidePadding, 40),
        children: [
          Text(
            _t(context, 'Package passengers', 'پیکج مسافر'),
            style: AppType.h2.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              context,
              'Confirmed bookings, masked passenger manifests and '
                  'waiting-list demand.',
              'تصدیق شدہ بکنگ، محفوظ مسافر فہرست اور ویٹنگ لسٹ کی طلب۔',
            ),
            style: AppType.small.copyWith(height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 22),

          UdSectionHeader(
            title: _t(context, 'Confirmed package bookings',
                'تصدیق شدہ پیکج بکنگ'),
            caption: bookings.isEmpty ? null : '${bookings.length}',
          ),
          const SizedBox(height: 12),
          if (bookings.isEmpty)
            UdEmptyState(
              icon: Icons.confirmation_number_outlined,
              title: _t(context, 'No confirmed bookings yet',
                  'ابھی کوئی تصدیق شدہ بکنگ نہیں'),
              text: _t(
                  context,
                  'Bookings on your approved packages appear here.',
                  'آپ کے منظور شدہ پیکجز کی بکنگ یہاں آئے گی۔'),
            )
          else
            ...bookings.map(
              (booking) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DriverPackageBookingCard(booking: booking),
              ),
            ),

          const SizedBox(height: 26),
          UdSectionHeader(
            title: _t(context, 'Waiting-list demand', 'ویٹنگ لسٹ کی طلب'),
            caption: waitlist.isEmpty ? null : '${waitlist.length}',
          ),
          const SizedBox(height: 12),
          if (waitlist.isEmpty)
            UdEmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: _t(context, 'Nobody waiting', 'کوئی انتظار میں نہیں'),
              text: _t(
                  context,
                  'Customers who want a seat that is not free yet appear here.',
                  'جو کسٹمر خالی نشست کا انتظار کر رہے ہوں وہ یہاں آئیں گے۔'),
            )
          else
            ...waitlist.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
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

/// One confirmed booking: who, when, and what is still owed.
class _DriverPackageBookingCard extends StatelessWidget {
  const _DriverPackageBookingCard({required this.booking});

  final LiveBooking booking;

  static UdTone _tone(String status) => switch (status) {
        'Cancelled' => UdTone.err,
        'Completed' => UdTone.ok,
        'Confirmed' => UdTone.lime,
        _ => UdTone.info,
      };

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,###');

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.bookingReference,
                  style: AppType.overline.copyWith(color: AppColors.brandInk),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(label: booking.status, tone: _tone(booking.status)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${booking.pickupLabel} → ${booking.destinationLabel}',
            style: AppType.h3.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 12),
          _Fact(
            Icons.calendar_month_rounded,
            DateFormat('d MMM yyyy · hh:mm a').format(booking.pickupAt),
          ),
          _Fact(
            Icons.event_seat_rounded,
            '${booking.bookingType} · ${booking.seatsBooked} seat(s)',
          ),
          _Fact(
            Icons.groups_rounded,
            booking.partyType.isEmpty ? 'Tour passengers' : booking.partyType,
          ),
          const SizedBox(height: 14),

          // Total, advance and balance as key/value rows rather than three
          // columns of 10pt labels. Balance is the one a Driver is looking
          // for, so it is the last line and it is bold.
          UdKeyValue(
            label: 'Total',
            value: 'PKR ${money.format(booking.totalAmount)}',
          ),
          UdKeyValue(
            label: 'Advance',
            value: 'PKR ${money.format(booking.advanceAmount)}',
          ),
          UdKeyValue(
            label: 'Balance',
            value: 'PKR ${money.format(booking.remainingAmount)}',
            total: true,
          ),

          const SizedBox(height: 16),
          UdButton.outline(
            label: 'Open passenger manifest',
            icon: Icons.badge_outlined,
            size: UdButtonSize.small,
            onPressed: () => _showManifest(context),
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
      await showUdSheet<void>(
        context: context,
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                'Passenger manifest',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 4),
              Text(
                '${manifest.bookingReference} · '
                '${manifest.passengers.length}/${manifest.seatsBooked} '
                'profiles supplied',
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 16),
              if (manifest.passengers.isEmpty)
                const UdEmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'No profiles yet',
                  text: 'The customer has not added passenger profiles.',
                )
              else
                UdListGroup(
                  children: [
                    for (final passenger in manifest.passengers)
                      UdListRow(
                        title: passenger.fullName,
                        subtitle: [
                          passenger.ageGroup,
                          if (passenger.gender != null) passenger.gender!,
                          if (passenger.phoneNumberMasked != null)
                            passenger.phoneNumberMasked!,
                        ].join(' · '),
                        leading: UdAvatar(
                          initials: passenger.fullName.isEmpty
                              ? 'P'
                              : passenger.fullName.characters.first
                                  .toUpperCase(),
                          size: 44,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (passenger.identityVerified)
                              const Icon(Icons.verified_rounded,
                                  size: 22, color: AppTint.successText),
                            if (passenger.emergencyContact)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.emergency_rounded,
                                    size: 22, color: AppTint.dangerText),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
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
}

/// Somebody who wants a seat that is not free yet.
class _DriverWaitlistCard extends StatelessWidget {
  const _DriverWaitlistCard({required this.entry});

  final LivePackageWaitlist entry;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const UdIconTile(
              icon: Icons.hourglass_top_rounded,
              tone: UdIconTone.warn,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.customerName,
                    style: AppType.listTitle
                        .copyWith(fontSize: 16, color: AppText.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.packageTitle} · ${entry.bookingType} · '
                    '${entry.seatsRequested} seat(s)',
                    style:
                        AppType.small.copyWith(color: AppText.secondary),
                  ),
                  if (entry.notes?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.notes!,
                      style: AppType.small.copyWith(
                        height: 1.45,
                        color: AppText.caption,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            UdBadge(label: entry.status, tone: UdTone.warn),
          ],
        ),
      );
}

/// An icon and a fact, one per line under a booking's route.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppText.caption),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppText.secondary,
                ),
              ),
            ),
          ],
        ),
      );
}
