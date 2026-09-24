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
import '../core/widgets/steering_wheel_icon.dart';
import 'settings/cache_reset_screen.dart';
import 'driver/driver_documents_screen.dart';
import 'driver/onboarding/driver_vehicle_type_screen.dart';
import 'driver/onboarding/driver_verification_status_screen.dart';
import 'driver/driver_wallet_screen.dart';
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

  /// Where back goes, per mode.
  ///
  /// This shell shows about forty-five screens by swapping the Scaffold body,
  /// not by pushing routes, so the Navigator only ever holds one route. Without
  /// a history of its own, the system back gesture found nothing to pop and
  /// handed the event to the platform, which closed the app - from any screen,
  /// however deep the customer felt they were. These two lists are that
  /// history; PopScope below turns them into ordinary back behaviour.
  final List<String> _customerHistory = <String>[];
  final List<String> _driverHistory = <String>[];

  /// Needed to tell whether the drawer is open when back is pressed.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Anything deeper than this is old navigation the customer will never use,
  /// and an unbounded list is a slow leak on a long session.
  static const int _maxHistory = 24;

  /// The bottom-navigation destinations, per mode.
  ///
  /// Switching between these is not "going deeper", so it does not build
  /// history: on Android, back from a bottom-navigation root leaves the app.
  /// Treating tab taps as history meant Home -> Explore -> Home -> Explore
  /// needed four back presses to escape.
  static const Set<String> _customerRoots = {
    'home',
    'explore',
    'nearMe',
    'profile',
  };
  // Exactly the keys in _bottomNavigation's `values` list. Keep the two in
  // step: a key here that is not a tab would silently wipe the history.
  static const Set<String> _driverRoots = {
    'dashboard',
    'requests',
    'driverPackages',
    'earnings',
    'driverProfile',
  };

  void _goToCustomer(String page) {
    if (page == _customerPage) return;
    setState(() {
      if (_customerRoots.contains(page)) {
        _customerHistory.clear();
      } else {
        _customerHistory
          ..remove(_customerPage)
          ..add(_customerPage);
        if (_customerHistory.length > _maxHistory) _customerHistory.removeAt(0);
      }
      _customerPage = page;
    });
  }

  void _goToDriver(String page) {
    if (page == _driverPage) return;
    setState(() {
      if (_driverRoots.contains(page)) {
        _driverHistory.clear();
      } else {
        _driverHistory
          ..remove(_driverPage)
          ..add(_driverPage);
        if (_driverHistory.length > _maxHistory) _driverHistory.removeAt(0);
      }
      _driverPage = page;
    });
  }

  bool _canGoBack(bool driver) =>
      (driver ? _driverHistory : _customerHistory).isNotEmpty;

  void _goBack(bool driver) {
    final history = driver ? _driverHistory : _customerHistory;
    if (history.isEmpty) return;
    setState(() {
      final previous = history.removeLast();
      if (driver) {
        _driverPage = previous;
      } else {
        _customerPage = previous;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    if (controller.mode == UserMode.hotel) {
      return const HotelOwnerShell();
    }
    final driver = controller.mode == UserMode.driver;
    final driverNeedsVerification = driver && !controller.driverApproved;

    // A driver who has already sent their registration sees where it stands,
    // not the list they started from.
    //
    // This was the bug behind "no status shows until I reopen the app": an
    // unapproved driver was sent to the chooser every time, whether they had
    // submitted an hour ago or never started. Submitting changed nothing on
    // screen, so there was nothing to come back to.
    final registrationSent = const {
      'Submitted',
      'PendingReview',
      'UnderReview',
      'ChangesRequired',
      'Rejected',
    }.contains(controller.driverVerificationStatus);

    final pageKey = driverNeedsVerification ? 'driverVerification' : (driver ? _driverPage : _customerPage);
    final page = driverNeedsVerification
        ? (registrationSent
            ? const DriverVerificationStatusScreen()
            : const DriverVehicleTypeScreen())
        : (driver ? _driverContent(pageKey) : _customerBody(pageKey));
    final title = driverNeedsVerification
        ? (controller.locale.languageCode == 'ur' ? 'ڈرائیور کی تصدیق' : 'Driver verification')
        : _titleFor(pageKey, driver);
    final customerHome = !driver && pageKey == 'home';
    final driverHome = driver && pageKey == 'dashboard';

    // The verification gate replaces the page regardless of _driverPage, so
    // going "back" there would swap a screen the driver cannot see and remove
    // their only route to the drawer.
    final canGoBack = !driverNeedsVerification && _canGoBack(driver);

    // canPop is false only while this shell has somewhere of its own to go.
    // On a root page it stays true, so back still leaves the app the way the
    // platform expects rather than trapping the customer inside it.
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // An open drawer is a local history entry on this same route, but
        // PopScope is consulted first, so without this back would navigate
        // underneath a drawer that stays on screen.
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          Navigator.of(context).pop();
          return;
        }
        _goBack(driver);
      },
      child: Scaffold(
      key: _scaffoldKey,
      backgroundColor: customerHome ? AppColors.background : null,
      extendBody: customerHome,
      drawer: _PremiumDrawer(
        mode: controller.mode,
        current: pageKey,
        onSelected: (value) {
          Navigator.pop(context);
          if (driver) {
            _goToDriver(value);
          } else {
            _goToCustomer(value);
          }
        },
        onSwitchMode: () async {
          Navigator.pop(context);
          final newMode = driver ? UserMode.customer : UserMode.driver;
          await controller.switchMode(newMode);
          if (mounted) {
            setState(() {
              _customerHistory.clear();
              _driverHistory.clear();
              // Not just the history: leaving the page too would strand the
              // customer on a deep screen with nothing behind it, so one back
              // press would exit the app.
              _customerPage = 'home';
              _driverPage = 'dashboard';
            });
          }
        },
      ),
      appBar: customerHome ? null : AppBar(
        titleSpacing: 4,
        // A back arrow when this shell has history, otherwise nothing, which
        // lets Scaffold insert the drawer's hamburger as before. Previously
        // there was no leading at all, so every one of these pages showed a
        // hamburger and offered no way back.
        // A back arrow only where there is somewhere to go back to. On a root
        // page leading stays null so Scaffold inserts the drawer's hamburger —
        // the drawer is the only route to Settings, Wallet and Switch mode, so
        // replacing it everywhere would hide them.
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _goBack(driver),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              )
            : null,
        // Just the name, at ordinary weight.
        //
        // "Good evening, Waseem" in 900-weight ran out of room on a phone and
        // truncated to "Good evening, Was…", which is a greeting that has
        // stopped greeting anybody. The time of day is not information, and a
        // heavy title makes every screen open with a shout.
        title: (customerHome || driverHome)
            ? Text(
                _firstName(controller.currentUserName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              )
            : Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
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
                onTap: () {
                  if (driverHome) {
                    _goToDriver('driverProfile');
                  } else {
                    _goToCustomer('profile');
                  }
                },
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
      ),
    );
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
      onDestinationSelected: (value) => _goToDriver(values[value]),
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
            onTap: () => _goToCustomer(key),
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
        'home' => CustomerHomeScreen(
            onNavigate: _customerNavigate,
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
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
        // The customer drawer has always offered "Clear cached data", but this
        // switch had no case for it, so the entry dropped through to the
        // default and quietly reopened Home. The driver side had the case.
        'refresh' => const CacheResetScreen(),
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
        'refresh' => const CacheResetScreen(),
        'driverDocuments' => const DriverDocumentsScreen(),
        'driverWallet' => const DriverWalletScreen(),
        // The four-step sign-up replaces the old single-page form.
        //
        // That one asked for four photographs and nothing else on one screen,
        // and people abandoned it. Same work, split into four subjects with a
        // progress bar, so it looks finishable.
        'documents' => const DriverVehicleTypeScreen(),
        'availability' => const DriverAvailabilityScreen(),
        'reviews' => const DriverReviewsScreen(),
        'help' => const HelpGuideScreen(driverMode: true),
        'support' => const SupportScreen(),
        'settings' => const SettingsScreen(),
        'driverProfile' => DriverProfileScreen(onNavigate: _driverNavigate),
        _ => DriverHomeScreen(onNavigate: _driverNavigate),
      };

  void _customerNavigate(String page) => _goToCustomer(page);
  void _driverNavigate(String page) => _goToDriver(page);
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
    // White, like every other surface now.
    //
    // This was `AppColors.surface`, which used to be a dark teal panel — and
    // when the palette flipped, the surface went white while every ink inside
    // the drawer stayed the white it had been chosen to be. White on white:
    // the menu was there and unreadable.
    const drawerColor = AppColors.background;
    final lime = AppColors.secondary;

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
                      backgroundColor: AppTint.brand,
                      child: Text(
                        _initials(controller.currentUserName),
                        style: const TextStyle(
                          color: AppText.primary,
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
                              color: AppText.primary,
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
                                style: const TextStyle(color: AppText.secondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppText.secondary),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: AppColors.border),
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
                        selectedTileColor: AppTint.brand,
                        iconColor: AppText.secondary,
                        // Near-black on white, and the accent when selected.
                        textColor: AppText.primary,
                        selectedColor: AppColors.secondary,
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
                    // A steering wheel for Driver mode, a passenger for
                    // Customer mode. The two modes are the same app wearing a
                    // different hat, and an icon says which hat faster than the
                    // words underneath it do.
                    child: FilledButton.icon(
                      onPressed: onSwitchMode,
                      style: FilledButton.styleFrom(
                        backgroundColor: lime,
                        foregroundColor: const Color(0xFF101310),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: driver
                          ? const Icon(Icons.person_rounded, size: 22)
                          : const SteeringWheelIcon(
                              size: 22,
                              color: Color(0xFF101310),
                            ),
                      label: Text(
                        driver ? 'Customer mode' : 'Driver mode',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    // Confirmed. Logout sits directly under the menu items, so
                    // a mis-tap signed the customer straight out and they had
                    // to wait for another code to get back in.
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Log out?'),
                          content: const Text(
                            'You will need to verify your phone number again '
                            'to sign back in.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Stay signed in'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text(
                                'Log out',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      navigator.pop();
                      await controller.logout();
                    },
                    icon: const Icon(Icons.logout_rounded, color: AppText.secondary, size: 19),
                    label: const Text('Logout', style: TextStyle(color: AppText.secondary)),
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
        // 'home' IS where a ride is booked, so the old label was not wrong —
        // but it read as a separate screen. Named for the screen it opens.
        //
        // Deliberately not adding a "Book a ride" entry for 'bookRide': that
        // key opens TourismBookingScreen, an advance tour form that defaults
        // to per-seat three days out and picks its vehicle from a hardcoded
        // demo list. Nor an "Active ride" entry for 'liveTracking', which
        // renders AppController's demo LiveTripSession — a trip called
        // "TR-2048" with a driver named Adeel Khan that no customer booked.
        // A running ride is reachable from Home's banner and from Trips, both
        // of which show the real one.
        ('home', Icons.home_outlined, 'Home'),
        ('trips', Icons.history_rounded, 'Request history'),
        ('explore', Icons.landscape_outlined, 'Explore Kashmir'),
        ('packages', Icons.luggage_outlined, 'Tour packages'),
        ('saved', Icons.bookmark_border_rounded, 'Saved places'),
        ('myBusiness', Icons.storefront_outlined, 'My business'),
        ('notifications', Icons.notifications_none_rounded, 'Notifications'),
        ('safety', Icons.health_and_safety_outlined, 'Safety'),
        ('settings', Icons.settings_outlined, 'Settings'),
        ('refresh', Icons.cleaning_services_outlined, 'Clear cached data'),
        ('help', Icons.info_outline_rounded, 'Help'),
        ('support', Icons.chat_bubble_outline_rounded, 'Support'),
      ];

  List<(String, IconData, String)> _driverEntries(BuildContext context) => [
        if (!AppControllerScope.of(context).driverApproved)
          ('driverVerification', Icons.verified_user_rounded, 'Driver verification'),
        // Eight, down from thirteen.
        //
        // Removed because they duplicated something already on screen: Ride
        // requests and Active trip are both on the dashboard, and Reviews moved
        // into Earnings. Create route folded into My routes & tours, and Help
        // into Support — a driver with a problem opens one of them, not both,
        // and having to choose is itself a small obstacle.
        //
        // A menu is a list of places you cannot already see. Everything else on
        // it is noise a driver has to read past.
        ('dashboard', Icons.dashboard_outlined, 'Dashboard'),
        ('driverWallet', Icons.account_balance_wallet_rounded, 'Wallet'),
        ('earnings', Icons.payments_outlined, 'Earnings & reviews'),
        ('vehicles', Icons.directions_car_outlined, 'Vehicles'),
        ('driverDocuments', Icons.badge_outlined, 'My documents'),
        ('driverPackages', Icons.luggage_outlined, 'My routes & tours'),
        ('settings', Icons.settings_outlined, 'Settings'),
        ('support', Icons.chat_bubble_outline_rounded, 'Help & support'),
      ];
}

