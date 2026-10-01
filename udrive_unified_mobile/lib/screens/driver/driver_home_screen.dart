import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_tokens.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking/trip_chat_repository.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/growth/driver_growth_repository.dart';
import '../../models/driver_growth_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import '../operations/live_trip_navigation_screen.dart';
import 'driver_documents_screen.dart';
import 'driver_founding_screen.dart';
import 'driver_mission_detail_screen.dart';
import 'driver_missions_screen.dart';
import 'driver_welcome_bonus_screen.dart';

/// D-10 / D-11 — the driver's dashboard, offline and online.
///
/// Rendered by `main_shell`, which draws the bar above it and holds the
/// online switch, so there is no `Scaffold` here.
///
/// It used to take an `onNavigate` callback. Nothing in the file called it:
/// the shortcut tiles it was for had already been cut, and the bottom bar and
/// drawer do the navigating now. A required parameter that goes nowhere is a
/// promise the screen does not keep, so it is gone.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  TripOperationsRepository? _tripRepository;
  List<MobileTrip> _acceptedTrips = const [];
  Timer? _acceptedRefreshTimer;
  Timer? _presenceTimer;
  Timer? _marketplaceRefreshTimer;
  Timer? _uiTickTimer;
  /// Whether this Driver is taking work, from the one place that owns it.
  ///
  /// This was `bool _isOnline = true;` — a field declared true and never
  /// assigned anywhere in the file. The switch a Driver actually touches is
  /// in the top bar and writes [AppController.driverOnline], so two things
  /// were wrong at once: the offline dashboard could never appear, and a
  /// Driver who had switched themselves off still published their position
  /// every fifteen seconds and still polled for requests every five.
  bool get _isOnline => AppControllerScope.of(context).driverOnline;
  final Map<String, _RecentFareSent> _recentFares = {};

  /// Where this Driver was when presence last went out.
  ///
  /// Kept so a request card can say how far the pickup is from *here*. A
  /// pickup label alone does not tell a Driver whether answering means a two
  /// minute drive or a twenty minute one, which is most of the decision.
  LatLng? _myLocation;

  /// The Driver's own figures: earnings, rating, trips.
  DriverDashboard? _dashboard;

  /// Everything the growth system knows about this driver — online time,
  /// missions, welcome bonus, demand, launch status.
  ///
  /// Null until the first load, and null for good on an install where no admin
  /// has configured a city. Every block that reads it is written to disappear
  /// rather than to show an empty shell, because a dashboard full of zeroes is
  /// a worse answer than no dashboard.
  DriverGrowthHome? _growth;

  /// Documents an Admin has asked for again.
  ///
  /// Sits above everything else on the dashboard until they are sent, because
  /// it is the only thing on this screen with a deadline attached.
  List<PendingDocument> _pendingDocuments = const [];

  /// When each visible request stops being answerable.
  ///
  /// A Customer waiting on offers should not be shown one from a Driver who saw
  /// the request four minutes ago and has since driven away. The window is
  /// short and deliberate: it is the same one the Customer gets to answer an
  /// offer, so neither side is left holding a decision the other has abandoned.
  final Map<String, DateTime> _requestDeadline = <String, DateTime>{};

  /// Requests that have already sounded.
  ///
  /// A Driver waiting for work is not staring at the screen. A request lives
  /// for fifteen seconds, so arriving silently means it is usually gone before
  /// it is noticed — which looks to them like the platform has no work.
  final Set<String> _announcedRequests = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripRepository ??= TripOperationsRepository(AppControllerScope.of(context).apiClient);
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _publishPresence();
      if (!mounted) return;
      await _refresh();
      await _loadAcceptedTrips();
    });
    _acceptedRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadAcceptedTrips(silent: true),
    );
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) => _publishPresence());
    _marketplaceRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshNearbyRequests());
    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();

      final expired = _recentFares.entries
          .where((e) => !e.value.visibleUntil.isAfter(now))
          .map((e) => e.key)
          .toList();
      if (expired.isNotEmpty) {
        setState(() {
          for (final id in expired) {
            _recentFares.remove(id);
          }
        });
        _refreshNearbyRequests();
        return;
      }

      // The countdown on every visible card runs off this one tick, so they
      // stay in step and there is not a timer per request.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _acceptedRefreshTimer?.cancel();
    _presenceTimer?.cancel();
    _marketplaceRefreshTimer?.cancel();
    _uiTickTimer?.cancel();
    super.dispose();
  }

  Future<void> _publishPresence() async {
    if (!mounted || !_isOnline) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      // `best`: this is the position published as the driver's own, and it is
      // what decides which requests reach them and how far away a customer
      // thinks they are.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() =>
          _myLocation = LatLng(position.latitude, position.longitude));
      await AppControllerScope.of(context).apiClient.postJson('/api/v1/driver/marketplace/presence', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        // Lets the customer's map point this vehicle down the road it is
        // actually on. A stationary phone reports a negative or NaN heading,
        // and sending that would spin the car to a direction nobody is facing.
        'heading': position.heading.isFinite && position.heading >= 0
            ? position.heading
            : null,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _refreshNearbyRequests() async {
    if (!mounted || !_isOnline) return;
    final controller = AppControllerScope.of(context);
    if (!controller.driverApproved) return;
    await _publishPresence();
    if (!mounted) return;
    await controller.loadDriverMarketplace();
  }

  /// Reads the Driver's own figures.
  ///
  /// Once per refresh, not on a timer. Earnings move when a trip completes, and
  /// a number that ticks on its own invites watching it instead of driving.
  Future<void> _loadDashboard() async {
    final controller = AppControllerScope.of(context);
    final repository = TripChatRepository(controller.apiClient);
    final dashboard = await repository.driverDashboard();
    final pending = await repository.pendingDocuments();

    // One request for the whole growth side of the screen. It is deliberately
    // not awaited alongside the two above with Future.wait: if the growth
    // endpoint is slow or absent, the figures a driver actually needs should
    // already be on screen.
    final growth = await DriverGrowthRepository(controller.apiClient).home();

    if (!mounted) return;
    setState(() {
      if (dashboard != null) _dashboard = dashboard;
      _pendingDocuments = pending;
      if (growth != null) _growth = growth;
    });
  }

  Future<void> _refresh() async {
    final controller = AppControllerScope.of(context);
    await controller.refreshAccount();
    if (controller.driverApproved) {
      await _publishPresence();
      if (!mounted) return;
      await Future.wait([
        controller.loadDriverMarketplace(),
        _loadAcceptedTrips(silent: true),
        _loadDashboard(),
      ]);
    }
  }

  Future<void> _loadAcceptedTrips({bool silent = false}) async {
    final repository = _tripRepository;
    if (repository == null) return;
    try {
      final trips = await repository.driverTrips();
      if (!mounted) return;
      setState(() {
        _acceptedTrips = trips
            .where((trip) => const {
                  'DriverAccepted',
                  'DriverEnRoute',
                  'DriverArrived',
                  'TripStarted',
                  'Emergency',
                }.contains(trip.tripStatus))
            .toList()
          ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
      });
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accepted rides could not be refreshed.')),
        );
      }
    }
  }

  /// Opens a rewards screen and refreshes on the way back.
  ///
  /// The refresh matters: a milestone can be credited while that screen is
  /// open, and a driver returning to a home card still showing the old figure
  /// has been told two different things in ten seconds.
  Future<void> _openGrowth(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _loadDashboard();
  }

  Future<void> _openAcceptedRide(MobileTrip trip) async {
    final repository = _tripRepository;
    if (repository == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverLiveNavigationScreen(
          trip: trip,
          repository: repository,
        ),
      ),
    );
    await _loadAcceptedTrips(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final verifiedVehicles = controller.liveVehicles.where((vehicle) {
      final status = vehicle.status.trim().toLowerCase();
      return status == 'verified' || status == 'approved';
    }).toList(growable: false);
    final requests = controller.liveDriverRideRequests;
    final activeTrip = _acceptedTrips.isEmpty ? null : _acceptedTrips.first;
    final name = controller.currentUserName.trim();
    final firstName = name.isEmpty ? 'Driver' : name.split(' ').first;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
        children: [
          // The online state, said once and said properly.
          //
          // This was a greeting and a sentence. The sentence was the only thing
          // telling a driver whether they were taking work, and it sat in grey
          // body text below their own name — on a phone propped on a dashboard
          // that is not a state anyone can read at a glance. The switch is in
          // the bar above and stays there; this card is the answer to "am I
          // earning right now", with the two numbers that qualify it.
          _OnlineHeroCard(
            name: firstName,
            online: _isOnline,
            onlineSeconds: _growth?.presence.todaySeconds ??
                controller.onlineSecondsToday,
            acceptanceRate: _growth?.acceptanceRate,
            cityName: _growth?.presence.cityName ?? controller.launchCityName,
            onGoOnline: () => controller.toggleDriverOnline(true),
          ),
          const SizedBox(height: 14),

          // Today's three figures. Earnings first, because that is the one
          // being asked.
          //
          // Hidden during an active ride, which is the rule this screen already
          // followed: a driver on their way to a pickup has one thing to do,
          // and today's takings are something to read past on the way to it.
          if (activeTrip == null) ...[
            _TodayTiles(growth: _growth, dashboard: _dashboard),
            const SizedBox(height: 18),
          ],

          // Above everything, including an active ride. It is the only block
          // on this screen with a consequence attached to ignoring it.
          if (_pendingDocuments.isNotEmpty) ...[
            _DocumentRequestBanner(
              documents: _pendingDocuments,
              onOpen: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DriverDocumentsScreen(),
                  ),
                );
                if (mounted) await _refresh();
              },
            ),
            const SizedBox(height: 14),
          ],

          // With a ride accepted, the dashboard is that ride and nothing else.
          //
          // Today's takings, the next-rides section and the locked-requests
          // notice all describe work that is not happening yet. A Driver who
          // has just accepted is driving to a pickup, and every other block on
          // the screen is something to read past on the way to the one button
          // they need.
          if (activeTrip != null) ...[
            _LiveRideHeroCard(
              trip: activeTrip,
              onOpen: () => _openAcceptedRide(activeTrip),
            ),
            const SizedBox(height: 14),
          ],

          // The reward blocks. Each one draws nothing at all when the server
          // has configured nothing, so an install with no campaigns shows the
          // same screen it always did.
          if (activeTrip == null) ...[
            if (_growth?.activeMission != null) ...[
              _ActiveMissionCard(
                mission: _growth!.activeMission!,
                onTap: () => _openGrowth(
                  DriverMissionDetailScreen(mission: _growth!.activeMission!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_growth?.welcomeBonus != null) ...[
              _WelcomeBonusStrip(
                bonus: _growth!.welcomeBonus!,
                onTap: () => _openGrowth(const DriverWelcomeBonusScreen()),
              ),
              const SizedBox(height: 12),
            ],
            if ((_growth?.demand ?? const []).isNotEmpty) ...[
              _DemandBlock(zones: _growth!.demand),
              const SizedBox(height: 18),
            ],
          ],
          if (_recentFares.isNotEmpty) ...[
            const SizedBox(height: 14),
            ..._recentFares.values.map((sent) {
              LiveDriverRideOfferStatus? liveStatus;
              for (final offer in controller.liveDriverRideOfferStatuses) {
                if (offer.rideRequestId == sent.rideRequestId) {
                  liveStatus = offer;
                  break;
                }
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecentFareSentCard(sent: sent, status: liveStatus),
              );
            }),
          ],
          if (activeTrip == null) ...[
            UdSectionHeader(
              title: 'Nearby rides',
              // A count, not a link: `actionLabel` renders in lime and looks
              // pressable, and there is nothing here to press.
              caption: requests.isEmpty ? null : '${requests.length} live',
            ),
            const SizedBox(height: 4),
            Text(
              'Live requests within 5 KM',
              style: AppType.small.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 14),
          ],
          if (activeTrip == null)
            if (!_isOnline)
              const UdEmptyState(
                icon: Icons.power_settings_new_rounded,
                title: 'Driver is offline',
                text: 'Use the switch in the bar above to go online.',
              )
            else if (!controller.driverApproved)
              // Not just "approval required". A Driver stuck here needs to know
              // which of the three things is true — nothing sent, waiting, or
              // rejected — and be one tap from the screen that fixes it. The old
              // card said none of that and led nowhere, so the only way forward
              // was to guess or ring support.
              UdEmptyState(
                icon: Icons.verified_user_outlined,
                tone: UdTone.warn,
                title: 'Approval needed before you can drive',
                text: 'Upload your CNIC, licence and photograph, check each '
                    'one, then send them for approval. The result appears '
                    'there.',
                action: UdButton(
                  label: 'Open my documents',
                  icon: Icons.folder_open_rounded,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverDocumentsScreen(),
                    ),
                  ),
                ),
              )
            else if (verifiedVehicles.isEmpty)
              const UdEmptyState(
                icon: Icons.directions_car_outlined,
                tone: UdTone.warn,
                title: 'Verified vehicle required',
                text: 'Verify at least one vehicle before sending fares.',
              )
            else if (requests.isEmpty)
              // Never just "no rides available".
              //
              // During launch this is the screen a driver sees most, and an
              // empty state that says only that the platform has nothing is a
              // screen that tells them to stop opening the app. This one answers
              // the three questions they actually have: when does it get busy,
              // where is it busy now, and what am I earning in the meantime.
              _NoRideState(
                growth: _growth,
                onRefresh: _refreshNearbyRequests,
              )
            else
              ...(() {
                final live = _liveRequests(requests);
                // After the frame, not during it: playing a sound inside build
                // would fire again on every unrelated rebuild.
                if (live.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _announceRequests(live),
                  );
                }
                return live;
              })().map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DashboardRequestCard(
                    request: request,
                    secondsLeft: _secondsLeft(request),
                    driverLocation: _myLocation,
                    commissionPercentage: _growth?.commissionPercentage,
                    enabled:
                        verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                    onAccept: () => _showOffer(request, verifiedVehicles),
                    onMap: () => _openRequestMap(request),
                    onReject: () => _rejectRequest(request),
                  ),
                ),
              ),
          // Below the work, not above it. A driver opening this screen is
          // looking for a ride; the wallet and the launch card are what they
          // read while there is not one.
          if (_growth != null) ...[
            const SizedBox(height: 18),
            _WalletRow(
              balance: _growth!.walletBalance,
              bonus: _growth!.bonusBalance,
            ),
            if (_growth!.launch != null) ...[
              const SizedBox(height: 12),
              _LaunchCard(launch: _growth!.launch!),
            ],
            if (_growth!.founding?.isFoundingDriver == true) ...[
              const SizedBox(height: 12),
              _FoundingRow(
                founding: _growth!.founding!,
                onTap: () => _openGrowth(
                  DriverFoundingScreen(founding: _growth!.founding!),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // One way in to everything the growth system offers, for a driver
            // who wants the list rather than the one card above.
            UdButton.outline(
              label: 'Rewards & missions',
              icon: Icons.star_outline_rounded,
              onPressed: () => _openGrowth(const DriverMissionsScreen()),
            ),
          ],

          if (controller.marketplaceError != null) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.cloud_off_rounded,
              text: controller.marketplaceError,
              trailing: UdButton(
                label: 'Retry',
                size: UdButtonSize.xs,
                variant: UdButtonVariant.outline,
                expand: false,
                onPressed: _refresh,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sounds once for each request the Driver has not yet seen.
  ///
  /// `SystemSound` rather than a bundled clip: the phone's own notification
  /// tone already respects silent mode and the volume the person has set, where
  /// an audio file would ignore both. The haptic covers a silenced phone, which
  /// on a driver's handset is the usual state.
  void _announceRequests(List<LiveRideRequest> requests) {
    final fresh = requests
        .where((request) => !_announcedRequests.contains(request.id))
        .toList(growable: false);
    if (fresh.isEmpty) return;

    for (final request in fresh) {
      _announcedRequests.add(request.id);
    }

    // Only while online. A Driver who has switched off should not be buzzed by
    // work they have declined to receive.
    if (!_isOnline) return;

    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
  }

  /// Requests still inside their decision window.
  ///
  /// The deadline is set the first time a request is seen rather than from its
  /// server timestamp, because what matters is how long *this* Driver has been
  /// looking at it.
  /// The requests worth showing, each with a countdown to decide on.
  ///
  /// The countdown is a nudge, not a verdict. It used to be a verdict: the
  /// deadline was set once per request id and never renewed, so fifteen seconds
  /// after a card first appeared it vanished for good — even though the server
  /// was still sending it, and would go on sending it until somebody took the
  /// ride. A driver who glanced away, or was finishing another trip, lost that
  /// customer permanently and had no way to ask for them back.
  ///
  /// Now an expired deadline is restarted rather than obeyed, so the card
  /// returns to the top of the queue on the next poll. What removes a request
  /// from this list is the server dropping it — because it was taken, expired,
  /// or this driver rejected it — which is the only thing that should.
  List<LiveRideRequest> _liveRequests(List<LiveRideRequest> requests) {
    final now = DateTime.now();
    final visible = <LiveRideRequest>[];

    for (final request in requests) {
      var deadline = _requestDeadline[request.id];
      if (deadline == null || !deadline.isAfter(now)) {
        deadline = now.add(const Duration(seconds: AppConfig.decisionSeconds));
        _requestDeadline[request.id] = deadline;
        // A fresh countdown is a fresh chance to notice it.
        _announcedRequests.remove(request.id);
      }
      visible.add(request);
    }

    // Deadlines for requests the server has stopped sending would otherwise
    // accumulate for as long as the app is open.
    final ids = requests.map((request) => request.id).toSet();
    _requestDeadline.removeWhere((id, _) => !ids.contains(id));
    _announcedRequests.removeWhere((id) => !ids.contains(id));

    return visible;
  }

  int _secondsLeft(LiveRideRequest request) {
    final deadline = _requestDeadline[request.id];
    if (deadline == null) return AppConfig.decisionSeconds;
    final seconds = deadline.difference(DateTime.now()).inSeconds + 1;
    return seconds.clamp(0, AppConfig.decisionSeconds);
  }

  Future<void> _openRequestMap(LiveRideRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _DriverRequestRouteMap(request: request)),
    );
  }

  /// D-12 — the fare sheet.
  ///
  /// Was a raw `showModalBottomSheet` with a `TextField` and a `FilledButton`.
  /// Now `showUdSheet`, and it says what it is asking about before it asks:
  /// the fare the Customer offered, where they are going, and which of the
  /// Driver's vehicles is being offered. The eligibility rules, the floor
  /// price and the submit call are untouched.
  Future<void> _showOffer(
    LiveRideRequest request,
    List<dynamic> vehicles,
  ) async {
    final compatible = vehicles.where((vehicle) {
      if (vehicle.passengerCapacity < request.seatsRequested) return false;
      final requested = request.vehicleCategory.trim().toLowerCase();
      if (requested.isEmpty || requested == 'any') return true;
      final category = vehicle.category.toString().trim().toLowerCase();
      return category == requested || category.contains(requested) || requested.contains(category);
    }).toList(growable: false);
    final eligible = compatible.isNotEmpty
        ? compatible
        : vehicles.where((vehicle) => vehicle.passengerCapacity >= request.seatsRequested).toList(growable: false);

    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('No verified vehicle can carry this booking.', 'اس بکنگ کے لیے کوئی موزوں تصدیق شدہ گاڑی موجود نہیں۔'))),
      );
      return;
    }

    final selectedVehicle = eligible.first;
    final amount = TextEditingController(
      text: request.customerOffer > 0 ? request.customerOffer.round().toString() : '',
    );

    final wholeVehicle = request.bookingType.toLowerCase().contains('whole');
    final money = NumberFormat('#,###');
    // Pulled out of the tree: the apostrophe means this needs a double-quoted
    // literal, and nesting one inside an interpolation inside a single-quoted
    // string is legal Dart that nobody should have to read.
    final offerLabel = _t("Customer's offer", 'کسٹمر کی پیشکش');

    await showUdSheet<void>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t('New request', 'نئی درخواست'),
                    style: AppType.h2.copyWith(color: AppText.primary),
                  ),
                ),
                UdBadge(
                  label: wholeVehicle
                      ? 'WHOLE VEHICLE'
                      : '${request.seatsRequested} SEAT'
                          '${request.seatsRequested == 1 ? '' : 'S'}',
                  tone: wholeVehicle ? UdTone.warn : UdTone.info,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // The Customer's number, in the lime card — because the whole
            // sheet exists to answer it.
            UdCard(
              tone: UdCardTone.lime,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PKR ${money.format(request.customerOffer)}',
                    style: AppType.price.copyWith(color: AppText.onBrand),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$offerLabel · ${request.customerName}',
                    style: AppType.small.copyWith(color: AppText.onBrand),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            UdRouteBlock(
              fromLabel: _t('Pickup', 'پک اپ'),
              fromValue: request.pickupLabel,
              toLabel: _t('Drop', 'منزل'),
              toValue: request.destinationLabel,
            ),
            const SizedBox(height: 12),

            UdBanner(
              tone: UdTone.gray,
              icon: Icons.directions_car_rounded,
              text: '${selectedVehicle.make} ${selectedVehicle.model} · '
                  '${selectedVehicle.registrationNumber}',
            ),
            const SizedBox(height: 16),

            UdTextField(
              controller: amount,
              label: _t('Your fare (PKR)', 'آپ کا کرایہ (PKR)'),
              icon: Icons.payments_rounded,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              helper: request.quotedMinimum != null
                  ? 'Customer offered PKR ${money.format(request.customerOffer)} '
                      '· lowest allowed PKR '
                      '${money.format(request.quotedMinimum!)}. Send as-is to '
                      'accept, or edit to counter-offer.'
                  : request.customerOffer > 0
                      ? 'Customer estimate: PKR '
                          '${money.format(request.customerOffer)}'
                      : null,
            ),
            const SizedBox(height: 18),

            UdButtonRow(
              children: [
                UdButton.outline(
                  label: _t('Decline', 'مسترد'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _rejectRequest(request);
                  },
                ),
                UdButton.primary(
                  label: _t('Send fare', 'کرایہ بھیجیں'),
                  trailingIcon: Icons.send_rounded,
                  onPressed: () async {
                    final parsedAmount = double.tryParse(amount.text.trim());
                    if (parsedAmount == null || parsedAmount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid fare.')),
                      );
                      return;
                    }

                    // The same floor the customer was held to. See the note in
                    // live_driver_requests_screen.dart for why a driver is not
                    // allowed to undercut it.
                    final floor = request.quotedMinimum;
                    if (floor != null && parsedAmount < floor) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'The lowest fare for this trip is PKR '
                          '${money.format(floor)}.',
                        ),
                      ));
                      return;
                    }

                    try {
                      await AppControllerScope.of(context).submitLiveDriverOffer(
                        rideRequestId: request.id,
                        vehicleId: selectedVehicle.id as String,
                        amount: parsedAmount,
                        etaMinutes: 1,
                      );
                      if (!mounted) return;
                      Navigator.pop(sheetContext);
                      setState(() {
                        _recentFares[request.id] = _RecentFareSent(
                          rideRequestId: request.id,
                          pickupLabel: request.pickupLabel,
                          destinationLabel: request.destinationLabel,
                          amount: parsedAmount,
                          visibleUntil: DateTime.now().add(const Duration(seconds: 20)),
                        );
                      });
                      await _refreshNearbyRequests();
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Asks why, then rejects.
  ///
  /// This was a yes/no dialog that sent "Driver declined from dashboard" every
  /// time, which told operations nothing. A reason costs the driver one extra
  /// tap and is the only signal that separates "the fare is too low" — a
  /// pricing problem — from "the pickup is too far", which is a dispatch radius
  /// problem. Both look identical in a rejection count.
  ///
  /// Still one tap to get out of it: dismissing the sheet rejects nothing.
  Future<void> _rejectRequest(LiveRideRequest request) async {
    const reasons = <(String, String, IconData)>[
      ('PickupTooFar', 'Pickup is too far', Icons.social_distance_rounded),
      ('FareTooLow', 'Fare is too low', Icons.trending_down_rounded),
      ('GoingOffline', 'Going offline', Icons.power_settings_new_rounded),
      ('VehicleIssue', 'Vehicle issue', Icons.build_rounded),
      ('Other', 'Other reason', Icons.more_horiz_rounded),
    ];

    final chosen = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('Why are you rejecting?', 'آپ کیوں مسترد کر رہے ہیں؟'),
            style: AppType.h3.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'This request leaves your queue for two minutes. Other drivers '
                  'can still take it, and if nobody does it comes back to you. '
                  'Rejecting does not affect your rating.',
              'یہ درخواست دو منٹ کے لیے آپ کی فہرست سے ہٹے گی۔ دوسرے ڈرائیور '
                  'لے سکتے ہیں، اور اگر کسی نے نہ لی تو دوبارہ آپ کو ملے گی۔ '
                  'مسترد کرنے سے آپ کی ریٹنگ متاثر نہیں ہوتی۔',
            ),
            style: AppType.caption.copyWith(
              height: 1.45,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 16),
          for (final (code, label, icon) in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: UdListRow(
                leading: UdIconTile(icon: icon, size: UdIconTileSize.sm),
                title: label,
                onTap: () => Navigator.pop(sheetContext, code),
              ),
            ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    try {
      await AppControllerScope.of(context).rejectLiveDriverRequest(
        rideRequestId: request.id,
        reason: 'Driver rejected: $chosen',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _RecentFareSent {
  const _RecentFareSent({
    required this.rideRequestId,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.amount,
    required this.visibleUntil,
  });
  final String rideRequestId;
  final String pickupLabel;
  final String destinationLabel;
  final double amount;
  final DateTime visibleUntil;
}

/// A fare that has just gone out, and what the Customer did with it.
///
/// Lives for twenty seconds and then removes itself. It is an acknowledgement,
/// not a record — the record is on the Requests screen.
class _RecentFareSentCard extends StatelessWidget {
  const _RecentFareSentCard({required this.sent, required this.status});

  final _RecentFareSent sent;
  final LiveDriverRideOfferStatus? status;

  @override
  Widget build(BuildContext context) {
    final seconds =
        sent.visibleUntil.difference(DateTime.now()).inSeconds.clamp(0, 20);
    final approved = status?.isApproved == true;
    final rejected = status?.isClosed == true;

    final (UdTone tone, IconData icon, String title, String right) = approved
        ? (UdTone.ok, Icons.verified_rounded, 'Approved · ride confirmed',
            'LIVE')
        : rejected
            ? (UdTone.gray, Icons.do_not_disturb_on_outlined, 'Not selected',
                'CLOSED')
            : (UdTone.lime, Icons.check_rounded,
                'Fare sent · waiting for customer', '${seconds}s');

    return UdBanner(
      tone: tone,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppType.listTitle.copyWith(
                    fontSize: 15,
                    color: AppText.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                right,
                style: AppType.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${sent.pickupLabel} → ${sent.destinationLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 4),
          Text(
            'PKR ${NumberFormat('#,###').format(sent.amount)}',
            style: AppType.priceMd.copyWith(color: AppText.primary),
          ),
        ],
      ),
    );
  }
}

/// The one ride that is happening, when one is.
class _LiveRideHeroCard extends StatelessWidget {
  const _LiveRideHeroCard({required this.trip, required this.onOpen});

  final MobileTrip trip;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => UdCard(
        tone: UdCardTone.navy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'ACTIVE RIDE',
                  style: AppType.overline.copyWith(color: AppColors.brand),
                ),
                const Spacer(),
                UdBadge(label: trip.tripStatus, tone: UdTone.lime),
              ],
            ),
            const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const UdRouteRail(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.pickupLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle
                              .copyWith(fontSize: 15.5, color: AppText.onInk),
                        ),
                        const Spacer(),
                        Text(
                          trip.destinationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle
                              .copyWith(fontSize: 15.5, color: AppText.onInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.customerName} · ${trip.passengerCount} '
                    'passenger${trip.passengerCount == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.small.copyWith(color: AppText.onInkMuted),
                  ),
                ),
                Text(
                  'PKR ${NumberFormat('#,###').format(trip.fare)}',
                  style: AppType.priceMd.copyWith(color: AppColors.brand),
                ),
              ],
            ),
            const SizedBox(height: 16),
            UdButton.primary(
              label: 'Open live ride',
              icon: Icons.navigation_rounded,
              onPressed: onOpen,
            ),
          ],
        ),
      );
}

/// Documents an Admin has asked for again, and what happens if they are not
/// sent.
///
/// Deliberately not a dialog. A popup is dismissed once and then gone, and this
/// has to stay in front of the Driver until the file is actually sent — so it
/// sits at the top of the dashboard and does not go away on its own.
class _DocumentRequestBanner extends StatelessWidget {
  const _DocumentRequestBanner({
    required this.documents,
    required this.onOpen,
  });

  final List<PendingDocument> documents;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    // The smallest allowance across the outstanding requests: two documents
    // asked for at different times must not read as four rides of grace.
    final remaining = documents
        .map((document) => document.ridesRemaining)
        .reduce((a, b) => a < b ? a : b);
    final blocked = remaining <= 0;
    final ink = blocked ? AppTint.dangerText : AppTint.warningText;

    return UdBanner(
      tone: blocked ? UdTone.err : UdTone.warn,
      icon: blocked ? Icons.block_rounded : Icons.upload_file_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            blocked
                ? 'Upload required before your next ride'
                : 'A document needs to be sent again',
            style: AppType.listTitle.copyWith(fontSize: 15.5, color: ink),
          ),
          const SizedBox(height: 8),

          // Named, not just counted. "A document" sends a Driver to open
          // the screen and work out which one; the name saves that trip.
          for (final document in documents)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                document.reason == null
                    ? '• ${document.label}'
                    : '• ${document.label} — ${document.reason}',
                style: AppType.small.copyWith(height: 1.45, color: ink),
              ),
            ),

          const SizedBox(height: 4),
          Text(
            blocked
                ? 'No new ride requests will arrive until this is uploaded.'
                : remaining == 1
                    ? 'One more ride, then requests stop until it is sent.'
                    : '$remaining more rides, then requests stop until it '
                        'is sent.',
            style: AppType.small.copyWith(
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 14),
          UdButton(
            label: 'Upload now',
            icon: Icons.upload_rounded,
            size: UdButtonSize.small,
            variant: blocked
                ? UdButtonVariant.dangerSolid
                : UdButtonVariant.dark,
            onPressed: () => onOpen(),
          ),
        ],
      ),
    );
  }
}

/// The pickup and destination of one request, on a map.
///
/// Pushed, so it keeps its own `Scaffold`. The markers are the kit's own — an
/// open navy ring for the pickup and the lime square for the drop — rather
/// than the green circle and red pin they were, which were the last two
/// colours in the app belonging to no part of the brand.
class _DriverRequestRouteMap extends StatelessWidget {
  const _DriverRequestRouteMap({required this.request});
  final LiveRideRequest request;

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(request.pickupLatitude, request.pickupLongitude);
    final destination = LatLng(request.destinationLatitude, request.destinationLongitude);
    final center = LatLng(
      (pickup.latitude + destination.latitude) / 2,
      (pickup.longitude + destination.longitude) / 2,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: 'Pickup & destination',
        onBack: () => Navigator.pop(context),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 9.5),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.udrive.mobile',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [pickup, destination],
                    strokeWidth: 4,
                    color: AppTint.routeActive,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: pickup,
                    width: 28,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTint.pinPickupRing,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppTint.pinPickupFill, width: 5),
                      ),
                    ),
                  ),
                  Marker(
                    point: destination,
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTint.pinDropFill,
                        borderRadius: AppRadii.all(7),
                        border: Border.all(
                            color: AppTint.pinDropBorder, width: 2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: AppSizes.sidePadding,
            right: AppSizes.sidePadding,
            bottom: 22,
            child: UdCard(
              tone: UdCardTone.raised,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const UdRouteRail(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            request.pickupLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                                fontSize: 15.5, color: AppText.primary),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            request.destinationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                                fontSize: 15.5, color: AppText.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One nearby request, as the Driver has to judge it.
///
/// The old card led with the Customer's name and initials, which is the one
/// thing that does not affect the decision. What does affect it is the money,
/// how far the pickup is from where the Driver is standing, how long the trip
/// itself runs, and how much time is left to answer — so those are what this
/// shows, in that order.
class _DashboardRequestCard extends StatelessWidget {
  const _DashboardRequestCard({
    required this.request,
    required this.secondsLeft,
    required this.driverLocation,
    required this.commissionPercentage,
    required this.enabled,
    required this.onAccept,
    required this.onMap,
    required this.onReject,
  });

  final LiveRideRequest request;
  final int secondsLeft;

  /// The platform's cut, so the card can show what the driver keeps.
  ///
  /// Null until the growth endpoint has answered. The breakdown is then left
  /// out entirely rather than computed from a guessed rate — a net figure that
  /// turns out to be wrong at settlement costs more trust than no net figure.
  final double? commissionPercentage;

  /// Null until presence has reported once. The distance line is then omitted
  /// rather than guessed — a wrong number here would send a Driver towards a
  /// pickup they cannot reach in time.
  final LatLng? driverLocation;

  final bool enabled;
  final VoidCallback onAccept;
  final VoidCallback onMap;
  final VoidCallback onReject;

  /// Road distance is not known without a Directions call, and one per card per
  /// refresh would be an expensive way to fill in a subtitle. Straight line
  /// with a road factor is close enough to answer "is this near me or not",
  /// which is the only question being asked of it.
  static double _roadish(LatLng from, LatLng to) =>
      const Distance().as(LengthUnit.Kilometer, from, to) * 1.25;

  static String _km(double value) =>
      value < 10 ? '${value.toStringAsFixed(1)} km' : '${value.round()} km';

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(request.pickupLatitude, request.pickupLongitude);
    final destination =
        LatLng(request.destinationLatitude, request.destinationLongitude);

    final tripKm = _roadish(pickup, destination);
    final toPickupKm =
        driverLocation == null ? null : _roadish(driverLocation!, pickup);

    final wholeVehicle = request.bookingType.toLowerCase().contains('whole');
    final expiring = secondsLeft <= 5;

    return UdCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The time left, across the top. A Driver reading the card needs to
          // know how much of it they can afford to read.
          ClipRRect(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadii.card)),
            child: LinearProgressIndicator(
              value: secondsLeft / AppConfig.decisionSeconds,
              minHeight: 5,
              backgroundColor: AppColors.border,
              color: expiring ? AppTint.dangerText : AppColors.brand,
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Money first. It is the number the Driver is deciding on.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PKR ${NumberFormat('#,###').format(request.customerOffer)}',
                        maxLines: 1,
                        style: AppType.price.copyWith(color: AppText.primary),
                      ),
                    ),
                    UdBadge(
                      label: '${secondsLeft}s',
                      tone: expiring ? UdTone.err : UdTone.gray,
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),

                const SizedBox(height: 4),
                Text(
                  wholeVehicle
                      ? 'Whole vehicle  ·  ${_km(tripKm)} trip'
                      : '${request.seatsRequested} seat'
                          '${request.seatsRequested == 1 ? '' : 's'}'
                          '  ·  ${_km(tripKm)} trip',
                  // Ordinary weight. The fare above is the only bold thing on
                  // the card; when everything is bold, nothing is read first.
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),

                const SizedBox(height: 14),

                // Pickup, with how far it is from here. A label alone does not
                // tell a Driver whether answering means a two minute drive or
                // a twenty minute one, and that is most of the decision.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const UdRouteRail(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RequestLeg(
                              label: request.pickupLabel,
                              detail: toPickupKm == null
                                  ? null
                                  : '${_km(toPickupKm)} from you',
                            ),
                            const SizedBox(height: 12),
                            _RequestLeg(
                              label: request.destinationLabel,
                              detail: DateFormat('d MMM · h:mm a')
                                  .format(request.pickupAt),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // What the fare is actually worth to this driver.
                //
                // The card showed the customer's offer and nothing else, so a
                // driver compared a gross figure against a trip they would be
                // paid the net of. The recommended minimum is the server's own
                // quote — shown only when there is one, since older requests
                // have none and a floor of zero is not a floor.
                if (commissionPercentage != null) ...[
                  const SizedBox(height: 14),
                  _FareBreakdown(
                    offer: request.customerOffer,
                    recommended: request.quotedMinimum,
                    commissionPercentage: commissionPercentage!,
                  ),
                ],

                const SizedBox(height: 16),

                Row(
                  children: [
                    UdIconButton(
                      icon: Icons.route_rounded,
                      variant: UdIconButtonVariant.soft,
                      tooltip: 'Route',
                      onPressed: onMap,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: UdButton.outline(
                        label: 'Reject',
                        size: UdButtonSize.small,
                        onPressed:
                            enabled && secondsLeft > 0 ? onReject : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: UdButton.primary(
                        label: 'Accept & send fare',
                        size: UdButtonSize.small,
                        onPressed:
                            enabled && secondsLeft > 0 ? onAccept : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One end of the trip: a place, and the fact that matters about it.
///
/// The dot it used to carry is now [UdRouteRail] beside the pair, which tells
/// the two ends apart by shape rather than by hue.
class _RequestLeg extends StatelessWidget {
  const _RequestLeg({required this.label, required this.detail});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.listTitle.copyWith(
            fontSize: 15.5,
            height: 1.35,
            color: AppText.primary,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 3),
          Text(
            detail!,
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────── the growth blocks

String _hoursMinutes(int seconds) {
  if (seconds <= 0) return '0m';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String _rupees(num value) => 'PKR ${NumberFormat('#,###').format(value.round())}';

/// Online or offline, in the size that question deserves.
///
/// Navy when online and grey when not, because the two states have to be
/// distinguishable from a phone clipped to a windscreen at arm's length. The
/// switch itself stays in the bar above — one switch, one state — but when the
/// driver is offline this card carries a button, since "turn on the switch
/// above" is an instruction and a button is the thing it describes.
class _OnlineHeroCard extends StatelessWidget {
  const _OnlineHeroCard({
    required this.name,
    required this.online,
    required this.onlineSeconds,
    required this.acceptanceRate,
    required this.cityName,
    required this.onGoOnline,
  });

  final String name;
  final bool online;
  final int onlineSeconds;
  final double? acceptanceRate;
  final String? cityName;
  final VoidCallback onGoOnline;

  @override
  Widget build(BuildContext context) {
    // The name only appears when offline. Online, the two numbers below are
    // what the driver is reading and a greeting is in the way; offline, there
    // is nothing else on the card and addressing them directly is what makes it
    // read as a prompt rather than a status.
    final subtitle = [
      'Ready for rides',
      if (cityName != null && cityName!.isNotEmpty) cityName!,
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: online ? AppColors.navy : AppColors.inkTile,
        borderRadius: AppRadii.all(AppRadii.largeCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: online ? AppColors.brand : AppColors.inkPanel,
                  borderRadius: AppRadii.all(AppRadii.tile),
                ),
                child: Icon(
                  online
                      ? Icons.bolt_rounded
                      : Icons.power_settings_new_rounded,
                  size: 24,
                  color: online ? AppColors.navy : AppText.onInkMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online ? "You're Online" : "You're Offline",
                      style: AppType.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.onInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      online
                          ? subtitle
                          : '$name — ride requests will not reach you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppText.onInkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (online) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InkStat(
                    label: 'Online today',
                    value: _hoursMinutes(onlineSeconds),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InkStat(
                    label: 'Acceptance',
                    // Null until this driver has answered a request. A zero
                    // here would read as a score, and it is not one.
                    value: acceptanceRate == null
                        ? '—'
                        : '${acceptanceRate!.round()}%',
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 14),
            UdButton.primary(label: 'Go online', onPressed: onGoOnline),
          ],
        ],
      ),
    );
  }
}

class _InkStat extends StatelessWidget {
  const _InkStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.inkPanel,
          borderRadius: AppRadii.all(AppRadii.row),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppType.caption.copyWith(color: AppText.onInkMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppType.h3.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.onInk,
              ),
            ),
          ],
        ),
      );
}

/// Earnings, rides and rating for today.
///
/// Falls back to the existing dashboard figures when the growth endpoint has
/// not answered, so this strip shows the same numbers it always did on an
/// install where no city has been configured.
class _TodayTiles extends StatelessWidget {
  const _TodayTiles({required this.growth, required this.dashboard});

  final DriverGrowthHome? growth;
  final DriverDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final earnings = growth?.todayEarnings ?? dashboard?.earnedToday ?? 0;
    final rides = growth?.todayCompletedRides ?? dashboard?.tripsToday ?? 0;
    final rating = growth?.rating ?? dashboard?.rating ?? 0;

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _Tile(label: 'Today', value: _rupees(earnings)),
        ),
        const SizedBox(width: 10),
        Expanded(child: _Tile(label: 'Rides', value: '$rides')),
        const SizedBox(width: 10),
        Expanded(
          child: _Tile(
            label: 'Rating',
            // A driver with no ratings yet has no rating, and 0.0 would be the
            // worst one on the platform.
            value: rating <= 0 ? '—' : rating.toStringAsFixed(1),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => UdCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppType.caption.copyWith(color: AppText.caption),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppType.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
              ),
            ),
          ],
        ),
      );
}

/// The one mission the driver is in the middle of.
class _ActiveMissionCard extends StatelessWidget {
  const _ActiveMissionCard({required this.mission, required this.onTap});

  final DriverMission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final qualified = mission.status == 'Qualified';

    return UdCard(
      tone: UdCardTone.plain,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mission.isPeakHour ? 'PEAK HOUR REWARD' : "TODAY'S MISSION",
                  style: AppType.overline.copyWith(color: AppColors.brandInk),
                ),
              ),
              UdBadge(
                label: _rupees(mission.rewardAmount),
                tone: qualified ? UdTone.lime : UdTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            mission.title,
            style: AppType.listTitle.copyWith(color: AppText.primary),
          ),
          if (mission.zoneName != null) ...[
            const SizedBox(height: 3),
            Text(
              mission.zoneName!,
              style: AppType.caption.copyWith(color: AppText.secondary),
            ),
          ],
          const SizedBox(height: 11),
          UdProgress(value: mission.fraction, lime: !qualified),
          const SizedBox(height: 7),
          Text(
            qualified
                // Said plainly, because a driver who has finished the work and
                // sees no money needs to know the money is coming rather than
                // that something went wrong.
                ? 'Done — the bonus is credited at the end of the day.'
                : mission.progressLabel,
            style: AppType.caption.copyWith(
              fontWeight: qualified ? FontWeight.w800 : FontWeight.w600,
              color: qualified ? AppColors.brandInk : AppText.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of the welcome bonus is unlocked, and what unlocks next.
class _WelcomeBonusStrip extends StatelessWidget {
  const _WelcomeBonusStrip({required this.bonus, required this.onTap});

  final WelcomeBonus bonus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = bonus.nextMilestone;

    return UdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'WELCOME BONUS',
                  style: AppType.overline.copyWith(color: AppText.caption),
                ),
              ),
              Text.rich(
                TextSpan(
                  text: _rupees(bonus.unlockedAmount),
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                  children: [
                    TextSpan(
                      text: '  of ${_rupees(bonus.totalAmount)}',
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          UdProgress(value: bonus.fraction, lime: true),
          if (next != null) ...[
            const SizedBox(height: 8),
            Text(
              'Next ${_rupees(next.rewardAmount)} — ${next.title}',
              maxLines: 2,
              style: AppType.caption.copyWith(color: AppText.secondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the work is expected to be.
class _DemandBlock extends StatelessWidget {
  const _DemandBlock({required this.zones});

  final List<DemandZone> zones;

  static Color _colour(String level) => switch (level) {
        'High' => AppTint.dangerText,
        'Medium' => AppTint.warningText,
        _ => AppText.disabled,
      };

  @override
  Widget build(BuildContext context) {
    // Three is what fits before this stops being a glance and starts being a
    // list. The rest live on the demand screen.
    final visible = zones.take(3).toList(growable: false);
    final anyLive = visible.any((zone) => zone.isLive);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'DEMAND NEAR YOU',
                style: AppType.overline.copyWith(color: AppText.caption),
              ),
            ),
            // The honest label. Anything an admin forecast is "expected", and
            // calling a forecast live is how a driver stops believing both.
            UdBadge(
              label: anyLive ? 'Live' : 'Expected',
              tone: anyLive ? UdTone.ok : UdTone.gray,
            ),
          ],
        ),
        const SizedBox(height: 10),
        UdCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _colour(visible[i].level),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              visible[i].zoneName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.small.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppText.primary,
                              ),
                            ),
                            if (visible[i].reason != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                visible[i].reason!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.caption
                                    .copyWith(color: AppText.caption),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        visible[i].level,
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _colour(visible[i].level),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Online, and nothing to do.
class _NoRideState extends StatelessWidget {
  const _NoRideState({required this.growth, required this.onRefresh});

  final DriverGrowthHome? growth;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final mission = growth?.activeMission;
    final best = growth?.bestDemand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdCard(
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.all(AppRadii.tile),
                ),
                child: const Icon(Icons.schedule_rounded,
                    size: 25, color: AppText.secondary),
              ),
              const SizedBox(height: 12),
              Text(
                'No ride requests right now',
                textAlign: TextAlign.center,
                style: AppType.h3.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 5),
              Text(
                "You're online — a request will appear here as soon as one "
                'comes in.',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(
                  height: 1.45,
                  color: AppText.secondary,
                ),
              ),
              const SizedBox(height: 14),
              UdButton.outline(
                label: 'Check again',
                size: UdButtonSize.small,
                icon: Icons.refresh_rounded,
                onPressed: onRefresh,
              ),
            ],
          ),
        ),

        // Everything below is only drawn when the server actually has something
        // to say. Nothing here is invented to fill the space.
        if (mission != null) ...[
          const SizedBox(height: 10),
          _HintRow(
            icon: Icons.star_rounded,
            tone: UdTone.ok,
            title: 'Next reward ${_rupees(mission.rewardAmount)}',
            text: mission.status == 'Qualified'
                ? 'Already earned — credited at the end of the day.'
                : mission.progressLabel,
          ),
        ],

        if (best != null && best.level != 'Low') ...[
          const SizedBox(height: 10),
          _HintRow(
            icon: Icons.place_rounded,
            tone: UdTone.warn,
            title: '${best.level} demand — ${best.zoneName}',
            text: best.isLive
                ? 'Live right now'
                : [
                    'Expected',
                    if (best.startTime.isNotEmpty)
                      '${best.startTime}–${best.endTime}',
                    if (best.reason != null) best.reason!,
                  ].join('  ·  '),
          ),
        ],

        if ((growth?.updates ?? const []).isNotEmpty) ...[
          const SizedBox(height: 10),
          _HintRow(
            icon: Icons.campaign_rounded,
            tone: UdTone.info,
            title: growth!.updates.first.title,
            text: growth!.updates.first.body,
          ),
        ],
      ],
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final UdTone tone;
  final String title;
  final String text;

  (Color, Color) get _colours => switch (tone) {
        UdTone.ok => (AppTint.success, AppTint.successText),
        UdTone.warn => (AppTint.warning, AppTint.warningText),
        UdTone.err => (AppTint.danger, AppTint.dangerText),
        _ => (AppTint.info, AppTint.infoText),
      };

  @override
  Widget build(BuildContext context) {
    final (wash, ink) = _colours;

    return UdCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: wash,
              borderRadius: AppRadii.all(AppRadii.tile),
            ),
            child: Icon(icon, size: 19, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    height: 1.4,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The wallet, with the bonus called out as what it is.
class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.balance, required this.bonus});

  final double balance;
  final double bonus;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandWash,
                borderRadius: AppRadii.all(AppRadii.tile),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  size: 22, color: AppColors.brandInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wallet  ${_rupees(balance)}',
                    style: AppType.listTitle.copyWith(color: AppText.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Said here rather than only on the wallet screen. A driver
                    // who thinks a bonus is cash finds out at payout, which is
                    // the worst possible moment to learn it.
                    bonus > 0
                        ? 'Includes ${_rupees(bonus)} bonus — pays your '
                            'commission, not withdrawable'
                        : 'Commission balance and earnings',
                    maxLines: 2,
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// How the city's launch is going, in numbers that were counted.
class _LaunchCard extends StatelessWidget {
  const _LaunchCard({required this.launch});

  final LaunchStatus launch;

  @override
  Widget build(BuildContext context) => UdCard(
        tone: UdCardTone.tint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    launch.cityName.isEmpty
                        ? 'UDRIVE LAUNCH'
                        : 'UDRIVE ${launch.cityName.toUpperCase()} LAUNCH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.overline.copyWith(color: AppColors.brandInk),
                  ),
                ),
                if (launch.customerCampaignActive)
                  const UdBadge(label: 'Campaign active', tone: UdTone.ok),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              launch.label,
              style: AppType.listTitle.copyWith(color: AppText.primary),
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                for (var stage = 1; stage <= 4; stage++) ...[
                  if (stage > 1) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: stage <= launch.stage
                            ? AppColors.navy
                            : AppTint.successBorder,
                        borderRadius: AppRadii.all(AppRadii.chip),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                // Only counted figures. A metric with no data is left out
                // entirely rather than shown as a zero that reads as failure.
                Expanded(
                  child: _MiniStat(
                    value: '${launch.verifiedDrivers}',
                    label: 'Drivers',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: '${launch.registeredCustomers}',
                    label: 'Customers',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: '${launch.requestsThisWeek}',
                    label: 'Requests / week',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppType.h3.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ],
      );
}

/// The founding driver badge, when this driver has one.
class _FoundingRow extends StatelessWidget {
  const _FoundingRow({required this.founding, required this.onTap});

  final FoundingDriver founding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: AppRadii.all(AppRadii.tile),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  size: 23, color: AppColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UDrive Founding Driver',
                    style: AppType.listTitle.copyWith(color: AppText.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (founding.cityName != null) founding.cityName!,
                      if (founding.sequenceNo != null) '#${founding.sequenceNo}',
                    ].join('  ·  '),
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Offer, floor, commission and what is left.
///
/// Four lines rather than one net figure, because a driver who is only told
/// "you keep 1,100" cannot tell whether the cut was the commission they agreed
/// to or something else. Showing the arithmetic is what makes the number
/// believable, and settlement disputes are almost always about a number nobody
/// could check at the time.
class _FareBreakdown extends StatelessWidget {
  const _FareBreakdown({
    required this.offer,
    required this.recommended,
    required this.commissionPercentage,
  });

  final double offer;
  final double? recommended;
  final double commissionPercentage;

  @override
  Widget build(BuildContext context) {
    final commission = offer * commissionPercentage / 100;
    final net = offer - commission;
    final belowFloor = recommended != null && offer < recommended!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.row),
      ),
      child: Column(
        children: [
          _FareLine(label: 'Customer offered', value: _rupees(offer)),
          if (recommended != null) ...[
            const SizedBox(height: 7),
            _FareLine(
              label: 'Recommended minimum',
              value: _rupees(recommended!),
              // Only coloured when the offer is under it. A floor the offer
              // already clears is information, not a warning.
              valueColor: belowFloor ? AppTint.warningText : null,
            ),
          ],
          const SizedBox(height: 7),
          _FareLine(
            label: 'UDrive commission '
                '(${commissionPercentage.toStringAsFixed(
              commissionPercentage % 1 == 0 ? 0 : 1,
            )}%)',
            value: '− ${_rupees(commission)}',
            valueColor: AppTint.dangerText,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1, color: AppColors.border),
          ),
          _FareLine(
            label: 'You keep',
            value: _rupees(net),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _FareLine extends StatelessWidget {
  const _FareLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.strong = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: strong ? AppText.primary : AppText.secondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: strong
                ? AppType.listTitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppText.primary,
                  )
                : AppType.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppText.primary,
                  ),
          ),
        ],
      );
}
