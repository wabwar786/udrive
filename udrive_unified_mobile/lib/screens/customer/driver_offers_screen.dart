import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({
    required this.rideRequestId,
    required this.pickup,
    required this.destination,
    required this.customerOffer,
    required this.vehicleName,
    super.key,
  });

  final String rideRequestId;
  final String pickup;
  final String destination;
  final int customerOffer;
  final String vehicleName;

  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen> {
  Timer? _poller;
  String? _selectedOfferId;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poller = Timer.periodic(const Duration(seconds: 6), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    final controller = AppControllerScope.of(context);
    await controller.loadRideOffers(widget.rideRequestId);
    if (!mounted || silent || controller.marketplaceError == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(controller.marketplaceError!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    LiveRideRequest? request;
    for (final item in controller.liveRideRequests) {
      if (item.id == widget.rideRequestId) { request = item; break; }
    }
    final offers = controller.liveDriverOffers
        .where((offer) => offer.rideRequestId == widget.rideRequestId)
        .toList()
      ..sort((a, b) => a.finalAmount.compareTo(b.finalAmount));

    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'Live Driver Offers', 'لائیو ڈرائیور آفرز')),
        actions: [
          IconButton(
            tooltip: _t(context, 'Refresh offers', 'آفرز تازہ کریں'),
            onPressed: controller.marketplaceBusy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          children: [
            PremiumCard(
              color: const Color(0xFFF1FAF6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusPill(
                        label: request?.status == 'NoDriverAccepted'
                            ? _t(context, 'No Driver accepted', 'کسی ڈرائیور نے قبول نہیں کیا')
                            : offers.isEmpty
                            ? _t(context, 'Finding drivers', 'ڈرائیور تلاش ہو رہے ہیں')
                            : _t(context, '${offers.length} offers received', '${offers.length} آفرز موصول'),
                      ),
                      const Spacer(),
                      if (controller.marketplaceBusy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${widget.pickup} → ${widget.destination}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _MiniInfo(icon: Icons.directions_car_rounded, label: widget.vehicleName),
                      _MiniInfo(
                        icon: Icons.sell_rounded,
                        label: 'PKR ${NumberFormat('#,###').format(widget.customerOffer)}',
                      ),
                      _MiniInfo(
                        icon: Icons.lock_clock_rounded,
                        label: _t(context, 'Offers expire automatically', 'آفرز خودکار ختم ہوں گی'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (offers.isEmpty) _emptyState(context, request) else ...offers.map(_offerCard),
          ],
        ),
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: FilledButton.icon(
            onPressed: _selectedOfferId == null || _confirming ? null : _confirm,
            icon: _confirming
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.verified_user_rounded),
            label: Text(_t(context, 'Select verified Driver', 'تصدیق شدہ ڈرائیور منتخب کریں')),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, LiveRideRequest? request) => Padding(
        padding: const EdgeInsets.only(top: 58),
        child: Column(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, size: 42, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 18),
            Text(
              request?.status == 'NoDriverAccepted'
                  ? _t(context, 'No Driver accepted within 1 hour', 'ایک گھنٹے میں کسی ڈرائیور نے قبول نہیں کیا')
                  : _t(context, 'Waiting for verified Drivers', 'تصدیق شدہ ڈرائیورز کا انتظار ہے'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                context,
                request?.status == 'NoDriverAccepted'
                    ? 'Try again, change the departure time, or increase your offered fare.'
                    : 'This page refreshes automatically for up to one hour.',
                request?.status == 'NoDriverAccepted'
                    ? 'دوبارہ کوشش کریں، وقت تبدیل کریں یا اپنی آفر بڑھائیں۔'
                    : 'یہ صفحہ ایک گھنٹے تک خودکار تازہ ہوتا ہے۔',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ],
        ),
      );

  Widget _offerCard(LiveDriverOffer offer) {
    final selected = _selectedOfferId == offer.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _selectedOfferId = offer.id),
        borderRadius: BorderRadius.circular(24),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: AppColors.primary.withValues(alpha: .12),
                      child: Text(
                        offer.driverName.isEmpty ? 'D' : offer.driverName.characters.first,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  offer.driverName,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(Icons.verified_rounded, size: 18, color: AppColors.info),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${offer.vehicle} · ${offer.registrationNumber}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'PKR ${NumberFormat('#,###').format(offer.finalAmount)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        Text(
                          _t(context, '${offer.estimatedArrivalMinutes} min away', '${offer.estimatedArrivalMinutes} منٹ دور'),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 26),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                    Text(' ${offer.driverRating.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 12),
                    const Icon(Icons.route_rounded, color: AppColors.muted, size: 17),
                    Text(' ${offer.completedTrips}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    const Spacer(),
                    const Icon(Icons.shield_rounded, color: AppColors.success, size: 17),
                    Text(' ${offer.safetyScore}/100', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check_circle_rounded, color: AppColors.primary),
                      ),
                  ],
                ),
                if (offer.message?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      offer.message!,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    try {
      final controller = AppControllerScope.of(context);
      final booking = await controller.selectLiveDriverOffer(
        rideRequestId: widget.rideRequestId,
        offerId: _selectedOfferId!,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 52),
                ),
                const SizedBox(height: 18),
                Text(
                  _t(context, 'Booking confirmed', 'بکنگ کی تصدیق ہوگئی'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  booking.bookingReference,
                  style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                const MapPreview(height: 180),
                const SizedBox(height: 14),
                PremiumCard(
                  child: Column(
                    children: [
                      _ResultLine(label: _t(context, 'Driver', 'ڈرائیور'), value: booking.driverName ?? '-'),
                      _ResultLine(label: _t(context, 'Vehicle', 'گاڑی'), value: booking.vehicle ?? '-'),
                      _ResultLine(label: _t(context, 'Trip OTP', 'سفر او ٹی پی'), value: booking.tripOtp ?? '-'),
                      _ResultLine(
                        label: _t(context, 'Total', 'کل رقم'),
                        value: 'PKR ${NumberFormat('#,###').format(booking.totalAmount)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: Text(_t(context, 'Open My Trips', 'میرے سفر کھولیں')),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.primaryDark),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      );
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900))),
          ],
        ),
      );
}
