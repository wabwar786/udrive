import 'package:flutter/material.dart';

import '../core/localization/app_language.dart';
import '../core/theme/app_theme.dart';
import 'customer/live_explore_screen.dart';
import 'customer/live_packages_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'safety/customer_sos_sheet.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  final _screens = const [
    HomeScreen(),
    LiveExploreScreen(),
    LivePackagesScreen(),
    ProfileScreen(),
  ];

  Future<void> _sendEmergencyAlert() => CustomerSosSheet.triggerEmergency(context);
  Future<void> _openEmergencyNumbers() => CustomerSosSheet.show(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      extendBody: true,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SizedBox(
              height: 78,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE7EBEA)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withValues(alpha: .10),
                            blurRadius: 26,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _NavIcon(
                                  icon: Icons.home_outlined,
                                  selectedIcon: Icons.home_rounded,
                                  tooltip: S.of(context, 'home'),
                                  selected: _index == 0,
                                  onTap: () => setState(() => _index = 0),
                                ),
                                _NavIcon(
                                  icon: Icons.explore_outlined,
                                  selectedIcon: Icons.explore_rounded,
                                  tooltip: S.of(context, 'explore'),
                                  selected: _index == 1,
                                  onTap: () => setState(() => _index = 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 72),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _NavIcon(
                                  icon: Icons.luggage_outlined,
                                  selectedIcon: Icons.luggage_rounded,
                                  tooltip: S.of(context, 'packages'),
                                  selected: _index == 2,
                                  onTap: () => setState(() => _index = 2),
                                ),
                                _NavIcon(
                                  icon: Icons.person_outline_rounded,
                                  selectedIcon: Icons.person_rounded,
                                  tooltip: S.of(context, 'profile'),
                                  selected: _index == 3,
                                  onTap: () => setState(() => _index = 3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    child: Semantics(
                      button: true,
                      label: 'Emergency microphone. Tap to send an alert. Long press to open emergency numbers.',
                      child: GestureDetector(
                        onTap: _sendEmergencyAlert,
                        onLongPress: _openEmergencyNumbers,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFFF6868), Color(0xFFE62E3A)],
                            ),
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE62E3A).withValues(alpha: .34),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 29),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryDark : const Color(0xFFA4AAB4);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 50,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, size: 21, color: color),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 4,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
