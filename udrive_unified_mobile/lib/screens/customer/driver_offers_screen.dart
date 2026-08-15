import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/booking/trip_operations_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/booking_models.dart';
import '../operations/live_trip_navigation_screen.dart';

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({
    required this.rideRequestId,
    required this.pickup,
    required this.destination,
    required this.customerOffer,
    required this.vehicleName,
    this.autoMatch = false,
    super.key,
  });

  final String rideRequestId;
  final String pickup;
  final String destination;
  final int customerOffer;
  final String vehicleName;
  final bool autoMatch;

  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen> {
  Timer? _poller;
  Timer? _ticker;
  bool _loading = true;
  bool _resolved = false;
  String? _approvingOfferId;

  final Map<String, DateTime> _customerDecisionDeadline = <String, DateTime>{};
  final Set<String> _declinedOfferIds = <String>{};
  final Set<String> _declineInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poller = Timer.periodic(const Duration(seconds: 2), (_) => _refresh(silent: true));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _resolved) return;
      _expireCustomerWindows();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _ticker?.cancel();
    super.dispose();
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

  void _registerDecisionWindows(List<LiveDriverOffer> offers) {
    final now = DateTime.now();
    for (final offer in offers) {
      if (offer.rideRequestId != widget.rideRequestId || _declinedOfferIds.contains(offer.id)) continue;
      _customerDecisionDeadline.putIfAbsent(offer.id, () {
        final localTenSeconds = now.add(const Duration(seconds: 10));
        return offer.expiresAt.isBefore(localTenSeconds) ? offer.expiresAt : localTenSeconds;
      });
    }
  }

  void _expireCustomerWindows() {
    final now = DateTime.now();
    final expired = _customerDecisionDeadline.entries
        .where((e) => !e.value.isAfter(now) && !_declinedOfferIds.contains(e.key))
        .map((e) => e.key)
        .toList(growable: false);
    for (final offerId in expired) {
      _declineOffer(offerId, automatic: true);
    }
  }

  int _secondsLeft(LiveDriverOffer offer) {
    final deadline = _customerDecisionDeadline[offer.id] ?? offer.expiresAt;
    final seconds = deadline.difference(DateTime.now()).inSeconds + 1;
    return seconds.clamp(0, 10);
  }

  List<LiveDriverOffer> _visibleOffers(AppController controller) {
    final now = DateTime.now();
    final offers = controller.liveDriverOffers.where((offer) {
      if (offer.rideRequestId != widget.rideRequestId) return false;
      if (_declinedOfferIds.contains(offer.id)) return false;
      final deadline = _customerDecisionDeadline[offer.id];
      return deadline == null || deadline.isAfter(now);
    }).toList();
    offers.sort((a, b) => a.finalAmount.compareTo(b.finalAmount));
    return offers;
  }

  Future<void> _declineOffer(String offerId, {bool automatic = false}) async {
    if (_declinedOfferIds.contains(offerId) || _declineInFlight.contains(offerId) || _resolved) return;
    _declinedOfferIds.add(offerId);
    _declineInFlight.add(offerId);
    if (mounted) setState(() {});
    try {
      await AppControllerScope.of(context).declineLiveDriverOffer(
        rideRequestId: widget.rideRequestId,
        offerId: offerId,
        countTowardsDriverRejectLimit: !automatic,
      );
    } catch (_) {
      // The server may already have expired the 20-second Driver offer.
      // For the Customer this offer remains dismissed after the 10-second decision window.
    } finally {
      _declineInFlight.remove(offerId);
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
    } catch (_) {
      await controller.refreshCustomerRideState();
      if (!mounted) return;
      if (await _openExistingBookingIfAny(controller)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.marketplaceError ?? 'This offer is no longer available. Please choose another Driver.')),
      );
    } finally {
      if (mounted && !_resolved) setState(() => _approvingOfferId = null);
    }
  }

  Future<bool> _openExistingBookingIfAny(AppController controller) async {
    LiveBooking? booking;
    for (final item in controller.liveBookings) {
      if (item.rideRequestId == widget.rideRequestId) {
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

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    _registerDecisionWindows(controller.liveDriverOffers);
    final offers = _visibleOffers(controller);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_t('Choose a driver', 'ڈرائیور منتخب کریں')),
        actions: [
          IconButton(
            tooltip: _t('Refresh', 'تازہ کریں'),
            onPressed: controller.marketplaceBusy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            _routeSummary(offers.length),
            const SizedBox(height: 12),
            if (_loading && offers.isEmpty)
              _waitingCard()
            else if (offers.isEmpty)
              _waitingCard()
            else
              ...offers.map(_offerCard),
          ],
        ),
      ),
    );
  }

  Widget _routeSummary(int offerCount) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 7),
                Text(
                  _t('Verified driver offers', 'تصدیق شدہ ڈرائیور آفرز'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '$offerCount ${offerCount == 1 ? 'offer' : 'offers'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.pickup}  →  ${widget.destination}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              _t(
                'Compare fares and arrival time. Each new offer gives you 10 seconds to approve or reject.',
                'کرایہ اور پہنچنے کا وقت دیکھیں۔ ہر نئی آفر پر آپ کے پاس منظور یا مسترد کرنے کے لیے 10 سیکنڈ ہیں۔',
              ),
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35),
            ),
          ],
        ),
      );

  Widget _waitingCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            const Icon(Icons.radar_rounded, color: AppColors.primary, size: 34),
            const SizedBox(height: 10),
            Text(
              _t('Waiting for driver fares…', 'ڈرائیورز کے کرایوں کا انتظار ہے…'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 5),
            Text(
              _t('Nearby Drivers can send their fare. New offers appear here automatically.', 'قریبی ڈرائیور اپنا کرایہ بھیج سکتے ہیں۔ نئی آفر یہاں خودکار ظاہر ہوگی۔'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35),
            ),
          ],
        ),
      );

  Widget _offerCard(LiveDriverOffer offer) {
    final seconds = _secondsLeft(offer);
    final busy = _approvingOfferId == offer.id;
    final distanceText = offer.pickupDistanceKm < 0.1
        ? '<0.1 km'
        : '${offer.pickupDistanceKm.toStringAsFixed(1)} km';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E6EA)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
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
                      'PKR ${NumberFormat('#,###').format(offer.finalAmount)}',
                      style: const TextStyle(fontSize: 28, height: 1, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '~${offer.estimatedArrivalMinutes} min to pickup',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.near_me_rounded, size: 15, color: AppColors.muted),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text('$distanceText away', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: seconds <= 3 ? const Color(0xFFFFE9E7) : const Color(0xFFEAF7F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${seconds}s',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: seconds <= 3 ? const Color(0xFFB42318) : AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: AppColors.primary.withValues(alpha: .12),
                child: Text(
                  offer.driverName.isEmpty ? 'D' : offer.driverName.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(offer.driverName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5))),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, color: AppColors.info, size: 16),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offer.vehicle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                    ),
                    if (offer.registrationNumber.isNotEmpty)
                      Text(offer.registrationNumber, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF59E0B)),
                  Text(' ${offer.driverRating.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || seconds <= 0 ? null : () => _declineOffer(offer.id),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: Text(_t('Reject', 'مسترد کریں')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy || seconds <= 0 || _approvingOfferId != null ? null : () => _approveOffer(offer),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_t('Approve', 'منظور کریں')),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
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

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5))),
          ],
        ),
      );
}
