import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mode_switch_card.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            S.of(context, 'profile'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      'SQ',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shahzad Ahmad Qureshi',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Suzuki Alto · AJK-219',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        SizedBox(height: 5),
                        Text('★ 4.9 · 834 trips'),
                      ],
                    ),
                  ),
                  Icon(Icons.verified_rounded, color: AppColors.secondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const ModeSwitchCard(targetMode: UserMode.customer),
          const SizedBox(height: 12),
          ...const [
            ('Documents', Icons.badge_outlined, 'All verified'),
            ('Vehicle', Icons.directions_car_outlined, 'Suzuki Alto 2023'),
            ('Service areas', Icons.map_outlined, 'Muzaffarabad, Neelum'),
            ('Availability', Icons.calendar_month_outlined, 'Open schedule'),
          ].map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Card(
                child: ListTile(
                  leading: Icon(item.$2, color: AppColors.primary),
                  title: Text(
                    item.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(item.$3),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context, 'language'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
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
}
