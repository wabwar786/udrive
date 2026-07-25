import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';

class LiveDriverRequestsScreen extends StatefulWidget {
  const LiveDriverRequestsScreen({super.key});

  @override
  State<LiveDriverRequestsScreen> createState() => _LiveDriverRequestsScreenState();
}

class _LiveDriverRequestsScreenState extends State<LiveDriverRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() => AppControllerScope.of(context).loadDriverMarketplace();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final requests = controller.liveDriverRideRequests;
    final verifiedVehicles = controller.liveVehicles.where((v) => v.status == 'Verified').toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(context, 'Live tourism requests', 'لائیو ٹورزم درخواستیں'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(context, 'Only verified Drivers and suitable vehicles can submit offers.', 'صرف تصدیق شدہ ڈرائیور اور موزوں گاڑیاں آفر دے سکتی ہیں۔'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (verifiedVehicles.isEmpty)
            PremiumCard(
              color: const Color(0xFFFFF5E5),
              child: Text(
                _t(context, 'Verify at least one vehicle before submitting live offers.', 'لائیو آفر دینے سے پہلے کم از کم ایک گاڑی کی تصدیق کروائیں۔'),
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800),
              ),
            ),
          if (requests.isEmpty) ...[
            const SizedBox(height: 70),
            const Icon(Icons.inbox_rounded, size: 66, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(
              _t(context, 'No eligible requests right now', 'اس وقت کوئی موزوں درخواست نہیں'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
          ] else
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestCard(
                  request: request,
                  enabled: verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                  onOffer: () => _showOffer(request, verifiedVehicles.first),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showOffer(LiveRideRequest request, dynamic vehicle) async {
    final amount = TextEditingController(text: request.customerOffer.round().toString());
    final eta = TextEditingController(text: '20');
    final message = TextEditingController(text: 'Verified tourism Driver. Safe daylight route recommended.');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_t(context, 'Submit Driver offer', 'ڈرائیور آفر جمع کریں'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Offer amount (PKR)', prefixIcon: Icon(Icons.payments_rounded))),
            const SizedBox(height: 10),
            TextField(controller: eta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pickup ETA (minutes)', prefixIcon: Icon(Icons.schedule_rounded))),
            const SizedBox(height: 10),
            TextField(controller: message, maxLines: 2, decoration: const InputDecoration(labelText: 'Message', prefixIcon: Icon(Icons.message_rounded))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                try {
                  await AppControllerScope.of(context).submitLiveDriverOffer(
                    rideRequestId: request.id,
                    vehicleId: vehicle.id as String,
                    amount: double.parse(amount.text),
                    etaMinutes: int.tryParse(eta.text) ?? 20,
                    message: message.text.trim(),
                  );
                  if (!mounted) return;
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t(context, 'Offer submitted successfully', 'آفر کامیابی سے جمع ہوگئی'))));
                } catch (error) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                }
              },
              child: Text(_t(context, 'Send offer', 'آفر بھیجیں')),
            ),
          ],
        ),
      ),
    );
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.enabled, required this.onOffer});
  final LiveRideRequest request;
  final bool enabled;
  final VoidCallback onOffer;

  @override
  Widget build(BuildContext context) => PremiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusPill(label: request.bookingType),
                const Spacer(),
                Text('PKR ${NumberFormat('#,###').format(request.customerOffer)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 13),
            Text('${request.pickupLabel} → ${request.destinationLabel}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Fact(Icons.calendar_month_rounded, DateFormat('dd MMM · hh:mm a').format(request.pickupAt)),
                _Fact(Icons.event_seat_rounded, '${request.seatsRequested} seats'),
                _Fact(Icons.luggage_rounded, '${request.luggageCount} bags'),
                _Fact(Icons.directions_car_rounded, request.vehicleCategory),
              ],
            ),
            if (request.familyOnly || request.womenOnly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (request.familyOnly) const StatusPill(label: 'Family only', color: AppColors.secondary),
                  if (request.womenOnly) const StatusPill(label: 'Women preference', color: AppColors.info),
                ],
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: enabled ? onOffer : null,
              icon: const Icon(Icons.local_offer_rounded),
              label: const Text('Accept / Counteroffer'),
            ),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      );
}
