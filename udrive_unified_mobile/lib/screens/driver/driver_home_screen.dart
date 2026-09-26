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
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import '../operations/live_trip_navigation_screen.dart';
import 'driver_documents_screen.dart';

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
    if (!mounted) return;
    setState(() {
      if (dashboard != null) _dashboard = dashboard;
      _pendingDocuments = pending;
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
    final firstName = name.isEmpty ? 'driver' : name.split(' ').first;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
        children: [
          // "Hi, Usman" and one line saying what the switch above is doing.
          //
          // The switch itself is in the bar and not repeated here. It used to
          // be in both places — one of them wired to a field that never
          // changed — and two switches for one state is how they disagree.
          Text(
            'Hi, $firstName',
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 6),
          Text(
            _isOnline
                ? "You're online. New requests within 5 KM will appear here "
                    'automatically.'
                : "You're offline. Turn the switch on above to start receiving "
                    'nearby ride requests.',
            style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 18),

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
          ] else ...[
            // Today, in one line: rides done and money earned.
            _TodayStrip(dashboard: _dashboard),
            const SizedBox(height: 14),
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
              _CompactWaitingState(
                hasActiveTrip: activeTrip != null,
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
                    enabled:
                        verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                    onAccept: () => _showOffer(request, verifiedVehicles),
                    onMap: () => _openRequestMap(request),
                    onReject: () => _rejectRequest(request),
                  ),
                ),
              ),
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
  List<LiveRideRequest> _liveRequests(List<LiveRideRequest> requests) {
    final now = DateTime.now();
    final visible = <LiveRideRequest>[];

    for (final request in requests) {
      final deadline = _requestDeadline.putIfAbsent(
        request.id,
        () => now.add(const Duration(seconds: AppConfig.decisionSeconds)),
      );
      if (deadline.isAfter(now)) visible.add(request);
    }

    // Deadlines for requests the server has stopped sending would otherwise
    // accumulate for as long as the app is open.
    final ids = requests.map((request) => request.id).toSet();
    _requestDeadline.removeWhere((id, _) => !ids.contains(id));

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

  Future<void> _rejectRequest(LiveRideRequest request) async {
    final result = await showUdDialog<bool>(
      context: context,
      title: _t('Reject request?', 'درخواست مسترد کریں؟'),
      message: _t(
        'This request will be removed only from your queue. Other eligible Drivers can still respond.',
        'یہ درخواست صرف آپ کی فہرست سے ہٹے گی۔ دوسرے اہل ڈرائیور جواب دے سکیں گے۔',
      ),
      actions: [
        Builder(
          builder: (dialogContext) => UdButtonRow(
            children: [
              UdButton.outline(
                label: _t('Cancel', 'منسوخ'),
                onPressed: () => Navigator.pop(dialogContext, false),
              ),
              UdButton(
                label: _t('Reject', 'مسترد'),
                variant: UdButtonVariant.dangerSolid,
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ),
        ),
      ],
    );
    if (result != true || !mounted) return;
    try {
      await AppControllerScope.of(context).rejectLiveDriverRequest(
        rideRequestId: request.id,
        reason: 'Driver declined from dashboard.',
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

/// Online, approved, with a vehicle — and still nothing to do.
class _CompactWaitingState extends StatelessWidget {
  const _CompactWaitingState(
      {required this.hasActiveTrip, required this.onRefresh});

  final bool hasActiveTrip;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => UdEmptyState(
        icon: hasActiveTrip ? Icons.route_rounded : Icons.radar_rounded,
        title: hasActiveTrip
            ? 'Next rides locked for now'
            : 'No nearby ride right now',
        text: hasActiveTrip
            ? 'They unlock within 1 KM of your destination.'
            : 'New 5 KM requests appear here automatically.',
        action: UdButton.outline(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          expand: false,
          onPressed: onRefresh,
        ),
      );
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

/// Today's two numbers, in one line.
///
/// Rides and money, nothing else. Everything a Driver might want to study —
/// the month, their rating, what passengers wrote — lives in Earnings, because
/// studying it is not what they are doing while a request is coming in.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.dashboard});

  final DriverDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final trips = dashboard?.tripsToday ?? 0;
    final earned = dashboard?.earnedToday ?? 0;

    return UdCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: UdStat(
              value: '$trips ride${trips == 1 ? '' : 's'}',
              label: 'Today',
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Earned',
                style: AppType.caption.copyWith(color: AppText.caption),
              ),
              const SizedBox(height: 2),
              // The one bold thing on the strip.
              Text(
                'PKR ${NumberFormat('#,###').format(earned.round())}',
                style: AppType.price.copyWith(color: AppText.primary),
              ),
            ],
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
    required this.enabled,
    required this.onAccept,
    required this.onMap,
    required this.onReject,
  });

  final LiveRideRequest request;
  final int secondsLeft;

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
