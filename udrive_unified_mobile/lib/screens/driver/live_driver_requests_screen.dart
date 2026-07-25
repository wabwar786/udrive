import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import '../../models/auth_models.dart';

class LiveDriverRequestsScreen extends StatefulWidget {
  const LiveDriverRequestsScreen({super.key});

  @override
  State<LiveDriverRequestsScreen> createState() => _LiveDriverRequestsScreenState();
}

class _LiveDriverRequestsScreenState extends State<LiveDriverRequestsScreen> {
  Timer? _poller;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poller = Timer.periodic(const Duration(seconds: 20), (_) => _refresh(silent: true));
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    await AppControllerScope.of(context).loadDriverMarketplace();
    if (!mounted || silent) return;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final requests = controller.liveDriverRideRequests
        .where((r) => r.status == 'Open' || r.status == 'ReceivingOffers')
        .where((r) => r.pickupAt.isAfter(DateTime.now()))
        .where((r) => r.expiresAt == null || r.expiresAt!.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
    final verifiedVehicles = controller.liveVehicles
        .where((v) => v.status == 'Verified')
        .toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Row(
              children: [
                const Icon(Icons.people_alt_rounded, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(context, 'Open customer requests', 'کھلی کسٹمر درخواستیں'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _t(context, 'Send your fare before the one-hour response window closes.', 'ایک گھنٹے کی مدت ختم ہونے سے پہلے اپنا کرایہ بھیجیں۔'),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
                  child: Text('${requests.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (verifiedVehicles.isEmpty)
            PremiumCard(
              color: const Color(0xFFFFF5E5),
              child: Text(
                _t(context, 'Verify at least one vehicle before sending an offer.', 'آفر بھیجنے سے پہلے کم از کم ایک گاڑی کی تصدیق کروائیں۔'),
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800),
              ),
            ),
          if (controller.marketplaceBusy && requests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (requests.isEmpty) ...[
            const SizedBox(height: 70),
            const Icon(Icons.inbox_rounded, size: 62, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              _t(context, 'No pending customer request', 'کوئی زیر التوا کسٹمر درخواست نہیں'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              _t(context, 'New requests appear here automatically.', 'نئی درخواستیں خودکار طور پر یہاں ظاہر ہوں گی۔'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ] else
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RequestCard(
                  request: request,
                  enabled: verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                  onOffer: () => _showOffer(request, verifiedVehicles),
                ),
              ),
            ),
          if (controller.marketplaceError != null && requests.isEmpty) ...[
            const SizedBox(height: 12),
            Text(controller.marketplaceError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Future<void> _showOffer(LiveRideRequest request, List<LiveVehicle> vehicles) async {
    final suitable = vehicles.where((v) => v.passengerCapacity >= request.seatsRequested).toList();
    if (suitable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(context, 'No verified vehicle has enough seats for this request.', 'اس درخواست کے لیے کسی تصدیق شدہ گاڑی میں کافی نشستیں نہیں۔'))),
      );
      return;
    }

    var selectedVehicleId = suitable.first.id;
    final amount = TextEditingController(text: request.customerOffer.round().toString());
    final eta = TextEditingController(text: '20');
    final message = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t(context, 'Send fare offer', 'کرایہ آفر بھیجیں'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text('${request.pickupLabel} → ${request.destinationLabel}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF1FAF6), borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.sell_rounded, color: AppColors.primaryDark),
                    const SizedBox(width: 9),
                    Expanded(child: Text(_t(context, 'Customer offer', 'کسٹمر آفر'), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('PKR ${NumberFormat('#,###').format(request.customerOffer)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                  ]),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedVehicleId,
                  decoration: const InputDecoration(labelText: 'Verified vehicle', prefixIcon: Icon(Icons.directions_car_rounded)),
                  items: suitable.map((v) => DropdownMenuItem(value: v.id, child: Text('${v.make} ${v.model} · ${v.registrationNumber} (${v.passengerCapacity} seats)'))).toList(),
                  onChanged: (value) => setSheetState(() => selectedVehicleId = value ?? selectedVehicleId),
                ),
                const SizedBox(height: 10),
                TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your fare (PKR)', prefixIcon: Icon(Icons.payments_rounded))),
                const SizedBox(height: 10),
                TextField(controller: eta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pickup ETA (minutes)', prefixIcon: Icon(Icons.schedule_rounded))),
                const SizedBox(height: 10),
                TextField(controller: message, maxLines: 2, decoration: const InputDecoration(labelText: 'Optional message', prefixIcon: Icon(Icons.message_rounded))),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final fare = double.tryParse(amount.text.trim());
                      if (fare == null || fare <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid fare amount.')));
                        return;
                      }
                      try {
                        await AppControllerScope.of(this.context).submitLiveDriverOffer(
                          rideRequestId: request.id,
                          vehicleId: selectedVehicleId,
                          amount: fare,
                          etaMinutes: int.tryParse(eta.text) ?? 20,
                          message: message.text.trim(),
                        );
                        if (!mounted) return;
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(_t(this.context, 'Offer sent to customer', 'آفر کسٹمر کو بھیج دی گئی'))));
                      } catch (error) {
                        if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('$error')));
                      }
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: Text(_t(context, 'Send offer', 'آفر بھیجیں')),
                  ),
                ),
              ],
            ),
          ),
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
  Widget build(BuildContext context) {
    final remaining = request.expiresAt?.difference(DateTime.now());
    final expired = remaining != null && remaining.isNegative;
    final remainingText = expired
        ? 'Closed'
        : remaining == null
            ? '1 hour window'
            : '${remaining.inMinutes.clamp(0, 59)}m ${remaining.inSeconds.remainder(60).clamp(0, 59)}s left';

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            StatusPill(label: request.bookingType),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFFFF3DF), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.timer_outlined, size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Text(remainingText, style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 10)),
              ]),
            ),
          ]),
          const SizedBox(height: 11),
          Text('${request.pickupLabel} → ${request.destinationLabel}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 11, runSpacing: 7, children: [
            _Fact(Icons.calendar_month_rounded, DateFormat('dd MMM · hh:mm a').format(request.pickupAt)),
            _Fact(Icons.event_seat_rounded, '${request.seatsRequested} seats'),
            _Fact(Icons.luggage_rounded, '${request.luggageCount} bags'),
            _Fact(Icons.directions_car_rounded, request.vehicleCategory),
          ]),
          const Divider(height: 22),
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Customer offer', style: TextStyle(color: AppColors.muted, fontSize: 10)),
              Text('PKR ${NumberFormat('#,###').format(request.customerOffer)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 17)),
            ]),
            const Spacer(),
            FilledButton.icon(
              onPressed: enabled && !expired ? onOffer : null,
              icon: const Icon(Icons.local_offer_rounded, size: 18),
              label: const Text('Send fare'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      );
}
