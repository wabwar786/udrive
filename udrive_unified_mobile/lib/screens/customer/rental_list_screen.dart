import 'package:flutter/material.dart';

import '../../core/network/api_config.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'rental_booking_screen.dart';

/// C-30 — the cars on offer, with the owner's own photograph of each.
///
/// The picture is the point. A rental list of names and prices tells a Customer
/// nothing they can judge: they are about to hand over a deposit and drive away
/// in one specific car, and a model name is not that car. The one picture this
/// platform could otherwise have shown is the admin's category photograph — a
/// different vehicle, in a different colour, in better condition — which is an
/// advertisement rather than information. So a vehicle with no photograph is not
/// listed at all, and the server enforces that rather than this screen.
class RentalListScreen extends StatefulWidget {
  const RentalListScreen({super.key});

  @override
  State<RentalListScreen> createState() => _RentalListScreenState();
}

class _RentalListScreenState extends State<RentalListScreen> {
  late final RentalRepository _repository =
      RentalRepository(AppControllerScope.of(context).apiClient);

  int _tab = 0;
  List<RentalVehicle> _vehicles = const [];
  List<RentalBooking> _bookings = const [];
  DateTimeRange? _dates;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = await _repository.search(
        from: _dates?.start,
        to: _dates?.end,
      );
      final bookings = await _repository.myBookings();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _bookings = bookings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
      initialDateRange: _dates,
      helpText: _t('When do you need the car?', 'گاڑی کب چاہیے؟'),
    );
    if (picked == null || !mounted) return;
    setState(() => _dates = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('Car rental', 'کرائے پر گاڑی'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: Column(
        children: [
          const SizedBox(height: 6),
          UdTabs(
            tabs: [
              _t('Browse', 'دیکھیں'),
              _t('My rentals', 'میری بکنگ'),
            ],
            index: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.navy,
                    child: _tab == 0 ? _browse() : _mine(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _browse() => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 4, AppSizes.sidePadding, 40),
        children: [
          if (_error != null) ...[
            UdBanner(tone: UdTone.err, text: _error),
            const SizedBox(height: 12),
          ],

          // The dates sit above the list rather than inside each car, because
          // they change what the list *is*: a car taken that week should not be
          // on screen at all, and finding that out at the last step is the
          // worst version of this flow.
          UdListGroup(
            children: [
              UdListRow(
                title: _dates == null
                    ? _t('Any dates', 'کوئی بھی تاریخ')
                    : '${_day(_dates!.start)} — ${_day(_dates!.end)}',
                subtitle: _dates == null
                    ? _t('Pick your dates to see what is free',
                        'تاریخ چنیں تاکہ خالی گاڑیاں دکھیں')
                    : _t('${_nights(_dates!)} day(s)',
                        '${_nights(_dates!)} دن'),
                leading: const UdIconTile(
                  icon: Icons.event_rounded,
                  tone: UdIconTone.soft,
                ),
                onTap: _pickDates,
                showChevron: true,
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_vehicles.isEmpty)
            UdEmptyState(
              icon: Icons.no_transfer_rounded,
              title: _t('Nothing free for those dates',
                  'ان تاریخوں میں کچھ خالی نہیں'),
              text: _t(
                'Try a different week, or clear the dates to see every car on '
                'offer.',
                'کوئی اور ہفتہ آزمائیں، یا تاریخ ہٹا کر ساری گاڑیاں دیکھیں۔',
              ),
              action: _dates == null
                  ? null
                  : UdButton.outline(
                      label: _t('Clear dates', 'تاریخ ہٹائیں'),
                      onPressed: () {
                        setState(() => _dates = null);
                        _load();
                      },
                    ),
            )
          else
            ..._vehicles.map(
              (vehicle) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _VehicleCard(
                  vehicle: vehicle,
                  onTap: () => _open(vehicle),
                ),
              ),
            ),
        ],
      );

  Widget _mine() => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 4, AppSizes.sidePadding, 40),
        children: [
          if (_bookings.isEmpty)
            UdEmptyState(
              icon: Icons.vpn_key_outlined,
              title: _t('No rentals yet', 'ابھی کوئی بکنگ نہیں'),
              text: _t(
                'Cars you rent will appear here with the owner\'s number and '
                'where to collect them.',
                'آپ کی کرائے کی گاڑیاں یہاں آئیں گی — مالک کا نمبر اور گاڑی '
                    'کہاں سے ملے گی، دونوں کے ساتھ۔',
              ),
            )
          else
            ..._bookings.map(
              (booking) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BookingCard(
                  booking: booking,
                  onCancel: booking.isLive ? () => _cancel(booking) : null,
                ),
              ),
            ),
        ],
      );

  Future<void> _open(RentalVehicle vehicle) async {
    final booked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RentalBookingScreen(vehicle: vehicle, dates: _dates),
      ),
    );
    if (!mounted) return;
    if (booked == true) {
      setState(() => _tab = 1);
      await _load();
    }
  }

  Future<void> _cancel(RentalBooking booking) async {
    final go = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            _t('Cancel this rental?', 'یہ بکنگ منسوخ کریں؟'),
            style: AppType.h2.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 10),
          Text(
            booking.advanceRefundableNow
                ? _t(
                    'Your advance will be returned.',
                    'آپ کا ایڈوانس واپس ہو جائے گا۔',
                  )
                : _t(
                    'The rental starts soon, so the advance stays with the '
                    'owner — they turned other bookings away for these days.',
                    'بکنگ قریب ہے، اس لیے ایڈوانس مالک کے پاس رہے گا — انہوں '
                        'نے ان دنوں کی دوسری بکنگ منع کی تھی۔',
                  ),
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 20),
          UdButton.primary(
            label: _t('Yes, cancel', 'ہاں، منسوخ کریں'),
            onPressed: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: 10),
          UdButton.ghost(
            label: _t('Keep it', 'رہنے دیں'),
            onPressed: () => Navigator.pop(sheetContext, false),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;
    try {
      await _repository.cancel(booking.id);
      await _load();
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusal.message)));
    }
  }

  static int _nights(DateTimeRange range) =>
      range.end.difference(range.start).inDays + 1;

  static String _day(DateTime value) =>
      '${value.day} ${_months[value.month - 1]}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

/// One car, led by its photograph.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.onTap});

  final RentalVehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return UdCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
            child: Image.network(
              ApiConfig.absoluteUrl(vehicle.photoUrl),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              // A broken image must not leave a car looking like a car with no
              // picture, because this list only contains cars that have one.
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: AppColors.surfaceAlt,
                alignment: Alignment.center,
                child: Icon(Icons.directions_car_rounded,
                    size: 40, color: AppText.caption),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${vehicle.name} ${vehicle.year}',
                        style: AppType.h3.copyWith(color: AppText.primary),
                      ),
                    ),
                    if (vehicle.isFourByFour)
                      const UdBadge(label: '4×4', tone: UdTone.ok),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${vehicle.colour} · ${vehicle.passengerCapacity} seats'
                  '${vehicle.hasAirConditioning ? ' · AC' : ''}',
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PKR ${vehicle.fromDaily.round()}',
                            style: AppType.h2.copyWith(
                                color: AppText.primary, height: 1),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'per day · ${_modes(vehicle)}',
                            style:
                                AppType.caption.copyWith(color: AppText.caption),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      vehicle.ownerName,
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _modes(RentalVehicle vehicle) {
    if (vehicle.offersWithDriver && vehicle.offersSelfDrive) {
      return 'with driver or self-drive';
    }
    return vehicle.offersSelfDrive ? 'self-drive' : 'with a driver';
  }
}

/// One of the Customer's own rentals.
class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onCancel});

  final RentalBooking booking;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return UdCard(
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
                      booking.vehicleName,
                      style: AppType.h3.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.registrationNumber} · ${booking.reference}',
                      style:
                          AppType.caption.copyWith(color: AppText.caption),
                    ),
                  ],
                ),
              ),
              UdBadge(
                label: booking.status,
                tone: switch (booking.status) {
                  'Cancelled' || 'NoShow' => UdTone.err,
                  'Returned' => UdTone.gray,
                  _ => UdTone.ok,
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          UdListGroup(
            children: [
              UdListRow(
                title: '${_d(booking.startDate)} — ${_d(booking.endDate)}',
                subtitle: '${booking.days} day(s) · '
                    '${booking.isSelfDrive ? 'Self-drive' : 'With a driver'}',
              ),
              UdListRow(
                title: 'PKR ${booking.balanceDue.round()} on collection',
                subtitle: 'Plus PKR ${booking.securityDeposit.round()} '
                    'refundable deposit. Advance of PKR '
                    '${booking.advanceAmount.round()} already paid.',
              ),
              if (booking.pickupPoint != null)
                UdListRow(
                  title: booking.pickupPoint!,
                  subtitle: 'Collect from',
                  leading: const UdIconTile(
                    icon: Icons.place_outlined,
                    tone: UdIconTone.neutral,
                  ),
                ),
              UdListRow(
                title: booking.counterpartName,
                subtitle: booking.counterpartPhone ?? 'Owner',
                leading: const UdIconTile(
                  icon: Icons.person_outline_rounded,
                  tone: UdIconTone.neutral,
                ),
              ),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            UdButton.outline(
              label: booking.advanceRefundableNow
                  ? 'Cancel — advance returned'
                  : 'Cancel — advance not returned',
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }

  static String _d(DateTime value) =>
      '${value.day} ${_RentalListScreenState._months[value.month - 1]}';
}
