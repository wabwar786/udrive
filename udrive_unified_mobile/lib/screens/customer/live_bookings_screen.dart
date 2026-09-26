import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format/money.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import 'booking_payment_screen.dart';
import 'driver_offers_screen.dart';
import '../common/booking_chat_screen.dart';

String _t(BuildContext context, String en, String ur) =>
    AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

/// C-51 — My trips.
///
/// Open searches and bookings in one continuous list. There is no tab or
/// filter here, in the code or in the design: a customer with an open search
/// cannot book anything else, so hiding it behind a tab would hide the one
/// thing blocking them.
class LiveBookingsScreen extends StatefulWidget {
  const LiveBookingsScreen({super.key});

  @override
  State<LiveBookingsScreen> createState() => _LiveBookingsScreenState();
}

class _LiveBookingsScreenState extends State<LiveBookingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// Loads bookings AND open ride requests.
  ///
  /// Was refreshLiveBookings, which fetched only bookings. A search that has
  /// not yet produced a booking is a ride request, so it was invisible here —
  /// and this screen is the only place a customer could reasonably look for it.
  Future<void> _refresh() async {
    // Guarded: every caller reaches this after an await, and two of them after
    // a pushed screen has been on top for a while. Reading an InheritedWidget
    // from a defunct element throws.
    if (!mounted) return;
    await AppControllerScope.of(context).refreshCustomerRideState();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final bookings = controller.liveBookings;
    final searches = controller.openRideRequests;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: bookings.isEmpty && searches.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 60, AppSizes.sidePadding, 34),
              children: [
                UdEmptyState(
                  icon: Icons.route_rounded,
                  title: _t(context, 'No live bookings yet',
                      'ابھی کوئی لائیو بکنگ نہیں'),
                  text: _t(
                    context,
                    'Book a verified Driver or reserve a tourism package. Your '
                        'confirmed trips will appear here.',
                    'تصدیق شدہ ڈرائیور یا ٹورزم پیکج بک کریں۔ تصدیق شدہ سفر یہاں نظر آئیں گے۔',
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 6, AppSizes.sidePadding, 90),
              // Open searches first: they are the only thing on this screen
              // that blocks the customer from booking anything else.
              itemCount: searches.length + bookings.length,
              itemBuilder: (_, index) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: index < searches.length
                    ? _OpenSearchCard(
                        request: searches[index],
                        onChanged: _refresh,
                      )
                    : _BookingCard(
                        booking: bookings[index - searches.length],
                        onChanged: _refresh,
                      ),
              ),
            ),
    );
  }
}

/// A ride request that is still looking for a driver.
///
/// Two actions, and both must always be available: return to the search, or
/// end it. The server refuses a second booking while one of these is open, so
/// a customer with no way to reach this card has no way to book at all.
class _OpenSearchCard extends StatelessWidget {
  const _OpenSearchCard({
    required this.request,
    required this.onChanged,
  });

  final LiveRideRequest request;
  final Future<void> Function() onChanged;

  Future<void> _resume(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverOffersScreen(
          rideRequestId: request.id,
          pickup: request.pickupLabel,
          destination: request.destinationLabel,
          customerOffer: request.customerOffer.round(),
          vehicleName: request.vehicleCategory,
          pickupPoint: LatLng(request.pickupLatitude, request.pickupLongitude),
          destinationPoint:
              LatLng(request.destinationLatitude, request.destinationLongitude),
        ),
      ),
    );
    await onChanged();
  }

  Future<void> _cancel(BuildContext context) async {
    final controller = AppControllerScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failedMessage = _t(
      context,
      'Could not cancel the search. Please try again.',
      'تلاش منسوخ نہیں ہو سکی۔ دوبارہ کوشش کریں۔',
    );

    final cancelled = await controller.cancelLiveRideRequest(request.id);
    await onChanged();

    // Unlike the search screen, this button reports failure. There the
    // customer is leaving anyway and the request expires on its own; here they
    // are cancelling precisely so they can book again, and a silent failure
    // would send them back to the same refusal.
    if (!cancelled) {
      messenger.showSnackBar(SnackBar(content: Text(failedMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = request.offersCount == 0;

    return UdCard(
      tone: UdCardTone.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _t(context, 'Looking for a driver',
                      'ڈرائیور تلاش کیا جا رہا ہے'),
                  style: AppType.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandInk,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(
                label: waiting
                    ? _t(context, 'Searching', 'تلاش جاری')
                    : _t(context, '${request.offersCount} offers',
                        '${request.offersCount} آفرز'),
                tone: waiting ? UdTone.warn : UdTone.info,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${request.pickupLabel} → ${request.destinationLabel}',
            style: AppType.listTitle.copyWith(
              fontSize: 16,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${request.vehicleCategory} · PKR ${request.customerOffer.round()}',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 16),
          UdButtonRow(
            children: [
              UdButton.dark(
                label: _t(context, 'Resume search', 'تلاش پر واپس جائیں'),
                size: UdButtonSize.small,
                onPressed: () => _resume(context),
              ),
              UdButton(
                label: _t(context, 'Cancel', 'منسوخ کریں'),
                variant: UdButtonVariant.danger,
                size: UdButtonSize.small,
                onPressed: () => _cancel(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One booking, with whatever its status allows the customer to do.
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onChanged,
  });

  final LiveBooking booking;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final active = ![
      'Completed',
      'Cancelled',
      'NoShow',
      'Disputed',
    ].contains(booking.status);
    // 'DriverAccepted' is what the API actually writes when a customer picks an
    // offer (BookingService.SelectDriverOffer). It was missing here, so every
    // marketplace booking showed neither Cancel nor Reschedule even though the
    // server accepts both for that status — the customer's only remaining exit
    // was to wait for the trip to expire.
    final canChange = [
      'DriverSelected',
      'DriverAccepted',
      'Confirmed',
      'Scheduled',
    ].contains(booking.status);

    return UdCard(
      tone: active ? UdCardTone.raised : UdCardTone.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  booking.bookingReference,
                  style: AppType.listTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppText.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // The raw status string, exactly as the API returns it.
              UdBadge(
                label: booking.status,
                tone: booking.status == 'Cancelled'
                    ? UdTone.err
                    : active
                        ? UdTone.lime
                        : UdTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${booking.pickupLabel} → ${booking.destinationLabel}',
            style: AppType.h3.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 10),
          _Info(
            icon: Icons.calendar_month_rounded,
            value: DateFormat('dd MMM yyyy · hh:mm a').format(booking.pickupAt),
          ),
          if (booking.returnAt != null)
            _Info(
              icon: Icons.keyboard_return_rounded,
              value: 'Return '
                  '${DateFormat('dd MMM yyyy · hh:mm a').format(booking.returnAt!)}',
            ),
          _Info(
            icon: Icons.event_seat_rounded,
            value: '${booking.bookingType} · ${booking.seatsBooked} seat(s)',
          ),
          if (booking.driverName != null)
            _Info(
              icon: Icons.verified_user_rounded,
              value: '${booking.driverName} · ${booking.vehicle ?? ''}',
            ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Remaining',
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Money.amount(booking.remainingAmount),
                      style: AppType.priceMd.copyWith(
                        fontSize: 19,
                        color: booking.remainingAmount > 0
                            ? AppText.primary
                            : AppColors.brandInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (booking.tripOtp != null) ...[
                const SizedBox(width: 10),
                // A navy pill: this is the number the driver asks for at the
                // kerb, so it has to be the thing on the card that reads first.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: AppRadii.all(AppRadii.row),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'OTP',
                        style: AppType.overline
                            .copyWith(color: AppText.onInkMuted),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${booking.tripOtp}',
                        style: AppType.listTitle.copyWith(
                          fontSize: 17,
                          letterSpacing: 2,
                          color: AppColors.brand,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          // Only when something is still owed — unchanged.
          if (booking.remainingAmount > 0) ...[
            const SizedBox(height: 16),
            UdButton.primary(
              label: 'Pay balance',
              icon: Icons.payments_rounded,
              size: UdButtonSize.small,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookingPaymentScreen(
                    bookingId: booking.id,
                    bookingReference: booking.bookingReference,
                  ),
                ),
              ),
            ),
          ],
          // Only while the trip is still live — unchanged.
          if (active) ...[
            const SizedBox(height: 10),
            UdButton.outline(
              label: 'Chat with driver',
              icon: Icons.chat_bubble_outline_rounded,
              size: UdButtonSize.small,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookingChatScreen(
                    bookingId: booking.id,
                    bookingReference: booking.bookingReference,
                  ),
                ),
              ),
            ),
          ],
          // Only for the four statuses the server accepts a change on.
          if (canChange) ...[
            const SizedBox(height: 10),
            UdButtonRow(
              children: [
                UdButton.outline(
                  label: _t(context, 'Reschedule', 'تاریخ تبدیل کریں'),
                  icon: Icons.event_repeat_rounded,
                  size: UdButtonSize.small,
                  onPressed: () => _reschedule(context),
                ),
                UdButton(
                  label: _t(context, 'Cancel', 'منسوخ کریں'),
                  variant: UdButtonVariant.danger,
                  size: UdButtonSize.small,
                  onPressed: () => _cancel(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final reason = TextEditingController(
      text: 'Customer travel plan changed.',
    );
    final confirmed = await showUdDialog<bool>(
      context: context,
      title: _t(context, 'Cancel booking?', 'بکنگ منسوخ کریں؟'),
      message: _t(
        context,
        'Tell the driver why, so the trip is closed with a reason on record.',
        'ڈرائیور کو وجہ بتائیں تاکہ سفر وجہ کے ساتھ بند ہو۔',
      ),
      content: UdTextField(
        controller: reason,
        label: _t(context, 'Reason', 'وجہ'),
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        UdButton(
          label: _t(context, 'Confirm cancel', 'منسوخی کی تصدیق'),
          variant: UdButtonVariant.dangerSolid,
          onPressed: () => Navigator.pop(context, true),
        ),
        UdButton.ghost(
          label: _t(context, 'Keep booking', 'بکنگ برقرار رکھیں'),
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await AppControllerScope.of(context).cancelLiveBooking(
        booking.id,
        reason.text.trim().isEmpty
            ? 'Customer cancelled the booking.'
            : reason.text.trim(),
      );
      await onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final initialDate = booking.pickupAt.isAfter(DateTime.now())
        ? booking.pickupAt
        : DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !context.mounted) return;

    final pickupAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    try {
      await AppControllerScope.of(context).rescheduleLiveBooking(
        bookingId: booking.id,
        pickupAt: pickupAt,
        reason: 'Customer requested a new departure time.',
      );
      await onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                context,
                'Booking rescheduled successfully.',
                'بکنگ کی نئی تاریخ کامیابی سے محفوظ ہو گئی۔',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }
}

/// An icon and one line of booking detail.
class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppText.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppText.primary,
                ),
              ),
            ),
          ],
        ),
      );
}
