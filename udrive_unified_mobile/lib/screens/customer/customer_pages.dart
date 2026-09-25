import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import 'package_detail_screen.dart';
import 'tourism_booking_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = destinations.where((e) => e.name.toLowerCase().contains(_query.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
      TextField(onChanged: (value) => setState(() => _query = value), decoration: InputDecoration(hintText: '${context.tr('search')} destinations', prefixIcon: const Icon(Icons.search_rounded))),
      const SizedBox(height: 18),
      ...filtered.map((item) => Padding(padding: EdgeInsets.only(bottom: 14), child: PremiumCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(23)), child: Image.asset(item.image, height: 190, width: double.infinity, fit: BoxFit.cover)), Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(item.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), StatusPill(label: '${item.rating} ★', color: AppColors.accent)]), SizedBox(height: 5), Text(item.location, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)), SizedBox(height: 10), Text(item.description, style: TextStyle(color: AppColors.muted, height: 1.4)), SizedBox(height: 14), FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TourismBookingScreen(initialDestination: item.name))), icon: Icon(Icons.local_taxi_rounded), label: Text('Ride to ${item.name}'))]))])))),
    ]);
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(padding: const EdgeInsets.all(18), children: [
      PremiumCard(color: AppColors.navy, child: Column(children: [CircleAvatar(radius: 38, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, size: 42, color: AppColors.primaryDark)), SizedBox(height: 12), Text(controller.currentUserName, style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)), SizedBox(height: 4), Text(controller.currentUserPhone, style: TextStyle(color: AppColors.onInkMuted, fontSize: 11)), SizedBox(height: 15), Row(mainAxisAlignment: MainAxisAlignment.center, children: [StatusPill(label: 'Customer account', color: AppColors.brand), SizedBox(width: 8), StatusPill(label: controller.currentUser?.accountStatus ?? 'Active', color: AppColors.brand)])])),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: () => controller.switchMode(UserMode.driver), icon: const Icon(Icons.drive_eta_rounded), label: Text(context.tr('switchDriver'))),
      const SizedBox(height: 14),
      // 'saved' was removed with the saved-places screen. It had no route case
      // left, so tapping it fell through main_shell's default and silently
      // re-rendered Home — a menu row that looks broken rather than absent.
      for (final item in [('safety', Icons.health_and_safety_rounded, context.tr('safety')), ('settings', Icons.settings_rounded, context.tr('settings')), ('support', Icons.support_agent_rounded, context.tr('support'))]) Padding(padding: const EdgeInsets.only(bottom: 9), child: PremiumCard(onTap: () => onNavigate(item.$1), child: Row(children: [Icon(item.$2, color: AppColors.primaryDark), const SizedBox(width: 13), Expanded(child: Text(item.$3, style: const TextStyle(fontWeight: FontWeight.w900))), const Icon(Icons.chevron_right_rounded)]))),
    ]);
  }
}

