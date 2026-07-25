import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final c = AppControllerScope.of(context);
    await c.refreshAccount();
    if (c.driverApproved) await c.loadDriverMarketplace();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppControllerScope.of(context);
    final verifiedVehicles = c.liveVehicles.where((v) => v.status == 'Verified').toList();
    final packageBookings = c.liveDriverPackageBookings;
    final active = packageBookings.where((b) => !_closed.contains(b.status)).toList()
      ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
    final completed = packageBookings.where((b) => b.status == 'Completed').length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(25), gradient: const LinearGradient(colors: [Color(0xFF0A493A), AppColors.primary])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(radius: 25, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, color: AppColors.primaryDark, size: 28)),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.currentUserName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(c.driverVerificationStatus, style: const TextStyle(color: Colors.white70, fontSize: 11))])),
                Switch(value: c.driverOnline, onChanged: c.toggleDriverOnline, activeThumbColor: AppColors.accent),
              ]),
              const SizedBox(height: 14),
              Row(children: [Icon(c.driverOnline ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded, color: Colors.white, size: 19), const SizedBox(width: 7), Expanded(child: Text(c.driverOnline ? _t('Online for new requests', 'نئی درخواستوں کے لیے آن لائن') : _t('Currently offline', 'اس وقت آف لائن'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)))]),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Metric(label: _t('Ride requests', 'رائیڈ درخواستیں'), value: '${c.liveDriverRideRequests.length}', icon: Icons.notifications_active_rounded, color: AppColors.warning)),
            const SizedBox(width: 9),
            Expanded(child: _Metric(label: _t('Verified vehicles', 'تصدیق شدہ گاڑیاں'), value: '${verifiedVehicles.length}', icon: Icons.directions_car_rounded, color: AppColors.primary)),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: _Metric(label: _t('Active bookings', 'فعال بکنگز'), value: '${active.length}', icon: Icons.route_rounded, color: AppColors.info)),
            const SizedBox(width: 9),
            Expanded(child: _Metric(label: _t('Completed', 'مکمل'), value: '$completed', icon: Icons.task_alt_rounded, color: AppColors.success)),
          ]),
          const SizedBox(height: 20),
          SectionHeader(title: _t('Driver tools', 'ڈرائیور ٹولز')),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _Tool(icon: Icons.notifications_active_rounded, label: context.tr('rideRequests'), onTap: () => widget.onNavigate('requests')),
              _Tool(icon: Icons.directions_car_filled_rounded, label: context.tr('vehicles'), onTap: () => widget.onNavigate('vehicles')),
              _Tool(icon: Icons.luggage_rounded, label: context.tr('myPackages'), onTap: () => widget.onNavigate('driverPackages')),
              _Tool(icon: Icons.account_balance_wallet_rounded, label: context.tr('earnings'), onTap: () => widget.onNavigate('earnings')),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(title: _t('Latest assignment', 'تازہ ترین اسائنمنٹ'), action: active.isEmpty ? null : _t('Open', 'کھولیں'), onAction: active.isEmpty ? null : () => widget.onNavigate('activeTrip')),
          const SizedBox(height: 10),
          if (active.isEmpty)
            _Empty(message: _t('No active Driver assignment is available from the database.', 'ڈیٹابیس میں کوئی فعال ڈرائیور اسائنمنٹ موجود نہیں۔'))
          else
            _Booking(booking: active.first, onTap: () => widget.onNavigate('activeTrip')),
          const SizedBox(height: 20),
          SectionHeader(title: _t('Vehicle readiness', 'گاڑی کی تیاری')),
          const SizedBox(height: 10),
          if (c.liveVehicles.isEmpty)
            _Empty(message: _t('No vehicle is registered. Add and submit a vehicle for verification.', 'کوئی گاڑی رجسٹرڈ نہیں۔ گاڑی شامل کر کے تصدیق کے لیے جمع کریں۔'))
          else
            ...c.liveVehicles.take(2).map((v) => Padding(padding: const EdgeInsets.only(bottom: 9), child: PremiumCard(onTap: () => widget.onNavigate('vehicles'), child: Row(children: [const Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${v.make} ${v.model}', style: const TextStyle(fontWeight: FontWeight.w900)), Text('${v.registrationNumber} · ${v.passengerCapacity} seats', style: const TextStyle(color: AppColors.muted, fontSize: 11))])), StatusPill(label: v.status, color: v.status == 'Verified' ? AppColors.success : AppColors.warning)])))),
          if (c.marketplaceError != null) ...[const SizedBox(height: 8), _Error(message: c.marketplaceError!, onRetry: _refresh)],
        ],
      ),
    );
  }

  String _t(String en, String ur) => AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
  static const _closed = {'Completed', 'Cancelled', 'NoShow'};
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon, required this.color});
  final String label; final String value; final IconData icon; final Color color;
  @override Widget build(BuildContext context) => PremiumCard(padding: const EdgeInsets.all(13), child: Row(children: [Container(width: 39, height: 39, decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, maxLines: 2, style: const TextStyle(color: AppColors.muted, fontSize: 10))]))]));
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override Widget build(BuildContext context) => PremiumCard(onTap: onTap, padding: const EdgeInsets.all(13), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: AppColors.primaryDark)), const SizedBox(width: 10), Expanded(child: Text(label, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)))]));
}

class _Booking extends StatelessWidget {
  const _Booking({required this.booking, required this.onTap}); final LiveBooking booking; final VoidCallback onTap;
  @override Widget build(BuildContext context) => PremiumCard(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(booking.bookingReference, style: const TextStyle(fontWeight: FontWeight.w900))), StatusPill(label: booking.status)]), const SizedBox(height: 10), Text('${booking.pickupLabel} → ${booking.destinationLabel}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)), const SizedBox(height: 6), Text(DateFormat('dd MMM yyyy · hh:mm a').format(booking.pickupAt), style: const TextStyle(color: AppColors.muted, fontSize: 11)), const Divider(height: 22), Row(children: [Text('${booking.seatsBooked} passenger(s)', style: const TextStyle(color: AppColors.muted, fontSize: 11)), const Spacer(), Text('PKR ${NumberFormat('#,##0').format(booking.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.w900))]) ]));
}

class _Empty extends StatelessWidget { const _Empty({required this.message}); final String message; @override Widget build(BuildContext context) => PremiumCard(child: Row(children: [const Icon(Icons.inbox_outlined, color: AppColors.muted), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 12)))])); }
class _Error extends StatelessWidget { const _Error({required this.message, required this.onRetry}); final String message; final VoidCallback onRetry; @override Widget build(BuildContext context) => PremiumCard(color: const Color(0xFFFFF3F2), child: Row(children: [const Icon(Icons.error_outline, color: AppColors.danger), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(fontSize: 11))), TextButton(onPressed: onRetry, child: const Text('Retry'))])); }
