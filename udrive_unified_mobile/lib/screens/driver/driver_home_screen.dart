import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

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
  bool _isOnline = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripRepository ??= TripOperationsRepository(AppControllerScope.of(context).apiClient);
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _loadAcceptedTrips();
    });
    _acceptedRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadAcceptedTrips(silent: true),
    );
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) => _publishPresence());
    _publishPresence();
  }

  @override
  void dispose() {
    _acceptedRefreshTimer?.cancel();
    _presenceTimer?.cancel();
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

  Future<void> _refresh() async {
    final controller = AppControllerScope.of(context);
    await controller.refreshAccount();
    if (controller.driverApproved) {
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
    final activeBookings = controller.liveDriverPackageBookings
        .where((booking) => !_closedStatuses.contains(booking.status))
        .toList()
      ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
    final requests = controller.liveDriverRideRequests.take(5).toList();
    final packages = controller.liveDriverPackages.take(4).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _DriverAvailabilityCard(
            isOnline: _isOnline,
            onChanged: (value) { setState(() => _isOnline = value); if (value) _publishPresence(); },
            nextTrip: _acceptedTrips.isEmpty ? null : _acceptedTrips.first,
            onOpenTrip: _acceptedTrips.isEmpty ? null : () => _openAcceptedRide(_acceptedTrips.first),
          ),
          const SizedBox(height: 14),
          if (_acceptedTrips.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t('Accepted rides', 'قبول شدہ رائیڈز'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Text(
                  '${_acceptedTrips.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ..._acceptedTrips.take(4).map(
              (trip) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _AcceptedRideCard(
                  trip: trip,
                  onStart: () => _openAcceptedRide(trip),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (requests.isEmpty)
            _EmptyRequests(onRefresh: _refresh)
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t('Customer requests', 'کسٹمر درخواستیں'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onNavigate('requests'),
                  child: Text(_t('View all', 'سب دیکھیں')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _DashboardRequestCard(
                  request: request,
                  enabled: verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                  onAccept: () => _showOffer(request, verifiedVehicles),
                  onReject: () => _rejectRequest(request),
                ),
              ),
            ),
          ],
          if (activeBookings.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionHeader(
              title: _t('Latest assignment', 'تازہ ترین اسائنمنٹ'),
              action: _t('Open', 'کھولیں'),
              onAction: () => widget.onNavigate('activeTrip'),
            ),
            const SizedBox(height: 8),
            _LatestAssignment(
              booking: activeBookings.first,
              onTap: () => widget.onNavigate('activeTrip'),
            ),
          ],
          const SizedBox(height: 18),
          SectionHeader(title: _t('Quick actions', 'فوری اختیارات')),
          const SizedBox(height: 9),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.52,
            children: [
              _ToolCard(
                icon: Icons.notifications_active_rounded,
                title: _t('Customer requests', 'کسٹمر درخواستیں'),
                subtitle: _t('Send your fare', 'اپنا کرایہ دیں'),
                colors: const [Color(0xFF165DFF), Color(0xFF4A86FF)],
                onTap: () => widget.onNavigate('requests'),
              ),
              _ToolCard(
                icon: Icons.add_road_rounded,
                title: _t('Create local route', 'لوکل روٹ بنائیں'),
                subtitle: _t('Daily seat departure', 'روزانہ سیٹ روانگی'),
                colors: const [Color(0xFF7B3FE4), Color(0xFFA76CF2)],
                onTap: () => widget.onNavigate('createPackage'),
              ),
              _ToolCard(
                icon: Icons.directions_car_filled_rounded,
                title: context.tr('vehicles'),
                subtitle: _t('Manage vehicles', 'گاڑیاں منظم کریں'),
                colors: const [Color(0xFF0B8F68), Color(0xFF20B88A)],
                onTap: () => widget.onNavigate('vehicles'),
              ),
              _ToolCard(
                icon: Icons.account_balance_wallet_rounded,
                title: context.tr('earnings'),
                subtitle: _t('Wallet & payouts', 'والیٹ اور ادائیگیاں'),
                colors: const [Color(0xFFE46A25), Color(0xFFF79B4D)],
                onTap: () => widget.onNavigate('earnings'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('My tour packages', 'میرے ٹور پیکیجز'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onNavigate('createPackage'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(_t('Add package', 'پیکیج شامل کریں')),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (packages.isEmpty)
            PremiumCard(
              onTap: () => widget.onNavigate('createPackage'),
              child: Row(
                children: [
                  const Icon(Icons.luggage_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t(
                        'No package created yet. Add your first tourism package.',
                        'ابھی کوئی پیکیج نہیں بنایا۔ اپنا پہلا ٹورزم پیکیج شامل کریں۔',
                      ),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                ],
              ),
            )
          else
            ...packages.map(
              (package) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PackageCard(
                  package: package,
                  onTap: () => widget.onNavigate('driverPackages'),
                ),
              ),
            ),
          if (controller.marketplaceError != null && requests.isEmpty) ...[
            const SizedBox(height: 10),
            PremiumCard(
              color: const Color(0xFFFFF3F2),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      controller.marketplaceError!,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showOffer(
    LiveRideRequest request,
    List<dynamic> vehicles,
  ) async {
    if (vehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Verify a vehicle before accepting requests.', 'درخواست قبول کرنے سے پہلے گاڑی کی تصدیق کروائیں۔'))),
      );
      return;
    }

    dynamic selectedVehicle = vehicles.first;
    final amount = TextEditingController(
      text: request.customerOffer.round().toString(),
    );
    final eta = TextEditingController(text: '20');
    final message = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
                _t('Accept & send fare', 'قبول کریں اور کرایہ بھیجیں'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '${request.pickupLabel} → ${request.destinationLabel}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<dynamic>(
                initialValue: selectedVehicle,
                decoration: const InputDecoration(
                  labelText: 'Verified vehicle',
                  prefixIcon: Icon(Icons.directions_car_rounded),
                ),
                items: vehicles
                    .where((vehicle) => vehicle.passengerCapacity >= request.seatsRequested)
                    .map<DropdownMenuItem<dynamic>>(
                      (vehicle) => DropdownMenuItem<dynamic>(
                        value: vehicle,
                        child: Text('${vehicle.make} ${vehicle.model} · ${vehicle.registrationNumber}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setSheetState(() => selectedVehicle = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _t('Your fare (PKR)', 'آپ کا کرایہ (PKR)'),
                  prefixIcon: const Icon(Icons.payments_rounded),
                  helperText: 'Customer offered PKR ${NumberFormat('#,###').format(request.customerOffer)}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: eta,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pickup ETA (minutes)',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: message,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Optional message',
                  prefixIcon: Icon(Icons.message_rounded),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final parsedAmount = double.tryParse(amount.text.trim());
                    if (selectedVehicle == null || parsedAmount == null || parsedAmount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a vehicle and enter a valid fare.')),
                      );
                      return;
                    }
                    try {
                      await AppControllerScope.of(context).submitLiveDriverOffer(
                        rideRequestId: request.id,
                        vehicleId: selectedVehicle.id as String,
                        amount: parsedAmount,
                        etaMinutes: int.tryParse(eta.text.trim()) ?? 20,
                        message: message.text.trim(),
                      );
                      if (!mounted) return;
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fare offer sent to Customer.')),
                      );
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$error')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(_t('Accept & send offer', 'قبول کریں اور آفر بھیجیں')),
                ),
              ),
            ],
          ),
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

class _DashboardRequestCard extends StatelessWidget {
  const _DashboardRequestCard({
    required this.request,
    required this.enabled,
    required this.onAccept,
    required this.onReject,
  });

  final LiveRideRequest request;
  final bool enabled;
  final VoidCallback onAccept;
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
                Text(
                  '${request.seatsRequested} passenger${request.seatsRequested == 1 ? '' : 's'} · ${request.bookingType}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
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
