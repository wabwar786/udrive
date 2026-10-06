import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_config.dart';
import '../../core/services/offer_card_fields.dart';
import '../../core/services/service_availability_repository.dart';
import '../../core/vehicles/vehicle_image_repository.dart';
import '../../core/booking/booking_repository.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/media/alert_sound.dart';
import '../../core/maps/ud_map.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/vehicles/nearby_repository.dart';
import '../../core/vehicles/nearby_vehicle.dart';
import '../../models/booking_models.dart';
import '../operations/live_trip_navigation_screen.dart';

/// What the Customer chose when backing out of a running search.
enum _LeaveSearchChoice { keepSearching, cancelRide }

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({
    required this.rideRequestId,
    required this.pickup,
    required this.destination,
    required this.customerOffer,
    required this.vehicleName,
    this.pickupPoint,
    this.destinationPoint,
    this.routePoints,
    super.key,
  });

  final String rideRequestId;
  final String pickup;
  final String destination;
  final int customerOffer;
  final String vehicleName;

  /// Drawn behind the offers when supplied. Optional because several older
  /// flows push this screen with labels only, and a screen that crashed
  /// without coordinates would be worse than one that shows a plain backdrop.
  final LatLng? pickupPoint;
  final LatLng? destinationPoint;

  /// The route already computed upstream. Passed rather than recomputed: this
  /// screen must not pay for a second Directions call to draw a line the
  /// previous screen already has.
  final List<LatLng>? routePoints;

  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// How far around the pickup the map shows while drivers are searched for.
  static const double _searchRadiusKm = 2;

  /// The zoom that fits [_searchRadiusKm] either side of the pickup on a phone.
  static const double _searchZoom = 13.4;

  /// Drives the "searching" rings over the pickup. An overlay, not a map
  /// circle: animating a circle on the map would rebuild the whole map every
  /// frame, which cheap phones cannot afford.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  Timer? _poller;
  Timer? _ticker;
  bool _loading = true;
  bool _resolved = false;
  String? _approvingOfferId;

  // These three are keyed by `offer.revision` — "<id>@<version>" — not by the
  // offer id.
  //
  // That distinction is the whole bug fix. A driver re-quoting the same ride
  // does not create a second offer: the server updates the row in place, so the
  // id stays the same and only the amount and the version change. Keyed by id,
  // the second quote inherited the first quote's countdown, which had long since
  // run out — so the moment it arrived it was auto-declined, added to the
  // declined set, and hidden for ever. The customer never saw it, which is
  // exactly what was reported.
  final Map<String, DateTime> _customerDecisionDeadline = <String, DateTime>{};

  /// When this device first received each offer revision, so the newest offer
  /// can be listed first.
  final Map<String, DateTime> _firstSeen = <String, DateTime>{};
  final Set<String> _declinedRevisions = <String>{};
  final Set<String> _declineInFlight = <String>{};

  /// Revision → the offer id the server knows. Declining has to send the id.
  final Map<String, String> _offerIdOfRevision = <String, String>{};

  /// Bearer token for the driver photographs.
  ///
  /// That route is authenticated and `Image.network` cannot go through the API
  /// client, so each image attaches the header itself. Read once here rather
  /// than per card.
  String? _mediaToken;

  /// Category pictures, for vehicles whose driver did not upload one.
  Map<String, String> _vehicleImages = const {};

  /// Offers that have already announced themselves.
  ///
  /// Kept so the alert fires once per offer. The screen polls every few
  /// seconds, and an alert tied to "offers exist" rather than "a new offer
  /// arrived" would chime continuously while someone read the first one.
  final Set<String> _announced = <String>{};

  final _mapController = UdMapController();
  bool _cancelling = false;

  /// When the search began, for the elapsed clock in the waiting card.
  ///
  /// Not `final`. Raising the fare restarts it, which is what the comment at
  /// the raise already claimed and what the customer is told is happening —
  /// but the field could not be reassigned, so after raising their offer they
  /// watched a clock that said they had been waiting six minutes at a price
  /// they had set ten seconds ago.
  DateTime _searchStartedAt = DateTime.now();

  /// The fare the customer is currently offering.
  ///
  /// Starts at what they sent and moves only when they raise it, so the waiting
  /// card and the raise sheet never disagree about the number in play.
  late int _offer = widget.customerOffer;

  /// When the raise prompt was last shown or dismissed.
  ///
  /// Used to space the prompt out. Reappearing the moment it is closed would
  /// make it an obstacle rather than an offer of help.
  DateTime? _lastRaisePrompt;

  bool _raising = false;

  /// How long to wait before suggesting a higher fare.
  ///
  /// A minute of silence usually means the fare is below what drivers nearby
  /// will take. Prompting earlier trains the customer to overpay; leaving them
  /// waiting with no way to act is worse.
  static const Duration _raiseAfter = Duration(minutes: 1);

  /// Vehicles online around the pickup.
  ///
  /// Shown both as a count ("14 drivers nearby") and as cars on the map behind
  /// the card. Waiting in front of an empty map gives the customer no way to
  /// tell whether the request went anywhere; seeing the vehicles it went to
  /// answers that without them having to ask.
  List<NearbyVehicle> _nearby = const [];

  /// Length of the Customer's decision window, in seconds.
  ///
  /// How long a driver's offer stays open — an admin setting
  /// (`dispatch.offer_valid_seconds`, three minutes by default) rather than
  /// the driver's own thirty seconds, which used to run the offer out while
  /// the customer was still reading it. Never past the server's expiry for the
  /// offer either way (see where the deadline is set).
  static int get _decisionSeconds =>
      ServiceAvailabilityRepository.offerValidSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _frameRoute();
      _loadCardMedia();
      unawaited(ServiceAvailabilityRepository(
              AppControllerScope.of(context).apiClient)
          .refreshDispatchSettings());
    });
    unawaited(_loadNearby());
    _scheduleNextPoll();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _resolved) return;
      _expireCustomerWindows();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _ticker?.cancel();
    _pulse.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Stops asking while nobody is looking.
  ///
  /// This screen is the busiest poller in the app. Left running in the
  /// background it keeps two API calls every few seconds going out of a phone in
  /// somebody's pocket — and when they come back, a queue of answers to
  /// questions nobody is waiting for lands before the one that matters.
  ///
  /// Coming back asks again straight away rather than waiting out the gap: the
  /// first thing a customer wants on returning is whether a driver answered.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollGap = _fastestPoll;
      _scheduleNextPoll();
      unawaited(_refresh(silent: true));
    } else {
      _poller?.cancel();
    }
  }

  /// Frames the map once its surface exists: the 2 km around the pickup,
  /// where the drivers being asked are — not the whole trip, which the
  /// customer has just seen on the previous screen.
  ///
  /// Called on a delay rather than in the first frame: the renderer is chosen
  /// after a connectivity check, so a move issued immediately lands on nothing.
  void _frameRoute() {
    final pickup = widget.pickupPoint;
    final points = _mapPoints;
    if (pickup == null && points.length < 2) return;
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (pickup != null) {
        _mapController.moveTo(pickup, zoom: _searchZoom);
      } else {
        _mapController.fitBounds(points, padding: 70);
      }
    });
  }

  /// Reads the vehicles around the pickup, once.
  ///
  /// Not polled: this is context for the wait, not a live feed, and another
  /// timer on a screen that already runs two would buy very little.
  Future<void> _loadNearby() async {
    final pickup = widget.pickupPoint;
    if (pickup == null) return;

    final controller = AppControllerScope.of(context);
    final vehicles = await NearbyVehicleRepository(controller.apiClient).nearby(
      latitude: pickup.latitude,
      longitude: pickup.longitude,
      radiusKm: _searchRadiusKm,
    );

    if (!mounted) return;
    setState(() => _nearby = vehicles);
  }

  /// Offers the customer a higher fare after a minute of silence.
  ///
  /// A sheet rather than a snackbar: it needs a stepper and a button, and it
  /// should not disappear on its own while someone is deciding what their trip
  /// is worth.
  Future<void> _promptRaiseFare() async {
    if (_raising || !mounted) return;
    _raising = true;
    _lastRaisePrompt = DateTime.now();

    // Steps that match the fare's size. Fifty rupees on a nine thousand rupee
    // Coster run is not a raise anybody notices.
    final step = _offer >= 10000
        ? 500
        : _offer >= 3000
            ? 100
            : 50;
    var proposed = _offer + step;

    final confirmed = await showUdSheet<int>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t('No offers yet', 'ابھی کوئی آفر نہیں'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'Drivers nearby have not taken this fare. Raising it usually '
                  'gets an answer.',
                  'قریبی ڈرائیورز نے یہ کرایہ قبول نہیں کیا۔ اسے بڑھانے پر عموماً '
                  'جواب آ جاتا ہے۔',
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppText.secondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _StepCircle(
                    icon: Icons.remove_rounded,
                    // Never back below what is already on the table. The server
                    // refuses it, and a button that fails is worse than one
                    // that is plainly unavailable.
                    enabled: proposed - step > _offer,
                    onTap: () => setSheet(() => proposed -= step),
                  ),
                  Expanded(
                    child: Text(
                      'PKR ${NumberFormat('#,###').format(proposed)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  _StepCircle(
                    icon: Icons.add_rounded,
                    enabled: true,
                    onTap: () => setSheet(() => proposed += step),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  'Currently offering PKR ${NumberFormat('#,###').format(_offer)}',
                  'موجودہ پیشکش PKR ${NumberFormat('#,###').format(_offer)}',
                ),
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: AppText.caption),
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: _t('Find offers again', 'دوبارہ آفرز تلاش کریں'),
                onPressed: () => Navigator.pop(sheetContext, proposed),
              ),
              const SizedBox(height: 8),
              UdButton.ghost(
                label: _t('Keep waiting at this fare', 'اسی کرایے پر انتظار کریں'),
                size: UdButtonSize.small,
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );

    _raising = false;
    _lastRaisePrompt = DateTime.now();
    if (confirmed == null || !mounted) return;

    try {
      final controller = AppControllerScope.of(context);
      await BookingRepository(controller.apiClient)
          .raiseRideRequestFare(widget.rideRequestId, confirmed);
      if (!mounted) return;
      // The clock restarts: this is a fresh search at a new price, and showing
      // the old elapsed time would suggest nothing had changed.
      setState(() {
        _offer = confirmed;
        _searchStartedAt = DateTime.now();
      });
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// Whether it is time to suggest raising the fare.
  ///
  /// Only while nothing has been offered. An unanswered request is a price
  /// problem; a request with offers on screen is a choice the customer is still
  /// making, and interrupting that would be pushing them to pay more than they
  /// need to.
  bool _shouldPromptRaise(int offerCount) {
    if (_resolved || _raising || offerCount > 0) return false;
    final since = _lastRaisePrompt ?? _searchStartedAt;
    return DateTime.now().difference(since) >= _raiseAfter;
  }

  /// How long the customer has been waiting, as m:ss.
  ///
  /// Counts up rather than down. A countdown would have to be counting towards
  /// something, and the request stays open for an hour — a bar draining to zero
  /// in sixty seconds would be telling the customer their request is about to
  /// die when it is not.
  String get _elapsed {
    final seconds = DateTime.now().difference(_searchStartedAt).inSeconds;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  List<LatLng> get _mapPoints {
    final route = widget.routePoints;
    if (route != null && route.length >= 2) return route;
    final pickup = widget.pickupPoint;
    final destination = widget.destinationPoint;
    if (pickup != null && destination != null) return [pickup, destination];
    return const [];
  }

  /// True while a poll is in the air. Nothing else starts one.
  bool _polling = false;

  /// How long to wait before asking again.
  ///
  /// Two seconds was a `Timer.periodic`, and that was the bug behind "sab kuch
  /// hang ho jata hai". Each poll makes **two** API calls — the ride state and
  /// the offers — and on the connection a customer in Azad Kashmir actually has
  /// (the report came in at 4.5 KB/s) a round takes far longer than two seconds.
  /// A periodic timer does not care: it fired again, and again, stacking
  /// requests on a line that was already full, so every one of them got slower
  /// and the screen stopped responding.
  ///
  /// Now the next poll is scheduled only once the last one has come back, and
  /// the gap is whatever the last round actually took, capped at ten seconds.
  /// On a good connection that is the same two seconds as before. On a bad one
  /// it settles at the fastest rate the line can carry, which is as live as live
  /// can honestly be.
  static const Duration _fastestPoll = Duration(seconds: 2);
  static const Duration _slowestPoll = Duration(seconds: 10);
  Duration _pollGap = _fastestPoll;

  void _scheduleNextPoll() {
    _poller?.cancel();
    if (!mounted || _resolved) return;

    _poller = Timer(_pollGap, () async {
      if (!mounted || _resolved || _polling) {
        _scheduleNextPoll();
        return;
      }

      _polling = true;
      final started = DateTime.now();
      try {
        await _refresh(silent: true);
      } catch (_) {
        // A failed poll is not news on this screen — the next one is seconds
        // away and the card already on screen is still the best thing to show.
      } finally {
        _polling = false;
        final took = DateTime.now().difference(started);
        _pollGap = took < _fastestPoll
            ? _fastestPoll
            : (took > _slowestPoll ? _slowestPoll : took);
        _scheduleNextPoll();
      }
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted || _resolved) return;
    final controller = AppControllerScope.of(context);

    try {
      await controller.refreshCustomerRideState();
      if (!mounted || _resolved) return;
      if (await _openExistingBookingIfAny(controller)) return;

      await controller.loadRideOffers(widget.rideRequestId);
      if (!mounted || _resolved) return;
      _registerDecisionWindows(controller.liveDriverOffers);
      if (await _openExistingBookingIfAny(controller)) return;
    } finally {
      if (mounted && !_resolved && _loading) setState(() => _loading = false);
    }

    if (!silent && controller.marketplaceError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.marketplaceError!)),
      );
    }
  }

  /// Sound and a short buzz when a driver answers.
  ///
  /// A customer waiting for offers is usually not looking at the screen —
  /// they are standing on a roadside, or have put the phone in a pocket. An
  /// offer lives for seconds, so arriving silently means it is often gone
  /// before it is seen.
  ///
  /// This used to call `SystemSound.play(SystemSoundType.alert)`, so that the
  /// phone's own notification tone would respect silent mode and the volume the
  /// person had set — a bundled clip ignores both. That reasoning was right and
  /// it bought nothing: the call **does nothing on Android**, where Flutter's
  /// embedding implements `click` and ignores `alert`. No error, no sound.
  ///
  /// [AlertSound] plays a bundled half-second chime instead, quietly and at
  /// most once every two seconds. An offer lives for seconds; one that arrives
  /// silently is usually gone before it is seen, which is the whole reason this
  /// method exists.
  void _announce(List<LiveDriverOffer> offers) {
    // Per revision, not per offer: a driver's second quote is news, and under
    // the old keying it arrived in silence because the id had already chimed.
    final fresh = offers
        .where((offer) => !_announced.contains(offer.revision))
        .toList(growable: false);
    if (fresh.isEmpty) return;

    for (final offer in fresh) {
      _announced.add(offer.revision);
    }

    unawaited(AlertSound.chime());
  }

  void _registerDecisionWindows(List<LiveDriverOffer> offers) {
    final now = DateTime.now();
    for (final offer in offers) {
      if (offer.rideRequestId != widget.rideRequestId ||
          _declinedRevisions.contains(offer.revision)) continue;

      // A new revision of an offer the customer already dismissed is a new
      // offer. The driver has answered again, at a different price, and that
      // answer deserves its own window rather than the ruling made on the last
      // one.
      _offerIdOfRevision[offer.revision] = offer.id;
      // The Customer always gets a full 10-second decision window from the
      // moment this device first receives the offer. Server-side validity has
      // an additional hidden network grace period so a visible offer cannot
      // expire while the Customer is pressing Approve.
      // Never past the server's own expiry for this offer.
      //
      // The local window starts when the Customer first sees the offer, which
      // is already later than when the Driver sent it. Left to itself it could
      // keep the Accept button alive after the server had stopped honouring
      // the offer — and a button that fails when pressed is worse than one
      // that has gone.
      _firstSeen.putIfAbsent(offer.revision, () => now);
      final localDeadline = now.add(Duration(seconds: _decisionSeconds));
      final serverDeadline = offer.expiresAt.toLocal();
      _customerDecisionDeadline.putIfAbsent(
        offer.revision,
        () => serverDeadline.isBefore(localDeadline)
            ? serverDeadline
            : localDeadline,
      );
    }

    // Windows belonging to revisions the server has stopped sending would
    // otherwise pile up for as long as this screen is open, and the expiry pass
    // below would keep trying to decline offers that no longer exist.
    final live = offers.map((offer) => offer.revision).toSet();
    _customerDecisionDeadline.removeWhere(
        (revision, _) => !live.contains(revision));
    _offerIdOfRevision.removeWhere((revision, _) => !live.contains(revision));
    _firstSeen.removeWhere((revision, _) => !live.contains(revision));
  }

  void _expireCustomerWindows() {
    final now = DateTime.now();
    final expired = _customerDecisionDeadline.entries
        .where((e) =>
            _offerIdOfRevision[e.key] != _approvingOfferId &&
            !e.value.isAfter(now) &&
            !_declinedRevisions.contains(e.key))
        .map((e) => e.key)
        .toList(growable: false);
    for (final revision in expired) {
      _declineOffer(revision, automatic: true);
    }
  }

  /// Loads the token and the category pictures the cards may need.
  ///
  /// Both are only needed if an offer arrives, and offers take a few seconds —
  /// so this runs alongside the first refresh rather than blocking it.
  Future<void> _loadCardMedia() async {
    final controller = AppControllerScope.of(context);
    try {
      final token = await controller.accessTokenForMedia();
      final images =
          await VehicleImageRepository(controller.apiClient).cached();
      if (!mounted) return;
      setState(() {
        _mediaToken = token;
        _vehicleImages = images;
      });
    } catch (_) {
      // The cards fall back to initials and icons.
    }
  }

  /// The picture to show for this offer's vehicle.
  ///
  /// The driver's own first — a customer at a kerb is looking for a particular
  /// car. The category picture second, which at least shows the right kind of
  /// vehicle. Null last, and the card draws an icon.
  String? _vehicleImageFor(LiveDriverOffer offer) {
    // The photograph the driver actually uploaded, first.
    //
    // It is a `VEHICLE_FRONT` document rather than a column, which is why this
    // used to fall straight through to a stock picture while the driver's own
    // car sat approved in the admin portal.
    if (offer.vehicleHasPhoto) {
      return '${ApiConfig.baseUrl}/api/v1/offers/${offer.id}/vehicle-photo';
    }

    final own = offer.vehicleImageUrl;
    if (own != null && own.trim().isNotEmpty) {
      return own.startsWith('http') ? own : '${ApiConfig.baseUrl}$own';
    }

    final key = VehicleImageRepository.settingKeyFor(offer.vehicleCategory);
    final url = key == null ? null : _vehicleImages[key];
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url';
  }

  int _secondsLeft(LiveDriverOffer offer) {
    final deadline = _customerDecisionDeadline[offer.revision] ?? offer.expiresAt;
    final seconds = deadline.difference(DateTime.now()).inSeconds + 1;
    return seconds.clamp(0, _decisionSeconds);
  }

  List<LiveDriverOffer> _visibleOffers(AppController controller) {
    final now = DateTime.now();
    final offers = controller.liveDriverOffers.where((offer) {
      if (offer.rideRequestId != widget.rideRequestId) return false;
      if (_declinedRevisions.contains(offer.revision)) return false;
      final deadline = _customerDecisionDeadline[offer.revision];
      return deadline == null || deadline.isAfter(now);
    }).toList();
    // Newest first: an offer that has just arrived goes to the top, where the
    // customer is looking, instead of being slotted in by price.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    offers.sort((a, b) => (_firstSeen[b.revision] ?? epoch)
        .compareTo(_firstSeen[a.revision] ?? epoch));
    return offers;
  }

  /// Declines one revision of one offer.
  ///
  /// Takes the revision, because that is what this screen tracks — and sends the
  /// server the offer id, because that is what the server knows.
  Future<void> _declineOffer(String revision, {bool automatic = false}) async {
    if (_declinedRevisions.contains(revision) ||
        _declineInFlight.contains(revision) ||
        _resolved) return;
    _declinedRevisions.add(revision);
    _declineInFlight.add(revision);
    if (mounted) setState(() {});
    try {
      await AppControllerScope.of(context).declineLiveDriverOffer(
        rideRequestId: widget.rideRequestId,
        offerId: _offerIdOfRevision[revision] ?? revision,
        countTowardsDriverRejectLimit: !automatic,
      );
    } catch (_) {
      // The server may already have expired the 20-second Driver offer.
      // For the Customer this offer remains dismissed after the 10-second decision window.
    } finally {
      _declineInFlight.remove(revision);
      if (mounted && !automatic) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver offer declined.')),
        );
      }
    }
  }

  Future<void> _approveOffer(LiveDriverOffer offer) async {
    if (_resolved || _approvingOfferId != null || _secondsLeft(offer) <= 0) return;
    setState(() => _approvingOfferId = offer.id);
    final controller = AppControllerScope.of(context);
    try {
      final booking = await controller.selectLiveDriverOffer(
        rideRequestId: widget.rideRequestId,
        offerId: offer.id,
      );
      if (!mounted) return;
      _resolved = true;
      _poller?.cancel();
      _ticker?.cancel();
      await _showBookingConfirmed(booking, etaMinutes: offer.estimatedArrivalMinutes);
    } catch (error) {
      // The server's own message, captured before anything else runs.
      //
      // This used to refresh first and then read `controller.marketplaceError`,
      // but a successful refresh clears that field — so the real reason was
      // thrown away and every failure, whatever it was, became "this offer is
      // no longer available". That sent the customer looking for another driver
      // when the driver was fine and the request had merely lost a race.
      final reason = _message(error);

      await controller.refreshCustomerRideState();
      if (!mounted) return;

      // A retry is worth one attempt: the common failure was a transient
      // conflict, and the offer is usually still there a moment later.
      if (await _openExistingBookingIfAny(controller)) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
    } finally {
      if (mounted && !_resolved) setState(() => _approvingOfferId = null);
    }
  }

  /// The message a server error actually carried, or a plain fallback.
  ///
  /// Never invents a diagnosis. If the server said the request was closed, the
  /// customer is told that, because "choose another driver" is the wrong advice
  /// for half the things that can go wrong here.
  String _message(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) {
      return _t(
        'That did not go through. Please try again.',
        'یہ مکمل نہیں ہوا۔ دوبارہ کوشش کریں۔',
      );
    }
    return text;
  }

  /// Jumps to tracking if this request already has a live booking.
  ///
  /// "Live" is the important word, and it used to be missing: the match was on
  /// the request id alone, so a booking a driver had cancelled still counted.
  /// When that driver walked away and the request went back out for offers,
  /// this screen opened, found the dead booking and pushed the customer
  /// straight back to a tracking map that said "Ride cancelled" — the loop
  /// they could not get out of.
  static const _deadBookingStatuses = {'Cancelled', 'Completed', 'Expired'};

  Future<bool> _openExistingBookingIfAny(AppController controller) async {
    LiveBooking? booking;
    for (final item in controller.liveBookings) {
      if (item.rideRequestId == widget.rideRequestId &&
          !_deadBookingStatuses.contains(item.status)) {
        booking = item;
        break;
      }
    }
    if (booking == null || !mounted || _resolved) return false;

    int? eta;
    String? selectedOfferId;
    for (final request in controller.liveRideRequests) {
      if (request.id == widget.rideRequestId) {
        selectedOfferId = request.selectedOfferId;
        break;
      }
    }
    if (selectedOfferId != null) {
      for (final offer in controller.liveDriverOffers) {
        if (offer.id == selectedOfferId) {
          eta = offer.estimatedArrivalMinutes;
          break;
        }
      }
    }

    _resolved = true;
    _poller?.cancel();
    _ticker?.cancel();
    await _showBookingConfirmed(booking, etaMinutes: eta);
    return true;
  }

  /// Pushes the live tracking map for a confirmed booking.
  ///
  /// Returns false when the trip is not readable yet, so the caller can fall
  /// back to the summary sheet rather than leaving the customer on a screen
  /// that has just stopped meaning anything.
  Future<bool> _openTracking(
    AppController controller,
    LiveBooking booking,
  ) async {
    final navigator = Navigator.of(context);
    final repository = TripOperationsRepository(controller.apiClient);

    try {
      final trips = await repository.customerTrips();
      final trip = trips.firstWhere((item) => item.bookingId == booking.id);
      if (!mounted) return false;

      await navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => CustomerFullScreenTrackingScreen(
            trip: trip,
            repository: repository,
            tripOtp: booking.tripOtp,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// What to do when the Customer leaves this screen with a search running.
  ///
  /// Leaving used to cancel nothing and show nothing: the request stayed open
  /// on the server for an hour while the app behaved as though no ride existed,
  /// so every new booking was refused with "cancel that request first" and
  /// there was nothing anywhere to cancel. The search is now reachable from
  /// Trips, which makes keeping it a real choice rather than a trap.
  Future<void> _handleBack() async {
    if (_resolved || _cancelling) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final choice = await showUdSheet<_LeaveSearchChoice>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('Drivers are still being asked', 'ڈرائیوروں سے ابھی پوچھا جا رہا ہے'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'You can leave this screen and come back to the search from Trips, '
                      'or cancel it now so you can book something else.',
                  'آپ یہ صفحہ چھوڑ سکتے ہیں اور Trips سے دوبارہ اسی تلاش پر آ سکتے ہیں، '
                      'یا ابھی منسوخ کر دیں تاکہ نئی بکنگ کر سکیں۔',
                ),
                style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              UdButton.primary(
                label: _t('Keep searching', 'تلاش جاری رکھیں'),
                onPressed: () => Navigator.pop(
                    sheetContext, _LeaveSearchChoice.keepSearching),
              ),
              const SizedBox(height: 8),
              UdButton(
                label: _t('Cancel this ride', 'یہ رائیڈ منسوخ کریں'),
                variant: UdButtonVariant.danger,
                onPressed: () =>
                    Navigator.pop(sheetContext, _LeaveSearchChoice.cancelRide),
              ),
              const SizedBox(height: 8),
              UdButton.ghost(
                label: _t('Stay here', 'یہیں رہیں'),
                size: UdButtonSize.small,
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case _LeaveSearchChoice.keepSearching:
        Navigator.of(context).pop();
      case _LeaveSearchChoice.cancelRide:
        await _cancelRequest(confirm: false);
    }
  }

  /// Stops the search and leaves the screen.
  ///
  /// Confirmed first: pressing it by mistake would throw away a request the
  /// Customer has already priced and would have to build again. The back
  /// handler passes `confirm: false` because it has already asked.
  Future<void> _cancelRequest({bool confirm = true}) async {
    if (_cancelling || _resolved) return;

    if (confirm) {
      final confirmed = await showUdDialog<bool>(
        context: context,
        title: _t('Cancel this request?', 'یہ درخواست منسوخ کریں؟'),
        message: _t(
          'Drivers will stop sending offers and you will go back to choosing a vehicle.',
          'ڈرائیور آفر بھیجنا بند کر دیں گے اور آپ دوبارہ گاڑی منتخب کرنے پر واپس چلے جائیں گے۔',
        ),
        actions: [
          Builder(
            builder: (dialogContext) => UdButton.outline(
              label: _t('Keep waiting', 'انتظار جاری رکھیں'),
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ),
          Builder(
            builder: (dialogContext) => UdButton(
              label: _t('Cancel request', 'درخواست منسوخ کریں'),
              variant: UdButtonVariant.danger,
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ),
        ],
      );

      if (confirmed != true) return;
    }

    if (!mounted) return;

    setState(() => _cancelling = true);
    _poller?.cancel();
    _ticker?.cancel();
    _resolved = true;

    final controller = AppControllerScope.of(context);
    final navigator = Navigator.of(context);
    // Through the controller, not the repository: the controller re-reads the
    // customer's requests afterwards, so the Trips tab stops offering a search
    // the server has already closed. The result is still not acted on — the
    // request expires on its own, and a route an older API does not have must
    // not trap the Customer on a screen they have asked to leave.
    await controller.cancelLiveRideRequest(widget.rideRequestId);

    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    _registerDecisionWindows(controller.liveDriverOffers);
    final offers = _visibleOffers(controller);

    // After the frame, not during it: playing a sound inside build would fire
    // again on every unrelated rebuild.
    if (offers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _announce(offers));
    }

    // Checked during build rather than on a timer, because the decision depends
    // on how many offers are on screen — which is a build-time fact.
    if (_shouldPromptRaise(offers.length)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptRaiseFare());
    }

    // canPop is false so the system back gesture reaches _handleBack instead of
    // tearing the route down. Predictive back decides at gesture start, so this
    // has to be declared before the Customer touches the screen, not at commit.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleBack());
      },
      child: _buildBody(offers),
    );
  }

  Widget _buildBody(List<LiveDriverOffer> offers) {
    // While nobody has answered, only the two buttons sit at the top and a
    // small strip at the bottom, so the route stays in view. Once offers
    // arrive the screen is exactly as before.
    final waiting = offers.isEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(waiting: waiting),
          if (waiting && widget.pickupPoint != null)
            Positioned.fill(child: IgnorePointer(child: _searchPulse())),

          // The list sits over the map and only takes the height it needs, so
          // the route stays visible underneath while offers arrive.
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.sidePadding, 6, AppSizes.sidePadding, 12),
                  child: Row(
                    children: [
                      // This screen is where five different booking flows end
                      // up, and it had no visible way back at all — the only
                      // exit was the system gesture, which silently abandoned
                      // the search.
                      UdIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: _t('Back', 'واپس'),
                        onPressed: _cancelling ? null : _handleBack,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CancelPill(
                          busy: _cancelling,
                          label: _t('Cancel request', 'درخواست منسوخ کریں'),
                          onTap: _cancelRequest,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!waiting) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.sidePadding, 0, AppSizes.sidePadding, 8),
                  child: Text(
                    _t('Choose a driver', 'ڈرائیور منتخب کریں'),
                    style: AppType.h1.copyWith(color: AppText.primary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.sidePadding, 0, AppSizes.sidePadding, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined,
                          size: 20, color: AppTint.infoText),
                      const SizedBox(width: 9),
                      // "All drivers verified" was printed here unconditionally
                      // — nothing in the offer payload was checked before
                      // asserting it. A customer chooses a stranger to get into
                      // a car with on the strength of a line like that, so it
                      // now says what the platform actually does rather than
                      // making a promise about each driver on the list.
                      Text(
                        _t('Drivers are checked before they can accept',
                            'ڈرائیور قبول کرنے سے پہلے جانچے جاتے ہیں'),
                        style: AppType.listTitle.copyWith(
                          fontSize: 16,
                          color: AppText.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                        AppSizes.sidePadding, 0, AppSizes.sidePadding, 20),
                    children: offers.map(_offerCard).toList(growable: false),
                  ),
                ),
                ],
              ],
            ),
          ),
          if (waiting)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: SafeArea(top: false, child: _waitingCard()),
            ),
        ],
      ),
    );
  }

  /// The route behind the offers, or a plain surface when this screen was
  /// pushed without coordinates.
  Widget _backdrop({required bool waiting}) {
    final points = _mapPoints;
    if (points.length < 2) {
      return const ColoredBox(color: AppTint.mapBackdrop);
    }

    return UdMap(
      controller: _mapController,
      initialCenter: widget.pickupPoint ?? points.first,
      zoom: widget.pickupPoint != null ? _searchZoom : AppConfig.defaultMapZoom,
      // Held still while searching, so the searching rings — drawn over the
      // middle of the screen — stay on the pickup. Once offers arrive the map
      // can be moved again, to check where a driver is coming from.
      interactive: !waiting,
      showMyLocation: false,
      polylines: [
        UdPolyline(
          id: 'offer-route-casing',
          points: points,
          color: AppColors.primary,
          width: 9,
        ),
        UdPolyline(
          id: 'offer-route',
          points: points,
          color: AppColors.secondary,
          width: 5,
        ),
      ],
      circles: [
        // The area the request went to. Static, not a pulsing sweep: an
        // animation here would rebuild the whole map every frame, and on the
        // cheap phones most of these customers use that stutter costs more
        // than the effect is worth.
        if (widget.pickupPoint != null)
          UdCircle(
            id: 'offer-search-radius',
            centre: widget.pickupPoint!,
            radiusMetres: _searchRadiusKm * 1000,
          ),
      ],
      markers: [
        // The drivers the fare went out to, drawn the same way Home draws
        // them — cars lying on the road, pointing where they are facing.
        for (final vehicle in _nearby)
          UdMarker(
            id: 'offer-nearby-${vehicle.id}',
            position: vehicle.point,
            sprite: vehicle.sprite,
            headingDegrees: vehicle.headingDegrees,
          ),
        if (widget.pickupPoint != null)
          UdMarker(
            id: 'offer-pickup',
            position: widget.pickupPoint!,
            label: widget.pickup,
          ),
        if (widget.destinationPoint != null)
          UdMarker(
            id: 'offer-destination',
            position: widget.destinationPoint!,
            label: widget.destination,
            hue: UdMarkerHue.danger,
          ),
      ],
    );
  }

  /// Two lime rings that grow out of the pickup and fade, while drivers are
  /// being asked. The map is centred on the pickup and held still while
  /// searching, so the middle of the screen is the pickup.
  Widget _searchPulse() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide * 0.78;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            Widget ring(double phase) {
              final t = (_pulse.value + phase) % 1.0;
              return Opacity(
                opacity: (1 - t) * 0.45,
                child: Transform.scale(
                  scale: 0.12 + t * 0.88,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      color: AppColors.limeLine,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }

            return Center(
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [ring(0), ring(0.5)],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// What the customer sees while nobody has answered yet.
  ///
  /// One small strip at the bottom of the map: status, elapsed clock and the
  /// customer's own offer, under a thin working bar. Small on purpose, so the
  /// route and the drivers around it stay visible. Deliberately not a
  /// countdown: the request stays open for an hour, and a bar draining to zero
  /// would say it is about to expire.
  Widget _waitingCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(18),
        boxShadow: AppShadows.panel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Working, not counting down: the request stays open for an hour.
          const LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: AppColors.surfaceAlt,
            color: AppColors.limeLine,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: AppRadii.all(12),
                  ),
                  child: const Icon(Icons.search_rounded,
                      size: 19, color: AppColors.navy),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_t('Searching for drivers', 'ڈرائیورز تلاش کیے جا رہے ہیں')}'
                        ' · $_elapsed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: AppText.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_t('Your offer', 'آپ کی پیشکش')} · ${widget.vehicleName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'PKR ${NumberFormat('#,###').format(_offer)}',
                  style: AppType.listTitle.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One driver's offer.
  ///
  /// Vehicle on the left, the driver's face top right, the fare large in the
  /// middle. The fare is what the customer is choosing between, so it is the
  /// biggest thing on the card; the two photographs are how they recognise the
  /// car and the person at the kerb.
  ///
  /// Rating and ride count are shown only when an admin has turned them on. On
  /// a new platform they are 0.00 and 0 for everybody, and a zero beside a name
  /// reads as *a bad driver* rather than a new one.
  Widget _offerCard(LiveDriverOffer offer) {
    final seconds = _secondsLeft(offer);
    final busy = _approvingOfferId == offer.id;
    final blocked = busy || seconds <= 0;
    final fields = OfferCardFields.current;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.largeCard),
        boxShadow: AppShadows.panel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fields.vehiclePhoto)
                _OfferVehiclePhoto(
                  offer: offer,
                  imageUrl: _vehicleImageFor(offer),
                  showPlate: fields.plate,
                  token: _mediaToken,
                ),
              if (fields.vehiclePhoto) const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                NumberFormat('#,###')
                                    .format(offer.finalAmount.round()),
                                style: AppType.price.copyWith(
                                  fontSize: 30,
                                  letterSpacing: -0.9,
                                  color: AppText.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'PKR  ·  arrives in '
                                '${offer.estimatedArrivalMinutes} min',
                                style: AppType.caption.copyWith(
                                  color: AppText.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (fields.driverPhoto)
                          _OfferDriverPhoto(offer: offer, token: _mediaToken),
                      ],
                    ),

                    const SizedBox(height: 9),
                    Text(
                      offer.driverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontSize: 15,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      offer.vehicle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppText.secondary,
                      ),
                    ),

                    // Only when they mean something.
                    if (fields.rating || fields.rides) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (fields.rating) ...[
                            const Icon(Icons.star_rounded,
                                size: 16, color: AppTint.star),
                            const SizedBox(width: 4),
                            Text(
                              offer.driverRating.toStringAsFixed(1),
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppText.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (fields.rides)
                            Text(
                              '${offer.completedTrips} rides',
                              style: AppType.caption.copyWith(
                                color: AppText.secondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (offer.message != null && offer.message!.trim().isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              offer.message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.small.copyWith(color: AppText.secondary),
            ),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              // Both flexes stated.
              //
              // Decline had none, so it took the default of 1 against Accept's
              // 16 — a seventeenth of the row, which is how "Decline" ended up
              // printed one letter per line. A ratio needs both numbers; giving
              // one and leaving the other implicit is not a ratio.
              // Decline stays live after the window closes: an offer the
              // customer no longer wants should still be dismissable.
              Expanded(
                flex: 10,
                child: _DeclineButton(
                  label: _t('Decline', 'مسترد'),
                  onTap: busy ? null : () => _declineOffer(offer.revision),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 14,
                // The decision window, drawn along the bottom edge of Accept.
                //
                // This widget has been in the file all along with nothing
                // building it — the card used a plain FilledButton, so the
                // ten seconds ran down with nothing on screen saying so, and
                // the button simply turned into "Expired".
                child: _AcceptButton(
                  label: seconds > 0
                      ? _t('Accept', 'قبول کریں')
                      : _t('Expired', 'وقت ختم'),
                  busy: busy,
                  remaining: seconds / _decisionSeconds,
                  onTap: blocked ? null : () => _approveOffer(offer),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showBookingConfirmed(LiveBooking booking, {int? etaMinutes}) async {
    if (!mounted) return;
    final controller = AppControllerScope.of(context);

    // Straight to the map, without a sheet in between.
    //
    // The moment a driver is confirmed the only question left is where the car
    // is and when it arrives, and that is a screen, not a summary. The driver,
    // vehicle, fare and OTP are all on the tracking screen anyway, so the sheet
    // was a list of things the customer had to dismiss before they could see
    // the one thing they wanted.
    //
    // It is still shown if the trip cannot be opened — better a summary than
    // nothing at all.
    if (await _openTracking(controller, booking)) return;
    if (!mounted) return;
    await showUdSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showHandle: false,
      builder: (_) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 58),
              const SizedBox(height: 12),
              Text(_t('Driver approved', 'ڈرائیور منظور ہو گیا'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              _ResultLine(label: _t('Driver', 'ڈرائیور'), value: booking.driverName ?? '-'),
              _ResultLine(label: _t('Vehicle', 'گاڑی'), value: booking.vehicle ?? '-'),
              _ResultLine(label: _t('Registration', 'رجسٹریشن'), value: booking.registrationNumber ?? '-'),
              _ResultLine(label: _t('Arrival', 'پہنچنے کا وقت'), value: etaMinutes == null ? _t('On the way', 'راستے میں') : '~$etaMinutes min'),
              _ResultLine(label: _t('Total fare', 'کل کرایہ'), value: 'PKR ${NumberFormat('#,###').format(booking.totalAmount)}'),
              _ResultLine(label: _t('Trip OTP', 'ٹرپ او ٹی پی'), value: booking.tripOtp ?? '-'),
              const SizedBox(height: 16),
              Row(
                children: [
                  if ((booking.driverPhone ?? '').trim().isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final uri = Uri(scheme: 'tel', path: booking.driverPhone!.trim());
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                        icon: const Icon(Icons.call_rounded),
                        label: Text(_t('Call Driver', 'ڈرائیور کو کال کریں')),
                      ),
                    ),
                  if ((booking.driverPhone ?? '').trim().isNotEmpty) const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final repo = TripOperationsRepository(controller.apiClient);
                        try {
                          final trips = await repo.customerTrips();
                          final trip = trips.firstWhere((x) => x.bookingId == booking.id);
                          if (!context.mounted) return;
                          navigator.pop();
                          navigator.pushReplacement(MaterialPageRoute(
                            builder: (_) => CustomerFullScreenTrackingScreen(trip: trip, repository: repo, tripOtp: booking.tripOtp),
                          ));
                        } catch (_) {
                          if (!context.mounted) return;
                          navigator.pop();
                          navigator.popUntil((route) => route.isFirst);
                        }
                      },
                      icon: const Icon(Icons.navigation_rounded),
                      label: Text(_t('Track Driver', 'ڈرائیور کو ٹریک کریں')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

/// The red "Cancel request" pill above the heading.
/// A round stepper button for the raise-fare sheet.
class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.background : AppColors.surfaceAlt,
      shape: enabled
          ? const CircleBorder(
              side: BorderSide(color: AppColors.borderStrong, width: 1.5),
            )
          : const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(
            icon,
            size: 24,
            color: enabled ? AppColors.navy : AppText.disabled,
          ),
        ),
      ),
    );
  }
}

/// The way out of a search that is still running.
///
/// Full width beside the back arrow, not a small icon in the corner: leaving
/// this screen without cancelling leaves a request open on the server, and the
/// customer needs the deliberate action to be the obvious one.
class _CancelPill extends StatelessWidget {
  const _CancelPill({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdButton(
        label: label,
        icon: Icons.close_rounded,
        variant: UdButtonVariant.danger,
        size: UdButtonSize.small,
        busy: busy,
        onPressed: onTap,
      );
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => UdButton.outline(
        label: label,
        size: UdButtonSize.small,
        onPressed: onTap,
      );
}

/// Accept, with the decision window draining across it.
class _AcceptButton extends StatelessWidget {
  const _AcceptButton({
    required this.label,
    required this.busy,
    required this.remaining,
    required this.onTap,
  });

  final String label;
  final bool busy;

  /// 1.0 at the start of the window, 0.0 when it closes.
  final double remaining;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = remaining.isNaN ? 0.0 : remaining.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: AppRadii.all(AppRadii.cta),
      child: Stack(
        children: [
          // The button is solid lime, full width, always.
          //
          // It used to drain from full colour to 38% opacity as the window ran
          // down, which meant the main action on the screen spent most of its
          // life washed out — and a half-faded button reads as disabled, which
          // is the opposite of what it is.
          Positioned.fill(
            child: ColoredBox(
              color: onTap == null ? AppColors.surfaceAlt : AppColors.brand,
            ),
          ),

          // The countdown is a thin bar along the bottom edge instead. It still
          // shows the time draining without taking the colour out of the thing
          // the customer is meant to press.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 4,
            child: Row(
              children: [
                Expanded(
                  flex: (fraction * 1000).round().clamp(1, 1000),
                  child: const ColoredBox(color: AppColors.navy),
                ),
                Expanded(
                  flex: ((1 - fraction) * 1000).round().clamp(1, 1000),
                  child: const ColoredBox(color: AppColors.limeLine),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: AppSizes.buttonSmall,
                width: double.infinity,
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppText.onBrand,
                          ),
                        )
                      : Text(
                          label,
                          style: AppType.buttonSm.copyWith(
                            color: onTap == null
                                ? AppText.disabled
                                : AppText.onBrand,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => UdKeyValue(label: label, value: value);
}

/// The vehicle on an offer card.
///
/// The driver's own photograph when they gave one, the category picture when
/// they did not, and an icon when neither exists. A customer at a kerb is
/// looking for a particular car — a stock photograph of a different car in the
/// same class helps them less than it appears to, but it still beats a grey box.
class _OfferVehiclePhoto extends StatelessWidget {
  const _OfferVehiclePhoto({
    required this.offer,
    required this.imageUrl,
    required this.showPlate,
    required this.token,
  });

  final LiveDriverOffer offer;
  final String? imageUrl;
  final bool showPlate;

  /// Bearer token, for when [imageUrl] is the authenticated document route.
  final String? token;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: imageUrl == null
                  ? const Icon(Icons.directions_car_rounded,
                      size: 42, color: AppText.disabled)
                  : Image.network(
                      imageUrl!,
                      cacheWidth: 600,
                      fit: BoxFit.cover,
                      // The document route is authenticated; the category
                      // picture is not. Sending the header either way is
                      // harmless and saves branching on which kind of URL
                      // this is.
                      headers: token == null
                          ? null
                          : {'Authorization': 'Bearer $token'},
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.directions_car_rounded,
                        size: 42,
                        color: AppText.disabled,
                      ),
                    ),
            ),
          ),

          // The plate, over the picture rather than under it.
          //
          // It is the one thing the customer reads off the car itself, and
          // putting it on the photograph keeps the two together.
          if (showPlate && offer.registrationNumber.trim().isNotEmpty)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  offer.registrationNumber,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The driver's face, top right of the offer card.
///
/// Their approved selfie, fetched through a route scoped to this offer — the
/// customer may see the face of somebody who has offered to drive *them*, and
/// nobody else. Initials when there is no photograph: a broken-image glyph
/// where a face should be is worse than a letter.
class _OfferDriverPhoto extends StatelessWidget {
  const _OfferDriverPhoto({required this.offer, required this.token});

  final LiveDriverOffer offer;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final initial = offer.driverName.trim().isEmpty
        ? 'D'
        : offer.driverName.trim().characters.first.toUpperCase();

    final fallback = Text(
      initial,
      style: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: AppColors.secondary,
      ),
    );

    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTint.brand,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: offer.driverHasPhoto
          ? Image.network(
              '${ApiConfig.baseUrl}/api/v1/offers/${offer.id}/driver-photo',
              cacheWidth: 192,
              fit: BoxFit.cover,
              width: 46,
              height: 46,
              headers: token == null ? null : {'Authorization': 'Bearer $token'},
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }
}
