import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mode_switch_card.dart';
import '../feedback/feedback_center_screen.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    final controller = AppControllerScope.of(context);
    final name = controller.currentUserName;
    final vehicle = controller.liveVehicles.isEmpty ? null : controller.liveVehicles.first;
    final status = controller.driverVerificationStatus;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(S.of(context, 'profile'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.primary,
                    child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        Text(
                          vehicle == null ? 'No registered vehicle' : '${vehicle.make} ${vehicle.model} · ${vehicle.registrationNumber}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 5),
                        Text('Verification: $status'),
                      ],
                    ),
                  ),
                  Icon(
                    controller.driverApproved ? Icons.verified_rounded : Icons.pending_rounded,
                    color: controller.driverApproved ? AppColors.secondary : AppColors.warning,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const ModeSwitchCard(targetMode: UserMode.customer),
          const SizedBox(height: 12),
          _item('Documents', Icons.badge_outlined, status),
          _item('Vehicle', Icons.directions_car_outlined, vehicle == null ? 'No vehicle registered' : '${vehicle.make} ${vehicle.model}'),
          _item('Capacity', Icons.event_seat_outlined, vehicle == null ? '—' : '${vehicle.passengerCapacity} passengers'),
          _item('Phone', Icons.phone_outlined, controller.currentUserPhone.isEmpty ? '—' : controller.currentUserPhone),
          _item('Ratings & complaints', Icons.star_outline_rounded, 'Rate customers or open a case', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackCenterScreen()))),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.of(context, 'language'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('English')),
                      ButtonSegment(value: 'ur', label: Text('اردو')),
                    ],
                    selected: {language.locale.languageCode},
                    onSelectionChanged: (value) => language.setLanguage(value.first),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2).toList();
    return parts.isEmpty ? 'D' : parts.map((part) => part[0].toUpperCase()).join();
  }

  static Widget _item(String title, IconData icon, String subtitle, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: AppColors.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(subtitle),
            onTap: onTap,
          ),
        ),
      );
}
