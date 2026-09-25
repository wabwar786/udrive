import 'package:flutter/material.dart';
import '../core/localization/app_strings.dart';
import '../core/state/app_controller.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/ud_kit.dart';
import '../data/models.dart';
import 'common/common_pages.dart';
import 'common/help_guide_screen.dart';
import 'customer/customer_home_screen.dart';
import 'customer/customer_pages.dart';
// family_tour_planner_screen.dart and join_tour_screen.dart were deleted before
// release. Neither was reachable — no navigation call ever passed
// 'familyPlanner', and 'joinTour' routes to LiveTourInterestScreen — and both
// still referenced `vehicleCategories`, the invented six-category list that was
// removed from dummy_data.dart, so they no longer compiled. The planner also
// invented a "safety score out of 100" and a total cost from arithmetic on the
// user's own inputs and presented them as a recommendation.
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
import 'feedback/feedback_center_screen.dart';
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
      // Not extended under the bar any more. `extendBody` was set for a
      // floating, rounded navigation bar that never actually rendered; the v2
      // bar is solid white against the bottom edge, so anything drawn beneath
      // it is simply hidden. Home's last row would have been.
      extendBody: false,
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
      // The bar is the first child of the body rather than `Scaffold.appBar`.
      //
      // `UdTopBar` draws its own status-bar inset, and an appBar is measured by
      // its `preferredSize` before that inset exists — so in the appBar slot it
      // would be laid out 72px tall and then paint taller than its box. In the
      // body it measures itself. The one thing the appBar slot was doing for
      // free is the drawer's hamburger, which is why `leading` below is
      // explicit: without it the drawer would have no way in.
      body: Column(
        children: [
          if (!customerHome)
            _topBar(
              context: context,
              controller: controller,
              title: title,
              canGoBack: canGoBack,
              driver: driver,
              driverHome: driverHome,
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: KeyedSubtree(
                key: ValueKey('${controller.mode.name}-$pageKey'),
                child: page,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          driverNeedsVerification ? null : _bottomNavigation(driver),
      ),
    );
  }

  /// The white top bar. Everything it holds is the same as before: a back arrow
  /// where there is history, the drawer otherwise, the person's first name on a
  /// tab root and the page title elsewhere, the driver's online switch, the
  /// notifications bell and the avatar.
  Widget _topBar({
    required BuildContext context,
    required AppController controller,
    required String title,
    required bool canGoBack,
    required bool driver,
    required bool driverHome,
  }) {
    // Just the name on the driver's dashboard, the page title everywhere else.
    //
    // "Good evening, Waseem" in 900-weight ran out of room on a phone and
    // truncated to "Good evening, Was...", which is a greeting that has stopped
    // greeting anybody. The customer's Home draws no bar at all — its controls
    // float over the map.
    return UdTopBar(
      title: driverHome ? _firstName(controller.currentUserName) : title,
      // A back arrow only where there is somewhere to go back to. Everywhere
      // else the slot holds the drawer, which is the only route to Settings,
      // Wallet and Switch mode.
      leading: canGoBack
          ? UdIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => _goBack(driver),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            )
          : UdIconButton(
              icon: Icons.menu_rounded,
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            ),
      actions: [
        if (driverHome)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                controller.driverOnline
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_off_rounded,
                size: 18,
                color: controller.driverOnline
                    ? AppColors.brandInk
                    : AppText.secondary,
              ),
              const SizedBox(width: 8),
              UdSwitch(
                value: controller.driverOnline,
                onChanged: controller.toggleDriverOnline,
                semanticLabel: 'Go online',
              ),
            ],
          ),
        UdIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: context.tr('notifications'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: AppColors.background,
                body: Column(
                  children: [
                    Builder(
                      builder: (inner) => UdTopBar(
                        title: context.tr('notifications'),
                        onBack: () => Navigator.maybePop(inner),
                      ),
                    ),
                    const Expanded(child: NotificationsScreen()),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (driverHome)
          GestureDetector(
            onTap: () => _goToDriver('driverProfile'),
            behavior: HitTestBehavior.opaque,
            child: UdAvatar(
              initials: _initials(controller.currentUserName),
              size: 40,
            ),
          ),
      ],
    );
  }

  /// The driver's tabs. Exactly the five keys in [_driverRoots].
  List<UdNavDestination> _driverDestinations() => [
        UdNavDestination(
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: context.tr('home'),
        ),
        UdNavDestination(
          icon: Icons.notifications_active_outlined,
          activeIcon: Icons.notifications_active_rounded,
          label: context.tr('rideRequests'),
        ),
        UdNavDestination(
          icon: Icons.luggage_outlined,
          activeIcon: Icons.luggage_rounded,
          label: context.tr('packages'),
        ),
        UdNavDestination(
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments_rounded,
          label: context.tr('earnings'),
        ),
        UdNavDestination(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: context.tr('profile'),
        ),
      ];


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
    if (driver) {
      const values = [
        'dashboard',
        'requests',
        'driverPackages',
        'earnings',
        'driverProfile',
      ];
      var index = values.indexOf(_driverPage);
      if (index < 0) index = 0;

      return UdBottomNav(
        destinations: _driverDestinations(),
        currentIndex: index,
        onSelected: (value) => _goToDriver(values[value]),
      );
    }

    // Home . Explore . SOS . Near me . Profile.
    //
    // This bar was built and then never shown. The line that placed it read
    // `driverNeedsVerification || !driver ? null : ...`, so every customer got
    // `null` and `_customerBottomNavigation` was unreachable code -- which is
    // why Explore, Near me and Profile could only be reached through the
    // drawer. The design has this bar on every customer tab root, so it is
    // wired up now. That is a change in behaviour, not only in paint.
    //
    // SOS is a slot, not a tab: it opens the sheet and leaves the selected tab
    // where it was.
    const values = ['home', 'explore', '', 'nearMe', 'profile'];
    var index = values.indexOf(_customerPage);
    if (index < 0) index = 0;

    return UdBottomNav(
      destinations: [
        UdNavDestination(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: context.tr('home'),
        ),
        UdNavDestination(
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore_rounded,
          label: context.tr('explore'),
        ),
        UdNavDestination.sos(
          label: 'SOS',
          onTap: () => CustomerSosSheet.show(context),
        ),
        UdNavDestination(
          icon: Icons.location_on_outlined,
          activeIcon: Icons.location_on_rounded,
          label: context.tr('nearMe'),
        ),
        UdNavDestination(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: context.tr('profile'),
        ),
      ],
      currentIndex: index,
      onSelected: (value) {
        final key = values[value];
        if (key.isNotEmpty) _goToCustomer(key);
      },
    );
  }

  String _titleFor(String key, bool driver) {
    final mapping = <String, String>{
      'home': 'home',
      'bookRide': 'bookRide',
      'joinTour': 'joinTour',
      'explore': 'explore',
      'nearMe': 'nearMe',
      'myBusiness': 'myBusiness',
      'packages': 'packages',
      'trips': 'trips',
      'safety': 'safety',
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
      'driverPackages': 'myPackages',
      'createPackage': 'createPackage',
      'packageBookings': 'packageBookings',
      'vehicleSuitability': 'vehicleSuitability',
      'roadReports': 'roadReports',
      'driverSafety': 'safety',
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
        'explore' => const LiveExploreScreen(),
        'nearMe' => const NearMeScreen(),
        'myBusiness' => const BusinessOwnerDashboard(),
        'packages' => const LivePackagesScreen(),
        'trips' => const LiveBookingsScreen(),
        'safety' => const SafetyHubScreen(),
        // 'liveTracking' and 'driverLiveTracking' were routed here to a
        // screen driven by SimulatedLocationService — a moving dot with a
        // hardcoded driver phone number, +92 300 901 2204, and a "Dummy
        // driver call opened" snackbar behind it. Nothing navigated to
        // either key. Real tracking is LiveTripNavigationScreen, opened from
        // Home and from the offers screen once a booking actually exists.
        'trustedContacts' => const SafetyHubScreen(),
        'tourGuardian' => const SafetyHubScreen(),
        'offlineCard' => const SafetyHubScreen(),
        'notifications' => const NotificationsScreen(),
        'help' => const HelpGuideScreen(driverMode: false),
        // Support opens the real ratings-and-complaints centre, which lists
        // trips awaiting a rating and the cases this person has opened, and
        // can open a new one. It replaced a screen that said "Dummy chat,
        // ticket and emergency help options are active" on the customer's
        // own display and auto-replied "a demo support ticket has been
        // created" to anything typed into it.
        'support' => const FeedbackCenterScreen(),
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
        'driverPackages' => const LiveDriverPackagesScreen(),
        'createPackage' => const LiveCreatePackageScreen(),
        'packageBookings' => const TourOperationsScreen(),
        'vehicleSuitability' => const VehicleSuitabilityScreen(),
        'roadReports' => const DriverRoadReportsScreen(),
        'driverSafety' => const SafetyHubScreen(),
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
        // 'documents' comes from Driver Profile. It used to open
        // DriverVehicleTypeScreen — the "How do you want to earn?"
        // chooser from sign-up — so an already-approved driver tapping
        // "Documents" was dropped back into registration. It now opens
        // the same screen as the drawer's "My documents".
        'documents' => const DriverDocumentsScreen(),
        'availability' => const DriverAvailabilityScreen(),
        // Earnings already shows the driver's real rating, rating count and
        // recent reviews. The screen this used to open showed every driver an
        // identical hardcoded "4.9" over "846 trips", with three invented
        // passengers praising them by name.
        'reviews' => const DriverEarningsScreen(),
        'help' => const HelpGuideScreen(driverMode: true),
        'support' => const FeedbackCenterScreen(),
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

    return Drawer(
      // 310, the width the design asks for. It used to be
      // `width.clamp(300, 360)`, which on a wide phone let the panel grow until
      // the dimmed screen behind it stopped reading as a screen.
      width: 310,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          children: [
            // The header is the way to Profile, so the whole row is the target.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 12, 12),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onSelected(driver ? 'driverProfile' : 'profile'),
                  borderRadius: AppRadii.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        UdAvatar(
                          initials: _initials(controller.currentUserName),
                          size: 52,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                controller.currentUserName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.h3.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.primary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      color: AppTint.star, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    driver
                                        ? 'Driver account'
                                        : 'Customer account',
                                    style: AppType.caption
                                        .copyWith(color: AppText.secondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppText.caption),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                children: [
                  for (final entry in entries)
                    UdDrawerRow(
                      icon: entry.$2,
                      label: entry.$3,
                      selected: current == entry.$1,
                      onTap: () => onSelected(entry.$1),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A steering wheel for Driver mode, a passenger for Customer
                  // mode. The two modes are the same app wearing a different
                  // hat, and an icon says which hat faster than the words
                  // underneath it do.
                  //
                  // UdButton takes an IconData, and the steering wheel is a
                  // painted widget rather than a glyph, so the driver-bound
                  // button is built by hand to keep it. Same height, radius and
                  // type as UdButton.primary.
                  driver
                      ? UdButton.primary(
                          label: 'Customer mode',
                          icon: Icons.person_rounded,
                          onPressed: onSwitchMode,
                        )
                      : _SwitchToDriverButton(onPressed: onSwitchMode),
                  const SizedBox(height: 8),
                  UdButton.ghost(
                    label: 'Logout',
                    icon: Icons.logout_rounded,
                    size: UdButtonSize.small,
                    // Confirmed. Logout sits directly under the menu items, so
                    // a mis-tap signed the customer straight out and they had
                    // to wait for another code to get back in.
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final confirmed = await showUdDialog<bool>(
                        context: context,
                        title: 'Log out?',
                        message: 'You will need to verify your phone number '
                            'again to sign back in.',
                        actions: [
                          Builder(
                            builder: (dialogContext) => UdButton.outline(
                              label: 'Stay signed in',
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                            ),
                          ),
                          Builder(
                            builder: (dialogContext) => UdButton(
                              label: 'Log out',
                              variant: UdButtonVariant.danger,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                            ),
                          ),
                        ],
                      );
                      if (confirmed != true) return;
                      navigator.pop();
                      await controller.logout();
                    },
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


/// The drawer's "Driver mode" button.
///
/// A copy of [UdButton] with the primary fill, because the steering wheel is a
/// painted widget rather than an icon glyph and [UdButton] takes an [IconData].
/// Every measurement here is the same one: 58px, radius 17, `AppType.button`.
class _SwitchToDriverButton extends StatelessWidget {
  const _SwitchToDriverButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = AppRadii.all(AppRadii.cta);

    return SizedBox(
      height: AppSizes.button,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SteeringWheelIcon(size: 22, color: AppText.onBrand),
                const SizedBox(width: 10),
                Text(
                  'Driver mode',
                  style: AppType.button.copyWith(color: AppText.onBrand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
