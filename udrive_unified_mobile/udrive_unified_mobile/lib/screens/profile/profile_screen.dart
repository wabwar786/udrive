import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mode_switch_card.dart';
import '../feedback/feedback_center_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    final controller = AppControllerScope.of(context);
    final name = controller.currentUserName;
    final phone = controller.currentUserPhone;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(S.of(context, 'profile'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
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
                        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(phone.isEmpty ? '—' : phone, style: const TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const ModeSwitchCard(targetMode: UserMode.driver),
          const SizedBox(height: 10),
          const ModeSwitchCard(targetMode: UserMode.hotel),
          const SizedBox(height: 14),
          _tile(Icons.bookmark_border_rounded, S.of(context, 'savedPlaces'), 'View saved places'),
          _tile(Icons.health_and_safety_outlined, S.of(context, 'safety'), 'Open safety centre'),
          _tile(Icons.star_outline_rounded, 'Ratings & complaints', 'Rate trips or open a support case', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackCenterScreen()))),
          _tile(Icons.support_agent_rounded, S.of(context, 'support'), 'Open help centre'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.of(context, 'language'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'en', label: Text(S.of(context, 'english'))),
                      ButtonSegment(value: 'ur', label: Text(S.of(context, 'urdu'))),
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
    return parts.isEmpty ? 'U' : parts.map((part) => part[0].toUpperCase()).join();
  }

  static Widget _tile(IconData icon, String title, String subtitle, {VoidCallback? onTap}) => Card(
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}
