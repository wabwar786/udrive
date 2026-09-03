import 'package:flutter/material.dart';
import '../core/localization/app_strings.dart';
import '../core/state/app_controller.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/brand.dart';
import '../data/models.dart';
import 'common/common_pages.dart';
import 'common/help_guide_screen.dart';
import 'customer/customer_home_screen.dart';
import 'customer/customer_pages.dart';
import 'customer/family_tour_planner_screen.dart';
import 'customer/join_tour_screen.dart';
import 'customer/live_bookings_screen.dart';
import 'customer/live_explore_screen.dart';
import 'customer/near_me_screen.dart';
import 'business_owner/business_owner_dashboard.dart';
import 'customer/live_packages_screen.dart';
import 'customer/live_tour_interest_screen.dart';
import 'driver/live_create_package_screen.dart';
import 'driver/live_driver_packages_screen.dart';
import 'driver/live_driver_package_bookings_screen.dart';
import 'driver/tour_operations_screen.dart';
import 'driver/live_driver_requests_screen.dart';
import 'customer/tourism_booking_screen.dart';
import 'driver/driver_home_screen.dart';
import 'driver/driver_earnings_screen.dart';
import 'driver/driver_pages.dart' hide DriverEarningsScreen;
import 'driver/advanced_package_screen.dart';
import 'driver/driver_tourism_tools.dart';
import 'driver/vehicle_registration_screen.dart';
import 'driver/driver_documents_screen.dart';
import 'driver/live_vehicle_list_screen.dart';
import 'driver/onboarding/driver_verification_screen.dart';
import 'maps/live_tracking_screen.dart';
import 'safety/safety_hub_screen.dart';
import 'safety/customer_sos_sheet.dart';
import 'hotel_owner/hotel_owner_shell.dart';

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
    if (controller.mode == UserMode.hotel) {
      return const HotelOwnerShell();
    }
    final driver = controller.mode == UserMode.driver;
    final driverNeedsVerification = driver && !controller.driverApproved;
    final pageKey = driverNeedsVerification ? 'driverVerification' : (driver ? _driverPage : _customerPage);
    final page = driverNeedsVerification
        ? const DriverVerificationScreen()
        : (driver ? _driverContent(pageKey) : _customerBody(pageKey));
    final title = driverNeedsVerification
        ? (controller.locale.languageCode == 'ur' ? 'ڈرائیور کی تصدیق' : 'Driver verification')
        : _titleFor(pageKey, driver);
    final customerHome = !driver && pageKey == 'home';
    final driverHome = driver && pageKey == 'dashboard';

    return Scaffold(
      backgroundColor: customerHome ? AppColors.background : null,
      extendBody: customerHome,
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
      appBar: customerHome ? null : AppBar(
        titleSpacing: 4,
        title: (customerHome || driverHome)
            ? Text(
                '${_greeting()}, ${_firstName(controller.currentUserName)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              )
            : Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
        actions: [
          if (driverHome)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    controller.driverOnline
                        ? Icons.wifi_tethering_rounded
                        : Icons.wifi_off_rounded,
                    size: 17,
                    color: controller.driverOnline
                        ? AppColors.success
                        : AppColors.muted,
                  ),
                  Switch.adaptive(
                    value: controller.driverOnline,
                    onChanged: controller.toggleDriverOnline,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: context.tr('notifications'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(context.tr('notifications'))),
                  body: const NotificationsScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          if (customerHome || driverHome)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => setState(() {
                  if (driverHome) {
                    _driverPage = 'driverProfile';
                  } else {
                    _customerPage = 'profile';
                  }
                }),
                borderRadius: BorderRadius.circular(999),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFFE2F7EF),
                  child: Text(
                    _initials(controller.currentUserName),
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: KeyedSubtree(key: ValueKey('${controller.mode.name}-$pageKey'), child: page),
      ),
      bottomNavigationBar: driverNeedsVerification || !driver ? null : _bottomNavigation(driver),
    );
  }

  String _greeting() {
    final pakistanNow =
        DateTime.now().toUtc().add(const Duration(hours: 5));
    if (pakistanNow.hour < 12) return 'Good morning';
    if (pakistanNow.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'Udrive User';
    return clean.split(RegExp(r'\s+')).first;
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'U';
    return parts.map((part) => part[0].toUpperCase()).join();
  }

  Widget _bottomNavigation(bool driver) {
    if (!driver) return _customerBottomNavigation();

    final values = const ['dashboard', 'requests', 'driverPackages', 'earnings', 'driverProfile'];
    var index = values.indexOf(_driverPage);
    if (index < 0) index = 0;

    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => _driverPage = values[value]),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard_rounded), label: context.tr('home')),
        NavigationDestination(icon: const Icon(Icons.notifications_active_outlined), selectedIcon: const Icon(Icons.notifications_active_rounded), label: context.tr('rideRequests')),
        NavigationDestination(icon: const Icon(Icons.luggage_outlined), selectedIcon: const Icon(Icons.luggage_rounded), label: context.tr('packages')),
        NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments_rounded), label: context.tr('earnings')),
        NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.tr('profile')),
      ],
    );
  }

  /// Redesigned customer bar: Home · Explore · (SOS) · Near me · Profile.
  ///
  /// No border-top — a soft upward shadow instead, per the handoff. The active
  /// tab gets a pill background behind icon and label; inactive tabs are plain.
  /// SOS stays in the centre slot rather than moving onto the map band.
  Widget _customerBottomNavigation() {
    Widget item(String key, IconData icon, IconData activeIcon, String label) {
      final selected = _customerPage == key;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: () => setState(() => _customerPage = key),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 58,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected ? AppTint.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? activeIcon : icon,
                        size: 20,
                        color: selected ? AppColors.secondary : AppText.disabled,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? AppColors.secondary : AppText.disabled,
                          fontSize: 9,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(13, 5, 13, 9),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(23),
            boxShadow: AppShadows.navBar,
          ),
          child: Row(
            children: [
              item('home', Icons.home_outlined, Icons.home_rounded, 'Home'),
              item('explore', Icons.explore_outlined, Icons.explore_rounded,
                  'Explore'),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'Emergency SOS',
                    child: InkWell(
                      onTap: () => CustomerSosSheet.show(context),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.danger.withValues(alpha: .30),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sos_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
              item('nearMe', Icons.location_on_outlined,
                  Icons.location_on_rounded, 'Near me'),
              item('profile', Icons.person_outline_rounded,
                  Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(String key, bool driver) {
    final mapping = <String, String>{
      'home': 'home',
      'bookRide': 'bookRide',
      'joinTour': 'joinTour',
      'familyPlanner': 'familyTourPlanner',
      'explore': 'explore',
      'nearMe': 'nearMe',
      'myBusiness': 'myBusiness',
      'packages': 'packages',
      'trips': 'trips',
      'saved': 'savedPlaces',
      'safety': 'safety',
      'liveTracking': 'liveTracking',
      'trustedContacts': 'trustedContacts',
      'tourGuardian': 'tourGuardian',
      'offlineCard': 'offlineTravelCard',
      'notifications': 'notifications',
      'help': 'help',
      'support': 'support',
      'settings': 'settings',
      'profile': 'profile',
      'dashboard': 'driverDashboard',
      'requests': 'rideRequests',
      'activeTrip': 'activeTrip',
      'driverPackages': 'myPackages',
      'createPackage': 'createPackage',
      'packageBookings': 'packageBookings',
      'vehicleSuitability': 'vehicleSuitability',
      'roadReports': 'roadReports',
      'driverSafety': 'safety',
      'driverLiveTracking': 'liveTracking',
      'earnings': 'earnings',
      'payouts': 'payouts',
      'vehicles': 'vehicles',
      'documents': 'documents',
      'availability': 'availability',
      'reviews': 'reviews',
      'driverProfile': 'profile',
      'driverVerification': 'documents',
    };
    if (key == 'help') {
      return AppControllerScope.of(context).locale.languageCode == 'ur' ? 'مدد / استعمال کا طریقہ' : 'Help / How to use';
    }
    return context.tr(mapping[key] ?? (driver ? 'driverDashboard' : 'home'));
  }

  /// Bottom-nav destinations, kept mounted so their state survives tab
  /// switches. Home holds a Google map, and Google charges per map load — a
  /// fresh build on every tab change would be a fresh charge each time.
  static const _keptAliveKeys = ['home', 'explore', 'nearMe', 'profile'];

  Widget _customerBody(String key) {
    final index = _keptAliveKeys.indexOf(key);
    if (index < 0) return _customerContent(key);

    return IndexedStack(
      index: index,
      children: [
        for (final alive in _keptAliveKeys)
          // Offstage children still build, but their tickers and timers are
          // paused by TickerMode, so a backgrounded Home stops polling.
          TickerMode(
            enabled: alive == key,
            child: _customerContent(alive),
          ),
      ],
    );
  }

  Widget _customerContent(String key) => switch (key) {
        'home' => CustomerHomeScreen(onNavigate: _customerNavigate),
        'bookRide' => const TourismBookingScreen(),
        'joinTour' => const LiveTourInterestScreen(),
        'familyPlanner' => const FamilyTourPlannerScreen(),
        'explore' => const LiveExploreScreen(),
        'nearMe' => const NearMeScreen(),
        'myBusiness' => const BusinessOwnerDashboard(),
        'packages' => const LivePackagesScreen(),
        'trips' => const LiveBookingsScreen(),
        'saved' => const SavedPlacesScreen(),
        'safety' => const SafetyHubScreen(),
        'liveTracking' => const LiveTrackingScreen(),
        'trustedContacts' => const SafetyHubScreen(),
        'tourGuardian' => const SafetyHubScreen(),
        'offlineCard' => const SafetyHubScreen(),
        'notifications' => const NotificationsScreen(),
        'help' => const HelpGuideScreen(driverMode: false),
        'support' => const SupportScreen(),
        'settings' => const SettingsScreen(),
        'profile' => ProfileScreen(onNavigate: _customerNavigate),
        _ => CustomerHomeScreen(onNavigate: _customerNavigate),
      };

  Widget _driverContent(String key) => switch (key) {
        'driverVerification' => const DriverVerificationScreen(),
        'dashboard' => DriverHomeScreen(onNavigate: _driverNavigate),
        'requests' => const LiveDriverRequestsScreen(),
        'activeTrip' => const ActiveDriverTripScreen(),
        'driverPackages' => const LiveDriverPackagesScreen(),
        'createPackage' => const LiveCreatePackageScreen(),
        'packageBookings' => const TourOperationsScreen(),
        'vehicleSuitability' => const VehicleSuitabilityScreen(),
        'roadReports' => const DriverRoadReportsScreen(),
        'driverSafety' => const SafetyHubScreen(),
        'driverLiveTracking' => const LiveTrackingScreen(),
        'earnings' => const DriverEarningsScreen(),
        'payouts' => const DriverEarningsScreen(),
        'vehicles' => const LiveVehicleListScreen(),
        'driverDocuments' => const DriverDocumentsScreen(),
        'documents' => const DriverVerificationScreen(),
        'availability' => const DriverAvailabilityScreen(),
        'reviews' => const DriverReviewsScreen(),
        'help' => const HelpGuideScreen(driverMode: true),
        'support' => const SupportScreen(),
        'settings' => const SettingsScreen(),
        'driverProfile' => DriverProfileScreen(onNavigate: _driverNavigate),
        _ => DriverHomeScreen(onNavigate: _driverNavigate),
      };

  void _customerNavigate(String page) => setState(() => _customerPage = page);
  void _driverNavigate(String page) => setState(() => _driverPage = page);
}

class _PremiumDrawer extends StatelessWidget {
  const _PremiumDrawer({
    required this.mode,
    required this.current,
    required this.onSelected,
    required this.onSwitchMode,
  });

  final UserMode mode;
  final String current;
  final ValueChanged<String> onSelected;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    if (controller.mode == UserMode.hotel) {
      return const HotelOwnerShell();
    }
    final driver = mode == UserMode.driver;
    final entries = driver ? _driverEntries(context) : _customerEntries(context);
    const drawerColor = AppColors.surface;
    const lime = AppColors.secondary;

    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(300, 360).toDouble(),
      backgroundColor: drawerColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(0)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 18, 18),
              child: InkWell(
                onTap: () => onSelected(driver ? 'driverProfile' : 'profile'),
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white12,
                      child: Text(
                        _initials(controller.currentUserName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.currentUserName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFFFB000), size: 17),
                              const SizedBox(width: 4),
                              Text(
                                driver ? 'Driver account' : 'Customer account',
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: ListTile(
                        minLeadingWidth: 28,
                        selected: current == entry.$1,
                        selectedTileColor: Colors.white24,
                        iconColor: Colors.white54,
                        textColor: Colors.white,
                        selectedColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
                        leading: Icon(entry.$2, size: 24),
                        title: Text(
                          entry.$3,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        onTap: () => onSelected(entry.$1),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: onSwitchMode,
                      style: FilledButton.styleFrom(
                        backgroundColor: lime,
                        foregroundColor: const Color(0xFF101310),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        driver ? 'Customer mode' : 'Driver mode',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await controller.logout();
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.white60, size: 19),
                    label: const Text('Logout', style: TextStyle(color: Colors.white60)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2);
    final value = parts.map((e) => e[0].toUpperCase()).join();
    return value.isEmpty ? 'U' : value;
  }

  List<(String, IconData, String)> _customerEntries(BuildContext context) => [
        ('home', Icons.directions_car_outlined, 'Book a ride'),
        ('trips', Icons.history_rounded, 'Request history'),
        ('explore', Icons.landscape_outlined, 'Explore Kashmir'),
        ('packages', Icons.luggage_outlined, 'Tour packages'),
        ('saved', Icons.bookmark_border_rounded, 'Saved places'),
        ('myBusiness', Icons.storefront_outlined, 'My business'),
        ('notifications', Icons.notifications_none_rounded, 'Notifications'),
        ('safety', Icons.health_and_safety_outlined, 'Safety'),
        ('settings', Icons.settings_outlined, 'Settings'),
        ('help', Icons.info_outline_rounded, 'Help'),
        ('support', Icons.chat_bubble_outline_rounded, 'Support'),
      ];

  List<(String, IconData, String)> _driverEntries(BuildContext context) => [
        if (!AppControllerScope.of(context).driverApproved)
          ('driverVerification', Icons.verified_user_rounded, 'Driver verification'),
        ('dashboard', Icons.dashboard_outlined, 'Dashboard'),
        ('requests', Icons.notifications_active_outlined, 'Ride requests'),
        ('activeTrip', Icons.navigation_outlined, 'Active trip'),
        ('driverPackages', Icons.luggage_outlined, 'My routes & tours'),
        ('createPackage', Icons.add_box_outlined, 'Create route or tour'),
        ('earnings', Icons.account_balance_wallet_outlined, 'Earnings'),
        ('vehicles', Icons.directions_car_outlined, 'Vehicles'),
        ('driverDocuments', Icons.badge_outlined, 'My documents'),
        ('reviews', Icons.star_border_rounded, 'Reviews'),
        ('settings', Icons.settings_outlined, 'Settings'),
        ('help', Icons.info_outline_rounded, 'Help'),
        ('support', Icons.chat_bubble_outline_rounded, 'Support'),
      ];
}

