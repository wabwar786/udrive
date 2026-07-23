import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF0A493A), AppColors.primary])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(radius: 27, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, color: AppColors.primaryDark, size: 30)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Shahzad Ahmad', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), SizedBox(height: 3), Text('Verified tourism driver · 4.9 ★', style: TextStyle(color: Colors.white70, fontSize: 12))])),
              Switch(value: controller.driverOnline, onChanged: controller.toggleDriverOnline, activeThumbColor: AppColors.accent, activeTrackColor: Colors.white30),
            ]),
            const SizedBox(height: 18),
            Row(children: [Icon(controller.driverOnline ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded, color: Colors.white), const SizedBox(width: 8), Text(controller.driverOnline ? 'You are online and receiving requests' : 'You are offline', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))]),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const MetricTile(icon: Icons.payments_rounded, label: "Today's earnings", value: 'PKR 8,450', color: AppColors.primary),
          const SizedBox(width: 10),
          const MetricTile(icon: Icons.route_rounded, label: 'Completed trips', value: '4', color: AppColors.secondary),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const MetricTile(icon: Icons.star_rounded, label: 'Driver rating', value: '4.9', color: AppColors.accent),
          const SizedBox(width: 10),
          MetricTile(icon: Icons.account_balance_wallet_rounded, label: 'Available balance', value: 'PKR ${controller.walletBalance}', color: const Color(0xFF7C3AED)),
        ]),
        const SizedBox(height: 22),
        SectionHeader(title: context.tr('rideRequests'), action: context.tr('viewAll'), onAction: () => onNavigate('requests')),
        const SizedBox(height: 10),
        PremiumCard(
          color: const Color(0xFFFFF9E9),
          onTap: () => onNavigate('requests'),
          child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .14), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.notifications_active_rounded, color: AppColors.warning)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('3 new ride requests', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), SizedBox(height: 4), Text('Best match: Islamabad → Muzaffarabad · PKR 7,200', style: TextStyle(color: AppColors.muted, fontSize: 12))])), const Icon(Icons.chevron_right_rounded)]),
        ),
        const SizedBox(height: 22),
        SectionHeader(title: 'Driver tools'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _DriverTool(icon: Icons.directions_car_filled_rounded, label: context.tr('vehicles'), color: AppColors.primary, onTap: () => onNavigate('vehicles')),
            _DriverTool(icon: Icons.add_box_rounded, label: context.tr('createPackage'), color: const Color(0xFF7C3AED), onTap: () => onNavigate('createPackage')),
            _DriverTool(icon: Icons.account_balance_wallet_rounded, label: context.tr('payouts'), color: AppColors.secondary, onTap: () => onNavigate('payouts')),
            _DriverTool(icon: Icons.calendar_month_rounded, label: context.tr('availability'), color: AppColors.accent, onTap: () => onNavigate('availability')),
          ],
        ),
        const SizedBox(height: 22),
        SectionHeader(title: context.tr('activeTrip')),
        const SizedBox(height: 10),
        PremiumCard(
          onTap: () => onNavigate('activeTrip'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const StatusPill(label: 'Pickup in 18 min', color: AppColors.info), const Spacer(), Text('PKR 7,200', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 17))]),
            const SizedBox(height: 13),
            const Text('F-8 Markaz, Islamabad → Muzaffarabad', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Customer: Hassan Ali · 3 passengers', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 13),
            const LinearProgressIndicator(value: .32, borderRadius: BorderRadius.all(Radius.circular(20))),
          ]),
        ),
        const SizedBox(height: 22),
        PremiumCard(color: const Color(0xFFEAF4FF), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.cloudy_snowing, color: AppColors.info), SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Driver route update', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('Keran road is open for SUVs and 4×4 vehicles. Avoid travel after 7 PM.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35))]))])),
      ],
    );
  }
}

class _DriverTool extends StatelessWidget {
  const _DriverTool({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PremiumCard(onTap: onTap, padding: const EdgeInsets.all(13), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color)), const SizedBox(width: 10), Expanded(child: Text(label, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)))]));
}
