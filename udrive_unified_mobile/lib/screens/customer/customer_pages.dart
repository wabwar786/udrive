import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';

// `ExploreScreen` used to live here too, and nothing built it. `main_shell`
// sends the 'explore' key to `LiveExploreScreen`, and this file is imported
// for `ProfileScreen` alone — so the class sat here running on the old
// `data/dummy_data.dart` destinations, a screen the app could not reach.
// (A second, equally unreachable `ExploreScreen` is still in
// `screens/explore/explore_screen.dart`; that whole file is an orphan and
// `tool/check_imports.py` already reports it.)

/// C-50 — Profile.
///
/// A bottom-nav tab root: `main_shell` supplies the top bar, so there is no
/// `Scaffold` and no app bar here.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 0, AppSizes.sidePadding, 34),
      children: [
        UdHeroTitle(
          title: context.tr('profile'),
          padding: const EdgeInsets.only(bottom: 18),
        ),
        UdCard(
          tone: UdCardTone.navy,
          child: Column(
            children: [
              const UdIconTile(
                icon: Icons.person_rounded,
                tone: UdIconTone.lime,
                size: UdIconTileSize.lg,
              ),
              const SizedBox(height: 16),
              Text(
                controller.currentUserName,
                textAlign: TextAlign.center,
                style: AppType.h2.copyWith(color: AppText.onInk),
              ),
              const SizedBox(height: 6),
              Text(
                controller.currentUserPhone,
                textAlign: TextAlign.center,
                // Was AppColors.onInkMuted at 11px. Same colour, but nothing
                // in v2 goes below 12.5.
                style: AppType.body2.copyWith(color: AppText.onInkMuted),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  const UdBadge(label: 'Customer account', tone: UdTone.lime),
                  UdBadge(
                    label: controller.currentUser?.accountStatus ?? 'Active',
                    tone: UdTone.ok,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        UdButton.dark(
          label: context.tr('switchDriver'),
          icon: Icons.drive_eta_rounded,
          onPressed: () => controller.switchMode(UserMode.driver),
        ),
        const SizedBox(height: 26),
        const UdSectionHeader(title: 'Account'),
        const SizedBox(height: 14),
        UdListGroup(
          children: [
            // Three rows, not the design's four.
            //
            // 'saved' was removed with the saved-places screen. It had no route
            // case left, so tapping it fell through main_shell's default and
            // silently re-rendered Home — a menu row that looks broken rather
            // than absent. Putting it back would put that bug back.
            for (final item in <(String, IconData, String, String)>[
              (
                'safety',
                Icons.health_and_safety_rounded,
                context.tr('safety'),
                'SOS, trusted contacts and trip safety',
              ),
              (
                'settings',
                Icons.settings_rounded,
                context.tr('settings'),
                'Language, notifications and account',
              ),
              (
                'support',
                Icons.support_agent_rounded,
                context.tr('support'),
                'Ratings, complaints and help',
              ),
            ])
              UdListRow(
                title: item.$3,
                subtitle: item.$4,
                leading: UdIconTile(icon: item.$2),
                showChevron: true,
                onTap: () => onNavigate(item.$1),
              ),
          ],
        ),
      ],
    );
  }
}
