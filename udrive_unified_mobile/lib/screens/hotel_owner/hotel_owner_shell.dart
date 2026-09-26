import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';
import 'hotel_owner_add_screen.dart';
import 'hotel_owner_dashboard.dart';

/// Hotel mode's own shell.
///
/// `main_shell` hands the whole screen over to this when the mode is hotel,
/// so there is one bar on screen, not two — this is the bar.
class HotelOwnerShell extends StatefulWidget {
  const HotelOwnerShell({super.key});

  @override
  State<HotelOwnerShell> createState() => _HotelOwnerShellState();
}

class _HotelOwnerShellState extends State<HotelOwnerShell> {
  int _index = 0;

  static const _titles = ['My hotels', 'Add hotel', 'Hotel mode'];

  @override
  Widget build(BuildContext context) {
    // Tabs are swapped inside one route, so the Navigator has nothing to pop
    // and the system back gesture used to close the app from the second or
    // third tab. Back now returns to the first tab, and leaves the app only
    // from there.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: UdTopBar(title: _titles[_index]),
        body: IndexedStack(
          index: _index,
          children: const [
            HotelOwnerDashboard(),
            HotelOwnerAddScreen(),
            _OwnerProfile(),
          ],
        ),
        // Was Material 3's `NavigationBar`, which brings its own pill, its
        // own type and its own height. Customer and driver are both on the
        // kit's bar; hotel mode was the last one that was not.
        bottomNavigationBar: UdBottomNav(
          currentIndex: _index,
          onSelected: (value) => setState(() => _index = value),
          destinations: const [
            UdNavDestination(
              icon: Icons.hotel_outlined,
              activeIcon: Icons.hotel_rounded,
              label: 'Hotels',
            ),
            UdNavDestination(
              icon: Icons.add_business_outlined,
              activeIcon: Icons.add_business_rounded,
              label: 'Add hotel',
            ),
            UdNavDestination(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// The third tab: which mode you are in, and how to leave it.
class _OwnerProfile extends StatelessWidget {
  const _OwnerProfile();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
      children: [
        UdCard(
          tone: UdCardTone.navy,
          child: Column(
            children: [
              const UdIconTile(
                icon: Icons.apartment_rounded,
                tone: UdIconTone.lime,
                size: UdIconTileSize.lg,
              ),
              const SizedBox(height: 14),
              Text(
                'Hotel mode',
                style: AppType.h2.copyWith(color: AppText.onInk),
              ),
              const SizedBox(height: 4),
              Text(
                controller.currentUserPhone,
                style: AppType.small.copyWith(color: AppText.onInkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        UdButton.primary(
          label: 'Switch to Customer mode',
          icon: Icons.person_rounded,
          onPressed: () => controller.switchMode(UserMode.customer),
        ),
        const SizedBox(height: 10),
        UdButton.outline(
          label: 'Switch to Driver mode',
          icon: Icons.drive_eta_rounded,
          onPressed: () => controller.switchMode(UserMode.driver),
        ),
      ],
    );
  }
}
