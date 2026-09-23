import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) =>
      AppControllerScope.of(context).loadDriverMarketplace(notify: !silent);

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final requests = controller.liveDriverRideRequests;
    final verifiedVehicles = controller.liveVehicles.where((vehicle) {
      final status = vehicle.status.trim().toLowerCase();
      return status == 'verified' || status == 'approved';
    }).toList(growable: false);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(context, 'Pending Customer requests', 'زیر التوا کسٹمر درخواستیں'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _t(context, 'Accept with your fare or reject from your own queue.', 'اپنے کرایے کے ساتھ قبول کریں یا اپنی فہرست سے مسترد کریں۔'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppTint.brand, borderRadius: BorderRadius.circular(999)),
                child: Text('${requests.length} live', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (verifiedVehicles.isEmpty)
            PremiumCard(
              color: const Color(0xFFFFF5E5),
              child: Text(
                _t(context, 'Verify at least one vehicle before accepting requests.', 'درخواست قبول کرنے سے پہلے کم از کم ایک گاڑی کی تصدیق کروائیں۔'),
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          if (requests.isEmpty) ...[
            const SizedBox(height: 72),
            const Icon(Icons.inbox_rounded, size: 60, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              _t(context, 'No pending request right now', 'اس وقت کوئی زیر التوا درخواست نہیں'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 5),
            Text(
              _t(context, 'This screen refreshes automatically every 20 seconds.', 'یہ اسکرین ہر 20 سیکنڈ بعد خود ریفریش ہوتی ہے۔'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ] else
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _PremiumRequestCard(
                  request: request,
                  enabled: verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                  onAccept: () => _showOffer(request, verifiedVehicles),
                  onReject: () => _rejectRequest(request),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showOffer(LiveRideRequest request, List<dynamic> vehicles) async {
    final suitable = vehicles.where((vehicle) => vehicle.passengerCapacity >= request.seatsRequested).toList();
    if (suitable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No verified vehicle has enough seats for this request.')),
      );
      return;
    }

    dynamic selectedVehicle = suitable.first;
    final amount = TextEditingController(text: request.customerOffer.round().toString());
    final eta = TextEditingController(text: '20');
    final message = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 4, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t(context, 'Accept & send fare', 'قبول کریں اور کرایہ بھیجیں'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(request.customerName, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 13),
              DropdownButtonFormField<dynamic>(
                initialValue: selectedVehicle,
                decoration: const InputDecoration(labelText: 'Verified vehicle', prefixIcon: Icon(Icons.directions_car_rounded)),
                items: suitable.map<DropdownMenuItem<dynamic>>((vehicle) => DropdownMenuItem<dynamic>(value: vehicle, child: Text('${vehicle.make} ${vehicle.model} · ${vehicle.registrationNumber}'))).toList(),
                onChanged: (value) => setSheetState(() => selectedVehicle = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Your fare (PKR)',
                  prefixIcon: const Icon(Icons.payments_rounded),
                  helperText: 'Customer offered PKR ${NumberFormat('#,###').format(request.customerOffer)}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: eta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pickup ETA (minutes)', prefixIcon: Icon(Icons.schedule_rounded))),
              const SizedBox(height: 10),
              TextField(controller: message, maxLines: 2, decoration: const InputDecoration(labelText: 'Optional message', prefixIcon: Icon(Icons.message_rounded))),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final parsedAmount = double.tryParse(amount.text.trim());
                    if (parsedAmount == null || parsedAmount <= 0) return;
                    try {
                      await AppControllerScope.of(context).submitLiveDriverOffer(
                        rideRequestId: request.id,
                        vehicleId: selectedVehicle.id as String,
                        amount: parsedAmount,
                        etaMinutes: int.tryParse(eta.text.trim()) ?? 20,
                        message: message.text.trim(),
                      );
                      if (!mounted) return;
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fare offer sent to Customer.')));
                    } catch (error) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Accept & send offer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rejectRequest(LiveRideRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this request?'),
        content: const Text('It will be hidden only for your Driver account. Other Drivers may still respond.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppControllerScope.of(context).rejectLiveDriverRequest(
        rideRequestId: request.id,
        reason: 'Driver rejected from live request list.',
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _PremiumRequestCard extends StatelessWidget {
  const _PremiumRequestCard({
    required this.request,
    required this.enabled,
    required this.onAccept,
    required this.onReject,
  });

  final LiveRideRequest request;
  final bool enabled;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => PremiumCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTint.brand,
              child: Text(_initials(request.customerName), style: const TextStyle(color: AppColors.primaryDark, fontSize: 12, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  _Route(icon: Icons.trip_origin_rounded, text: request.pickupLabel, color: AppColors.primary),
                  const SizedBox(height: 3),
                  _Route(icon: Icons.location_on_rounded, text: request.destinationLabel, color: AppColors.danger),
                  const SizedBox(height: 7),
                  Text(
                    '${DateFormat('dd MMM · h:mm a').format(request.pickupAt)} · ${request.seatsRequested} passenger${request.seatsRequested == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 98,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('PKR ${NumberFormat('#,###').format(request.customerOffer)}', maxLines: 1, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(height: 9),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _Action(icon: Icons.close_rounded, color: AppColors.danger, onTap: enabled ? onReject : null),
                      const SizedBox(width: 6),
                      _Action(icon: Icons.check_rounded, color: AppColors.success, onTap: enabled ? onAccept : null),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'CU' : value;
  }
}

class _Route extends StatelessWidget {
  const _Route({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))),
        ],
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.color, this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: onTap == null ? const Color(0xFFF1F3F5) : color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 35, height: 32, child: Icon(icon, size: 18, color: onTap == null ? AppColors.muted : color)),
        ),
      );
}
