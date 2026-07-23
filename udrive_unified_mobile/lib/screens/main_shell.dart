import 'package:flutter/material.dart';
import '../core/localization/app_strings.dart';
import '../core/state/app_controller.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../data/models.dart';
import 'common/common_pages.dart';
import 'customer/customer_home_screen.dart';
import 'customer/customer_pages.dart';
import 'customer/ride_booking_screen.dart';
import 'driver/driver_home_screen.dart';
import 'driver/driver_pages.dart';
import 'driver/vehicle_registration_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  String _customerPage = 'home';
  String _driverPage = 'dashboard';

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final driver = controller.mode == UserMode.driver;
    final pageKey = driver ? _driverPage : _customerPage;
    final page = driver ? _driverContent(pageKey) : _customerContent(pageKey);
    final title = _titleFor(pageKey, driver);

    return Scaffold(
      drawer: _PremiumDrawer(
        mode: controller.mode,
        current: pageKey,
        onSelected: (value) {
          Navigator.pop(context);
          setState(() {
            if (driver) {
              _driverPage = value;
            } else {
              _customerPage = value;
            }
          });
        },
        onSwitchMode: () async {
          Navigator.pop(context);
          final newMode = driver ? UserMode.customer : UserMode.driver;
          await controller.switchMode(newMode);
          if (mounted) setState(() {});
        },
      ),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        actions: [
          IconButton(
            tooltip: context.tr('notifications'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(context.tr('notifications'))), body: const NotificationsScreen()))),
            icon: Badge(
              label: const Text('2'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: KeyedSubtree(key: ValueKey('${controller.mode.name}-$pageKey'), child: page),
      ),
      bottomNavigationBar: _bottomNavigation(driver),
    );
  }

  Widget _bottomNavigation(bool driver) {
    final current = driver ? _driverPage : _customerPage;
    final values = driver
        ? const ['dashboard', 'requests', 'driverPackages', 'earnings', 'driverProfile']
        : const ['home', 'explore', 'trips', 'wallet', 'profile'];
    var index = values.indexOf(current);
    if (index < 0) index = 0;

    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() {
        if (driver) {
          _driverPage = values[value];
        } else {
          _customerPage = values[value];
        }
      }),
      destinations: driver
          ? [
              NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard_rounded), label: context.tr('home')),
              NavigationDestination(icon: const Icon(Icons.notifications_active_outlined), selectedIcon: const Icon(Icons.notifications_active_rounded), label: context.tr('rideRequests')),
              NavigationDestination(icon: const Icon(Icons.luggage_outlined), selectedIcon: const Icon(Icons.luggage_rounded), label: context.tr('packages')),
              NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments_rounded), label: context.tr('earnings')),
              NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.tr('profile')),
            ]
          : [
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: context.tr('home')),
              NavigationDestination(icon: const Icon(Icons.explore_outlined), selectedIcon: const Icon(Icons.explore_rounded), label: context.tr('explore')),
              NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route_rounded), label: context.tr('trips')),
              NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet_rounded), label: context.tr('wallet')),
              NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.tr('profile')),
            ],
    );
  }

  String _titleFor(String key, bool driver) {
    final mapping = <String, String>{
      'home': 'home',
      'bookRide': 'bookRide',
      'explore': 'explore',
      'packages': 'packages',
      'trips': 'trips',
      'wallet': 'wallet',
      'saved': 'savedPlaces',
      'safety': 'safety',
      'notifications': 'notifications',
      'support': 'support',
      'settings': 'settings',
      'profile': 'profile',
      'dashboard': 'driverDashboard',
      'requests': 'rideRequests',
      'activeTrip': 'activeTrip',
      'driverPackages': 'myPackages',
      'createPackage': 'createPackage',
      'earnings': 'earnings',
      'payouts': 'payouts',
      'vehicles': 'vehicles',
      'documents': 'documents',
      'availability': 'availability',
      'reviews': 'reviews',
      'driverProfile': 'profile',
    };
    return context.tr(mapping[key] ?? (driver ? 'driverDashboard' : 'home'));
  }

  Widget _customerContent(String key) => switch (key) {
        'home' => CustomerHomeScreen(onNavigate: _customerNavigate),
        'bookRide' => const RideBookingScreen(),
        'explore' => const ExploreScreen(),
        'packages' => const PackagesScreen(),
        'trips' => const TripsScreen(),
        'wallet' => const WalletScreen(),
        'saved' => const SavedPlacesScreen(),
        'safety' => const SafetyScreen(),
        'notifications' => const NotificationsScreen(),
        'support' => const SupportScreen(),
        'settings' => const SettingsScreen(),
        'profile' => ProfileScreen(onNavigate: _customerNavigate),
        _ => CustomerHomeScreen(onNavigate: _customerNavigate),
      };

  Widget _driverContent(String key) => switch (key) {
        'dashboard' => DriverHomeScreen(onNavigate: _driverNavigate),
        'requests' => const DriverRequestsScreen(),
        'activeTrip' => const ActiveDriverTripScreen(),
        'driverPackages' => DriverPackagesScreen(onNavigate: _driverNavigate),
        'createPackage' => const CreatePackageScreen(),
        'earnings' => const DriverEarningsScreen(),
        'payouts' => const DriverWalletScreen(),
        'vehicles' => const VehicleListScreen(),
        'documents' => const DriverDocumentsScreen(),
        'availability' => const DriverAvailabilityScreen(),
        'reviews' => const DriverReviewsScreen(),
        'support' => const SupportScreen(),
        'settings' => const SettingsScreen(),
        'driverProfile' => DriverProfileScreen(onNavigate: _driverNavigate),
        _ => DriverHomeScreen(onNavigate: _driverNavigate),
      };

  void _customerNavigate(String page) => setState(() => _customerPage = page);
  void _driverNavigate(String page) => setState(() => _driverPage = page);
}

class _PremiumDrawer extends StatelessWidget {
  const _PremiumDrawer({required this.mode, required this.current, required this.onSelected, required this.onSwitchMode});
  final UserMode mode;
  final String current;
  final ValueChanged<String> onSelected;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final driver = mode == UserMode.driver;
    final entries = driver ? _driverEntries(context) : _customerEntries(context);
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(290, 350).toDouble(),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(30))),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF063F32), AppColors.primary]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UDriveWordmark(light: true, compact: true),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const CircleAvatar(radius: 27, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, color: AppColors.primaryDark, size: 30)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Shahzad Ahmad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 3),
                            Text(driver ? context.tr('driverMode') : context.tr('customerMode'), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const Icon(Icons.verified_rounded, color: AppColors.accent),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: onSwitchMode,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(15)),
                      child: Row(
                        children: [
                          Icon(driver ? Icons.person_rounded : Icons.drive_eta_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 9),
                          Expanded(child: Text(driver ? context.tr('switchCustomer') : context.tr('switchDriver'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900))),
                          const Icon(Icons.swap_horiz_rounded, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: ListTile(
                        selected: current == entry.$1,
                        selectedTileColor: AppColors.primary.withValues(alpha: .1),
                        selectedColor: AppColors.primaryDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        leading: Icon(entry.$2, size: 22),
                        title: Text(entry.$3, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        trailing: current == entry.$1 ? const Icon(Icons.circle, size: 7, color: AppColors.primary) : null,
                        onTap: () => onSelected(entry.$1),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await AppControllerScope.of(context).logout();
                },
                icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                label: Text(context.tr('logout'), style: const TextStyle(color: AppColors.danger)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, IconData, String)> _customerEntries(BuildContext context) => [
        ('home', Icons.home_rounded, context.tr('home')),
        ('bookRide', Icons.local_taxi_rounded, context.tr('bookRide')),
        ('explore', Icons.explore_rounded, context.tr('explore')),
        ('packages', Icons.luggage_rounded, context.tr('packages')),
        ('trips', Icons.route_rounded, context.tr('trips')),
        ('wallet', Icons.account_balance_wallet_rounded, context.tr('wallet')),
        ('saved', Icons.bookmark_rounded, context.tr('savedPlaces')),
        ('safety', Icons.health_and_safety_rounded, context.tr('safety')),
        ('notifications', Icons.notifications_rounded, context.tr('notifications')),
        ('support', Icons.support_agent_rounded, context.tr('support')),
        ('settings', Icons.settings_rounded, context.tr('settings')),
        ('profile', Icons.person_rounded, context.tr('profile')),
      ];

  List<(String, IconData, String)> _driverEntries(BuildContext context) => [
        ('dashboard', Icons.dashboard_rounded, context.tr('driverDashboard')),
        ('requests', Icons.notifications_active_rounded, context.tr('rideRequests')),
        ('activeTrip', Icons.navigation_rounded, context.tr('activeTrip')),
        ('driverPackages', Icons.luggage_rounded, context.tr('myPackages')),
        ('createPackage', Icons.add_box_rounded, context.tr('createPackage')),
        ('earnings', Icons.insights_rounded, context.tr('earnings')),
        ('payouts', Icons.account_balance_wallet_rounded, context.tr('payouts')),
        ('vehicles', Icons.directions_car_filled_rounded, context.tr('vehicles')),
        ('documents', Icons.fact_check_rounded, context.tr('documents')),
        ('availability', Icons.calendar_month_rounded, context.tr('availability')),
        ('reviews', Icons.star_rounded, context.tr('reviews')),
        ('support', Icons.support_agent_rounded, context.tr('support')),
        ('settings', Icons.settings_rounded, context.tr('settings')),
        ('driverProfile', Icons.person_rounded, context.tr('profile')),
      ];
}
