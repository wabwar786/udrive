import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format/money.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import 'booking_payment_screen.dart';
import 'driver_offers_screen.dart';
import '../common/booking_chat_screen.dart';

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
      child: bookings.isEmpty && searches.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(22),
              children: [
                const SizedBox(height: 90),
                const Icon(
                  Icons.route_rounded,
                  size: 70,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  _t(
                    context,
                    'No live bookings yet',
                    'ابھی کوئی لائیو بکنگ نہیں',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    context,
                    'Book a verified Driver or reserve a tourism package. Your confirmed trips will appear here.',
                    'تصدیق شدہ ڈرائیور یا ٹورزم پیکج بک کریں۔ تصدیق شدہ سفر یہاں نظر آئیں گے۔',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
              // Open searches first: they are the only thing on this screen
              // that blocks the customer from booking anything else.
              itemCount: searches.length + bookings.length,
              itemBuilder: (_, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
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

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
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

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

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

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t(context, 'Looking for a driver', 'ڈرائیور تلاش کیا جا رہا ہے'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              StatusPill(
                label: waiting
                    ? _t(context, 'Searching', 'تلاش جاری')
                    : _t(context, '${request.offersCount} offers', '${request.offersCount} آفرز'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${request.pickupLabel} → ${request.destinationLabel}',
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            '${request.vehicleCategory} · PKR ${request.customerOffer.round()}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _resume(context),
                  child: Text(_t(context, 'Resume search', 'تلاش پر واپس جائیں')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _cancel(context),
                  child: Text(
                    _t(context, 'Cancel', 'منسوخ کریں'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              StatusPill(
                label: booking.status,
                color: booking.status == 'Cancelled'
                    ? AppColors.danger
                    : active
                        ? AppColors.primary
                        : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${booking.pickupLabel} → ${booking.destinationLabel}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          _Info(
            icon: Icons.calendar_month_rounded,
            value: DateFormat('dd MMM yyyy · hh:mm a')
                .format(booking.pickupAt),
          ),
          if (booking.returnAt != null)
            _Info(
              icon: Icons.keyboard_return_rounded,
              value:
                  'Return ${DateFormat('dd MMM yyyy · hh:mm a').format(booking.returnAt!)}',
            ),
          _Info(
            icon: Icons.event_seat_rounded,
            value:
                '${booking.bookingType} · ${booking.seatsBooked} seat(s)',
          ),
          if (booking.driverName != null)
            _Info(
              icon: Icons.verified_user_rounded,
              value:
                  '${booking.driverName} · ${booking.vehicle ?? ''}',
            ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Remaining',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      Money.amount(booking.remainingAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
              if (booking.tripOtp != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'OTP ${booking.tripOtp}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
          if (booking.remainingAmount > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingPaymentScreen(
                      bookingId: booking.id,
                      bookingReference: booking.bookingReference,
                    ),
                  ),
                ),
                icon: const Icon(Icons.payments_rounded),
                label: const Text('Pay balance'),
              ),
            ),
          ],
          if (active) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingChatScreen(
                      bookingId: booking.id,
                      bookingReference: booking.bookingReference,
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat with driver'),
              ),
            ),
          ],
          if (canChange) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reschedule(context),
                    icon: const Icon(Icons.event_repeat_rounded),
                    label: Text(
                      _t(context, 'Reschedule', 'تاریخ تبدیل کریں'),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    onPressed: () => _cancel(context),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(_t(context, 'Cancel', 'منسوخ کریں')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final controller = TextEditingController(
      text: 'Customer travel plan changed.',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t(context, 'Cancel booking?', 'بکنگ منسوخ کریں؟')),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: _t(context, 'Reason', 'وجہ'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t(context, 'Keep booking', 'بکنگ برقرار رکھیں')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t(context, 'Confirm cancel', 'منسوخی کی تصدیق')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await AppControllerScope.of(context).cancelLiveBooking(
        booking.id,
        controller.text.trim().isEmpty
            ? 'Customer cancelled the booking.'
            : controller.text.trim(),
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

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
