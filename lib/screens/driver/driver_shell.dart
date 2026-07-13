import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import 'driver_earnings_screen.dart';
import 'driver_home_screen.dart';
import 'driver_packages_screen.dart';
import 'driver_profile_screen.dart';
import 'driver_requests_screen.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;

  final _screens = const [
    DriverHomeScreen(),
    DriverRequestsScreen(),
    DriverPackagesScreen(),
    DriverEarningsScreen(),
    DriverProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: S.of(context, 'home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_active_outlined),
            selectedIcon: const Icon(Icons.notifications_active_rounded),
            label: S.of(context, 'requests'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.card_travel_outlined),
            selectedIcon: const Icon(Icons.card_travel_rounded),
            label: S.of(context, 'packages'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
            label: S.of(context, 'earnings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: S.of(context, 'profile'),
          ),
        ],
      ),
    );
  }
}
