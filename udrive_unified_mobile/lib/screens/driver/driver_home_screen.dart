import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking/trip_operations_repository.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import '../operations/live_trip_navigation_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

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
  bool _isOnline = true;
  final Map<String, _RecentFareSent> _recentFares = {};

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
      const Duration(seconds: 10),
      (_) => _loadAcceptedTrips(silent: true),
    );
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) => _publishPresence());
    _marketplaceRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshNearbyRequests());
    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _recentFares.isEmpty) return;
      final now = DateTime.now();
      final expired = _recentFares.entries.where((e) => !e.value.visibleUntil.isAfter(now)).map((e) => e.key).toList();
      if (expired.isNotEmpty) {
        setState(() { for (final id in expired) { _recentFares.remove(id); } });
        _refreshNearbyRequests();
      } else {
        setState(() {});
      }
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
    if (!_isOnline || !mounted) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      await AppControllerScope.of(context).apiClient.postJson('/api/v1/driver/marketplace/presence', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _refreshNearbyRequests() async {
    if (!_isOnline || !mounted) return;
    final controller = AppControllerScope.of(context);
    if (!controller.driverApproved) return;
    await _publishPresence();
    if (!mounted) return;
    await controller.loadDriverMarketplace();
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

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
        children: [
          _CompactDriverHeader(
            driverName: controller.currentUserName,
            requestCount: requests.length,
            hasActiveTrip: activeTrip != null,
          ),
          const SizedBox(height: 10),
          if (activeTrip != null) ...[
            _LiveRideHeroCard(
              trip: activeTrip,
              onOpen: () => _openAcceptedRide(activeTrip),
            ),
            const SizedBox(height: 10),
          ],
          if (_recentFares.isNotEmpty) ...[
            ..._recentFares.values.map((sent) {
              LiveDriverRideOfferStatus? liveStatus;
              for (final offer in controller.liveDriverRideOfferStatuses) {
                if (offer.rideRequestId == sent.rideRequestId) {
                  liveStatus = offer;
                  break;
                }
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecentFareSentCard(sent: sent, status: liveStatus),
              );
            }),
            const SizedBox(height: 2),
          ],
          _CompactSectionRow(
            title: activeTrip == null ? 'Nearby rides' : 'Next rides',
            subtitle: activeTrip == null
                ? 'Live requests within 5 KM'
                : 'Unlock within 1 KM of destination',
            count: requests.length,
          ),
          const SizedBox(height: 7),
          if (!_isOnline)
            const _DriverHomeInfoCard(
              icon: Icons.power_settings_new_rounded,
              title: 'Driver is offline',
              message: 'Use the top menu to go online.',
            )
          else if (!controller.driverApproved)
            const _DriverHomeInfoCard(
              icon: Icons.verified_user_outlined,
              title: 'Driver approval required',
              message: 'Nearby rides start automatically after approval.',
            )
          else if (verifiedVehicles.isEmpty)
            const _DriverHomeInfoCard(
              icon: Icons.directions_car_outlined,
              title: 'Verified vehicle required',
              message: 'Verify at least one vehicle before sending fares.',
            )
          else if (requests.isEmpty)
            _CompactWaitingState(
              hasActiveTrip: activeTrip != null,
              onRefresh: _refreshNearbyRequests,
            )
          else
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DashboardRequestCard(
                  request: request,
                  enabled: verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                  onAccept: () => _showOffer(request, verifiedVehicles),
                  onMap: () => _openRequestMap(request),
                  onReject: () => _rejectRequest(request),
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (controller.marketplaceError != null) ...[
            const SizedBox(height: 8),
            _DriverHomeInfoCard(
              icon: Icons.cloud_off_rounded,
              title: 'Live refresh issue',
              message: controller.marketplaceError!,
              actionLabel: 'Retry',
              onAction: _refresh,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openRequestMap(LiveRideRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _DriverRequestRouteMap(request: request)),
    );
  }

  Future<void> _openOfferMap(LiveDriverRideOfferStatus offer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _DriverOfferRouteMap(offer: offer)),
    );
  }

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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          4,
          18,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Send your fare', 'اپنا کرایہ بھیجیں'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              '${request.pickupLabel} → ${request.destinationLabel}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${selectedVehicle.make} ${selectedVehicle.model} · ${selectedVehicle.registrationNumber}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _t('Your fare (PKR)', 'آپ کا کرایہ (PKR)'),
                prefixIcon: const Icon(Icons.payments_rounded),
                helperText: request.customerOffer > 0
                    ? 'Customer estimate: PKR ${NumberFormat('#,###').format(request.customerOffer)}'
                    : null,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final parsedAmount = double.tryParse(amount.text.trim());
                  if (parsedAmount == null || parsedAmount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid fare.')),
                    );
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
                icon: const Icon(Icons.send_rounded),
                label: Text(_t('Send Fare', 'کرایہ بھیجیں')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectRequest(LiveRideRequest request) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Reject request?', 'درخواست مسترد کریں؟')),
        content: Text(_t(
          'This request will be removed only from your queue. Other eligible Drivers can still respond.',
          'یہ درخواست صرف آپ کی فہرست سے ہٹے گی۔ دوسرے اہل ڈرائیور جواب دے سکیں گے۔',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Reject'),
          ),
        ],
      ),
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

  static const _closedStatuses = {'Completed', 'Cancelled', 'NoShow'};
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

class _CompactDriverHeader extends StatelessWidget {
  const _CompactDriverHeader({required this.driverName, required this.requestCount, required this.hasActiveTrip});
  final String driverName;
  final int requestCount;
  final bool hasActiveTrip;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E9ED))),
    child: Row(children: [
      Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF5F1), borderRadius: BorderRadius.circular(12)), child: Icon(hasActiveTrip ? Icons.navigation_rounded : Icons.local_taxi_rounded, color: AppColors.primaryDark, size: 20)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hi ${driverName.split(' ').first}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
        Text(hasActiveTrip ? 'Your active ride is live' : 'Nearby rides update automatically', style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF4F7F8), borderRadius: BorderRadius.circular(999)), child: Text('$requestCount nearby', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.navy))),
    ]),
  );
}

class _CompactSectionRow extends StatelessWidget {
  const _CompactSectionRow({required this.title, required this.subtitle, required this.count});
  final String title;
  final String subtitle;
  final int count;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)), Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.muted))])),
    if (count > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFEAF5F1), borderRadius: BorderRadius.circular(999)), child: Text('$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primaryDark))),
  ]);
}

class _RecentFareSentCard extends StatelessWidget {
  const _RecentFareSentCard({required this.sent, required this.status});
  final _RecentFareSent sent;
  final LiveDriverRideOfferStatus? status;
  @override
  Widget build(BuildContext context) {
    final seconds = sent.visibleUntil.difference(DateTime.now()).inSeconds.clamp(0, 20);
    final approved = status?.isApproved == true;
    final rejected = status?.isClosed == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF0FAF6), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.success.withValues(alpha: .25))),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.success.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.check_rounded, color: AppColors.success, size: 19)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(approved ? 'APPROVED · ride confirmed' : rejected ? 'NOT SELECTED' : 'Fare sent · waiting for customer', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.navy)),
          Text('${sent.pickupLabel} → ${sent.destinationLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('PKR ${NumberFormat('#,###').format(sent.amount)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.navy)),
          Text(approved ? 'LIVE' : rejected ? 'CLOSED' : '${seconds}s', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.success)),
        ]),
      ]),
    );
  }
}

class _CompactWaitingState extends StatelessWidget {
  const _CompactWaitingState({required this.hasActiveTrip, required this.onRefresh});
  final bool hasActiveTrip;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(color: const Color(0xFFF8FAFB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE7ECEF))),
    child: Row(children: [
      Icon(hasActiveTrip ? Icons.route_rounded : Icons.radar_rounded, color: AppColors.primaryDark, size: 21),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(hasActiveTrip ? 'Next rides locked for now' : 'No nearby ride right now', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.navy)),
        Text(hasActiveTrip ? 'They unlock within 1 KM of destination.' : 'New 5 KM requests appear here automatically.', style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
      ])),
      IconButton(onPressed: onRefresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, size: 20)),
    ]),
  );
}

class _DriverCommandHeader extends StatelessWidget {
  const _DriverCommandHeader({
    required this.driverName,
    required this.isOnline,
    required this.activeTrip,
    required this.requestCount,
    required this.pendingOfferCount,
    required this.onOnlineChanged,
  });

  final String driverName;
  final bool isOnline;
  final MobileTrip? activeTrip;
  final int requestCount;
  final int pendingOfferCount;
  final ValueChanged<bool> onOnlineChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ready to drive, ${driverName.split(' ').first}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(activeTrip == null ? 'Nearby rides arrive automatically' : 'Active ride is live', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Switch.adaptive(value: isOnline, onChanged: onOnlineChanged),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _HeaderMetric(icon: Icons.radar_rounded, value: '$requestCount', label: 'Nearby'),
                const SizedBox(width: 8),
                _HeaderMetric(icon: Icons.local_offer_rounded, value: '$pendingOfferCount', label: 'Waiting'),
                const SizedBox(width: 8),
                _HeaderMetric(icon: activeTrip == null ? Icons.check_circle_outline_rounded : Icons.navigation_rounded, value: activeTrip == null ? 'READY' : 'LIVE', label: activeTrip == null ? 'Status' : 'Current ride'),
              ],
            ),
          ],
        ),
      );
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .09), borderRadius: BorderRadius.circular(13)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(height: 5),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 9.5)),
            ],
          ),
        ),
      );
}

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle({required this.icon, required this.title, required this.subtitle, required this.trailing});
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE8F5F0), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 19, color: AppColors.primaryDark)),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.muted))])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFF1F5F8), borderRadius: BorderRadius.circular(999)), child: Text(trailing, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 11))),
        ],
      );
}

class _LiveRideHeroCard extends StatelessWidget {
  const _LiveRideHeroCard({required this.trip, required this.onOpen});
  final MobileTrip trip;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: const Color(0xFFEAF7F2), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.primary.withValues(alpha: .25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.navigation_rounded, color: AppColors.primaryDark), const SizedBox(width: 8), const Expanded(child: Text('ACTIVE RIDE', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 12))), StatusPill(label: trip.tripStatus, color: AppColors.primary)]),
          const SizedBox(height: 10),
          _RouteLine(icon: Icons.trip_origin_rounded, text: trip.pickupLabel, color: AppColors.primary),
          const SizedBox(height: 5),
          _RouteLine(icon: Icons.location_on_rounded, text: trip.destinationLabel, color: AppColors.danger),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: Text('${trip.customerName} · ${trip.passengerCount} passenger${trip.passengerCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))), Text('PKR ${NumberFormat('#,###').format(trip.fare)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy))]),
          const SizedBox(height: 11),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.navigation_rounded), label: const Text('Open live ride'))),
        ]),
      );
}

class _NextRideUnlockBanner extends StatelessWidget {
  const _NextRideUnlockBanner();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: const Color(0xFFFFF7E7), borderRadius: BorderRadius.circular(13)),
        child: const Row(children: [Icon(Icons.next_plan_rounded, size: 18, color: AppColors.warning), SizedBox(width: 8), Expanded(child: Text('Next rides stay hidden during this trip. They unlock automatically when you are within 1 KM of the destination; the same 5 KM pickup-radius rule then applies.', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.navy)))]),
      );
}

class _WaitingForNearbyRide extends StatelessWidget {
  const _WaitingForNearbyRide({required this.hasActiveTrip, required this.onRefresh});
  final bool hasActiveTrip;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7ECEF))),
        child: Column(children: [
          const SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 12),
          Text(hasActiveTrip ? 'Next rides will appear near destination' : 'Searching for nearby rides…', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.navy)),
          const SizedBox(height: 4),
          Text(hasActiveTrip ? 'The system unlocks new requests within 1 KM of your current destination.' : 'Only pickups inside your live 5 KM radius are sent here.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh now')),
        ]),
      );
}

class _DriverHomeInfoCard extends StatelessWidget {
  const _DriverHomeInfoCard({required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF7F9FB), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E9ED))),
        child: Row(children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 2), Text(message, style: const TextStyle(fontSize: 10.5, color: AppColors.muted))])), if (onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel ?? 'Open'))]),
      );
}

class _DriverFareStatusCard extends StatelessWidget {
  const _DriverFareStatusCard({required this.offer, required this.onMap, this.onOpenRide});
  final LiveDriverRideOfferStatus offer;
  final VoidCallback onMap;
  final VoidCallback? onOpenRide;
  @override
  Widget build(BuildContext context) {
    final approved = offer.isApproved;
    final pending = offer.isPending;
    final statusColor = approved ? AppColors.success : pending ? AppColors.warning : AppColors.muted;
    final statusText = approved ? 'APPROVED' : pending ? 'WAITING FOR CUSTOMER' : 'CLOSED / NOT SELECTED';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: approved ? const Color(0xFFF0FAF6) : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: approved ? AppColors.success.withValues(alpha: .35) : const Color(0xFFE5E9ED))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(offer.customerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.navy))), StatusPill(label: statusText, color: statusColor)]),
        const SizedBox(height: 7),
        _RouteLine(icon: Icons.trip_origin_rounded, text: offer.pickupLabel, color: AppColors.primary),
        const SizedBox(height: 4),
        _RouteLine(icon: Icons.location_on_rounded, text: offer.destinationLabel, color: AppColors.danger),
        const SizedBox(height: 9),
        Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: offer.isWholeVehicle ? const Color(0xFFFFF3E8) : const Color(0xFFEAF4FF), borderRadius: BorderRadius.circular(999)), child: Text(offer.isWholeVehicle ? 'WHOLE VEHICLE' : '${offer.seatsRequested} SEAT${offer.seatsRequested == 1 ? '' : 'S'}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))), const Spacer(), Text('Your fare  PKR ${NumberFormat('#,###').format(offer.driverAmount)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 12))]),
        const SizedBox(height: 9),
        Row(children: [OutlinedButton.icon(onPressed: onMap, icon: const Icon(Icons.map_rounded, size: 17), label: const Text('Map')), if (approved && onOpenRide != null) ...[const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: onOpenRide, icon: const Icon(Icons.navigation_rounded, size: 17), label: const Text('Open live ride')))] else const Spacer(), if (pending) const Text('Auto checking approval…', style: TextStyle(fontSize: 9.5, color: AppColors.muted, fontWeight: FontWeight.w700))]),
      ]),
    );
  }
}

class _DriverOfferRouteMap extends StatelessWidget {
  const _DriverOfferRouteMap({required this.offer});
  final LiveDriverRideOfferStatus offer;
  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(offer.pickupLatitude, offer.pickupLongitude);
    final destination = LatLng(offer.destinationLatitude, offer.destinationLongitude);
    final center = LatLng((pickup.latitude + destination.latitude) / 2, (pickup.longitude + destination.longitude) / 2);
    return Scaffold(
      appBar: AppBar(title: const Text('Ride route')),
      body: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 9.5),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.udrive.mobile'),
          PolylineLayer(polylines: [Polyline(points: [pickup, destination], strokeWidth: 4, color: AppColors.primary)]),
          MarkerLayer(markers: [Marker(point: pickup, width: 46, height: 46, child: const Icon(Icons.trip_origin_rounded, color: AppColors.primary, size: 34)), Marker(point: destination, width: 48, height: 48, child: const Icon(Icons.location_on_rounded, color: AppColors.danger, size: 40))]),
        ],
      ),
    );
  }
}

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
      appBar: AppBar(title: const Text('Pickup & Destination')),
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
                  Polyline(points: [pickup, destination], strokeWidth: 4, color: AppColors.primary),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(point: pickup, width: 48, height: 48, child: const Icon(Icons.trip_origin_rounded, color: AppColors.primary, size: 36)),
                  Marker(point: destination, width: 48, height: 48, child: const Icon(Icons.location_on_rounded, color: AppColors.danger, size: 42)),
                ],
              ),
            ],
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 18,
            child: Card(
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(request.pickupLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text('→ ${request.destinationLabel}', style: const TextStyle(fontWeight: FontWeight.w800)),
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

class _DashboardRequestCard extends StatelessWidget {
  const _DashboardRequestCard({
    required this.request,
    required this.enabled,
    required this.onAccept,
    required this.onMap,
    required this.onReject,
  });

  final LiveRideRequest request;
  final bool enabled;
  final VoidCallback onAccept;
  final VoidCallback onMap;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(request.customerName);
    return PremiumCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE8F5F0),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      DateFormat('dd MMM · h:mm a').format(request.pickupAt),
                      style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _RouteLine(icon: Icons.trip_origin_rounded, text: request.pickupLabel, color: AppColors.primary),
                const SizedBox(height: 3),
                _RouteLine(icon: Icons.location_on_rounded, text: request.destinationLabel, color: AppColors.danger),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: request.bookingType.toLowerCase().contains('whole')
                            ? const Color(0xFFFFF3E8)
                            : const Color(0xFFEAF4FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        request.bookingType.toLowerCase().contains('whole')
                            ? 'WHOLE VEHICLE'
                            : '${request.seatsRequested} SEAT${request.seatsRequested == 1 ? '' : 'S'}',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.navy),
                      ),
                    ),
                    const SizedBox(width: 7),
                    TextButton.icon(
                      onPressed: onMap,
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), minimumSize: Size.zero),
                      icon: const Icon(Icons.map_rounded, size: 15),
                      label: const Text('Map', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PKR ${NumberFormat('#,###').format(request.customerOffer)}',
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _SmallAction(
                      icon: Icons.close_rounded,
                      color: AppColors.danger,
                      onTap: enabled ? onReject : null,
                    ),
                    const SizedBox(width: 6),
                    _SmallAction(
                      icon: Icons.check_rounded,
                      color: AppColors.success,
                      onTap: enabled ? onAccept : null,
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

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'CU' : value;
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.color, this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: onTap == null ? const Color(0xFFF1F3F5) : color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 35,
            height: 32,
            child: Icon(icon, size: 18, color: onTap == null ? AppColors.muted : color),
          ),
        ),
      );
}

class _LatestAssignment extends StatelessWidget {
  const _LatestAssignment({required this.booking, required this.onTap});
  final LiveBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: onTap,
        padding: const EdgeInsets.all(13),
        color: const Color(0xFFF3F8FF),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDCEAFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.route_rounded, color: Color(0xFF275FC6)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${booking.pickupLabel} → ${booking.destinationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('dd MMM · h:mm a').format(booking.pickupAt)} · ${booking.bookingReference}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            StatusPill(label: booking.status, color: AppColors.info),
          ],
        ),
      );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(color: colors.first.withValues(alpha: .18), blurRadius: 12, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onTap});
  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = package.status.trim().toLowerCase();
    final color = status == 'active' || status == 'approved'
        ? AppColors.success
        : status == 'rejected'
            ? AppColors.danger
            : AppColors.warning;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.landscape_rounded, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                const SizedBox(height: 3),
                Text('${package.startingCity} → ${package.destination}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(label: package.status, color: color),
        ],
      ),
    );
  }
}


class _AcceptedRideCard extends StatelessWidget {
  const _AcceptedRideCard({required this.trip, required this.onStart});
  final MobileTrip trip;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final initials = trip.customerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final started = trip.tripStatus != 'DriverAccepted';
    return PremiumCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFEAF8F2),
            child: Text(
              initials.isEmpty ? 'C' : initials,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                      ),
                    ),
                    Text(
                      'PKR ${trip.fare.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${trip.pickupLabel} → ${trip.destinationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('dd MMM, h:mm a').format(trip.pickupAt.toLocal())} · ${trip.passengerCount} passenger(s)',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              minimumSize: const Size(0, 38),
            ),
            child: Text(started ? 'Open map' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests({required this.onRefresh});
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => PremiumCard(
        color: const Color(0xFFF7FAF9),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: AppColors.muted),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No pending Customer request right now.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
      );
}

class _DriverAvailabilityCard extends StatelessWidget {
  const _DriverAvailabilityCard({
    required this.isOnline,
    required this.onChanged,
    required this.nextTrip,
    required this.onOpenTrip,
  });
  final bool isOnline;
  final ValueChanged<bool> onChanged;
  final MobileTrip? nextTrip;
  final VoidCallback? onOpenTrip;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (isOnline ? AppColors.primary : Colors.white24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(isOnline ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isOnline ? 'You are online' : 'You are offline', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    Text(isOnline ? 'New ride requests can reach you' : 'Go online when you are ready', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
                Switch(value: isOnline, onChanged: onChanged),
              ],
            ),
            if (nextTrip != null) ...[
              const Divider(color: Colors.white24, height: 22),
              InkWell(
                onTap: onOpenTrip,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Next trip', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
                      Text('${nextTrip!.pickupLabel} → ${nextTrip!.destinationLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      Text(DateFormat('EEE, dd MMM · hh:mm a').format(nextTrip!.pickupAt), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  ]),
                ),
              ),
            ],
          ],
        ),
      );
}
