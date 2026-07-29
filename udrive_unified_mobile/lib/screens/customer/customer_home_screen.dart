import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import 'live_packages_screen.dart';
import 'tourism_booking_screen.dart';
import '../operations/live_trip_navigation_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final TextEditingController _vehicleSearch = TextEditingController();
  String _query = '';
  _VehicleTypeFilter _vehicleType = _VehicleTypeFilter.fourWheel;
  TripOperationsRepository? _tripRepository;
  Timer? _tripRefreshTimer;
  MobileTrip? _incomingTrip;

  @override
  void initState() {
    super.initState();
    _vehicleSearch.addListener(() {
      final value = _vehicleSearch.text.trim().toLowerCase();
      if (value != _query) setState(() => _query = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHome());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripRepository ??= TripOperationsRepository(
      AppControllerScope.of(context).apiClient,
    );
    _loadIncomingTrip(silent: true);
    _tripRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadIncomingTrip(silent: true),
    );
  }

  Future<void> _loadIncomingTrip({bool silent = false}) async {
    final repository = _tripRepository;
    if (repository == null) return;
    try {
      final trips = await repository.customerTrips();
      final active = trips.where((trip) => const {
            'DriverEnRoute',
            'DriverArrived',
            'TripStarted',
            'Emergency',
          }.contains(trip.tripStatus)).toList()
        ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
      if (!mounted) return;
      setState(() => _incomingTrip = active.isEmpty ? null : active.first);
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live trip could not be refreshed.')),
        );
      }
    }
  }

  Future<void> _openIncomingTrip() async {
    final trip = _incomingTrip;
    final repository = _tripRepository;
    if (trip == null || repository == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFullScreenTrackingScreen(
          trip: trip,
          repository: repository,
        ),
      ),
    );
    await _loadIncomingTrip(silent: true);
  }

  @override
  void dispose() {
    _tripRefreshTimer?.cancel();
    _vehicleSearch.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    final controller = AppControllerScope.of(context);
    if (controller.liveMarketplacePackages.isEmpty) {
      await controller.refreshHomeVehicles();
    }
    unawaited(controller.refreshPhase9Marketplace());
  }

  Future<void> _refresh() async {
    final controller = AppControllerScope.of(context);
    await Future.wait([
      controller.refreshHomeVehicles(force: true),
      _loadIncomingTrip(silent: true),
    ]);
    unawaited(controller.refreshPhase9Marketplace());
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final active = controller.liveBookings
        .where((booking) => !_closed.contains(booking.status))
        .toList()
      ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
    final upcoming = active
        .where((booking) => booking.pickupAt.isAfter(DateTime.now()))
        .length;
    final pendingOffers = controller.liveRideRequests.fold<int>(
      0,
      (sum, request) => sum + request.offersCount,
    );
    final vehicles = _filteredVehicles(controller.liveMarketplacePackages);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          _BookingHero(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TourismBookingScreen(),
              ),
            ),
          ),
          if (_incomingTrip != null) ...[
            const SizedBox(height: 10),
            _IncomingDriverCard(
              trip: _incomingTrip!,
              onTap: _openIncomingTrip,
            ),
          ],
          const SizedBox(height: 14),
          _VehicleTypeSelector(
            selected: _vehicleType,
            onSelected: (value) => setState(() => _vehicleType = value),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vehicleSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _t(
                      'Search destination, e.g. Neelum Valley',
                      'منزل تلاش کریں، مثلاً نیلم ویلی',
                    ),
                    prefixIcon: const Icon(Icons.location_searching_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _t('Clear search', 'تلاش صاف کریں'),
                            onPressed: _vehicleSearch.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _openAllVehicles,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                  minimumSize: const Size(0, 48),
                ),
                child: Text(_t('View all', 'سب دیکھیں')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.marketplaceBusy && vehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (vehicles.isEmpty)
            _EmptyLiveData(
              message: _query.isEmpty
                  ? _t(
                      'No ${_vehicleType.label.toLowerCase()} vehicle is currently available.',
                      'اس وقت اس قسم کی کوئی گاڑی دستیاب نہیں۔',
                    )
                  : _t(
                      'No ${_vehicleType.label.toLowerCase()} vehicle is going to this destination right now.',
                      'اس وقت اس منزل کی طرف اس قسم کی کوئی گاڑی نہیں جا رہی۔',
                    ),
            )
          else
            ...vehicles.map(
              (package) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ScheduledVehicleCard(
                  package: package,
                  onTap: () => _openVehicle(package),
                ),
              ),
            ),
          if (controller.marketplaceError != null &&
              vehicles.isEmpty &&
              !controller.marketplaceBusy) ...[
            const SizedBox(height: 8),
            _ErrorBanner(
              message: _t(
                'Vehicles could not be refreshed. Pull down or tap retry.',
                'گاڑیاں ریفریش نہیں ہو سکیں۔ نیچے کھینچیں یا دوبارہ کوشش کریں۔',
              ),
              onRetry: _refresh,
            ),
          ],
          if (active.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(
              title: _t('Current booking', 'موجودہ بکنگ'),
              action: _t('View all', 'سب دیکھیں'),
              onAction: () => widget.onNavigate('trips'),
            ),
            const SizedBox(height: 10),
            _LiveBookingCard(
              booking: active.first,
              onTap: () => widget.onNavigate('trips'),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.route_rounded,
                  label: _t('Active trips', 'فعال سفر'),
                  value: '${active.length}',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  icon: Icons.calendar_month_rounded,
                  label: _t('Upcoming', 'آنے والے'),
                  value: '$upcoming',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  icon: Icons.local_offer_rounded,
                  label: _t('Offers', 'آفرز'),
                  value: '$pendingOffers',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(title: _t('Quick actions', 'فوری سہولیات')),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.72,
            children: [
              _Action(
                icon: Icons.local_taxi_rounded,
                title: _t('Book a ride', 'رائیڈ بک کریں'),
                subtitle: _t('Private or shared', 'پرائیویٹ یا شیئرڈ'),
                colors: const [Color(0xFF0E8F68), Color(0xFF16B982)],
                onTap: () => widget.onNavigate('bookRide'),
              ),
              _Action(
                icon: Icons.directions_bus_filled_rounded,
                title: _t('Scheduled rides', 'شیڈول رائیڈز'),
                subtitle: _t('Book available seats', 'دستیاب سیٹ بک کریں'),
                colors: const [Color(0xFF3568D4), Color(0xFF5A8AF0)],
                onTap: () => widget.onNavigate('packages'),
              ),
              _Action(
                icon: Icons.groups_rounded,
                title: _t('Join a tour', 'ٹور جوائن کریں'),
                subtitle: _t('Find matching tours', 'میچنگ ٹور تلاش کریں'),
                colors: const [Color(0xFF7A42C8), Color(0xFFA164E8)],
                onTap: () => widget.onNavigate('joinTour'),
              ),
              _Action(
                icon: Icons.health_and_safety_rounded,
                title: _t('Safety centre', 'سیفٹی سینٹر'),
                subtitle: _t('Tracking & support', 'ٹریکنگ اور مدد'),
                colors: const [Color(0xFFE5702A), Color(0xFFF49A46)],
                onTap: () => widget.onNavigate('safety'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<LiveTourPackage> _filteredVehicles(List<LiveTourPackage> source) {
    final sorted = [...source]
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    final filtered = sorted.where((package) {
      final destinationMatches = _query.isEmpty ||
          package.destination.toLowerCase().contains(_query);
      return destinationMatches &&
          _vehicleTypeOf(package) == _vehicleType;
    });
    return filtered.take(10).toList();
  }

  _VehicleTypeFilter _vehicleTypeOf(LiveTourPackage package) {
    final text =
        '${package.vehicle} ${package.title} ${package.registrationNumber}'
            .toLowerCase();

    if (text.contains('rickshaw') ||
        text.contains('qinqi') ||
        text.contains('three wheel') ||
        text.contains('3 wheel')) {
      return _VehicleTypeFilter.threeWheel;
    }

    if (text.contains('motorcycle') ||
        text.contains('motor bike') ||
        text.contains('motorbike') ||
        text.contains('scooter') ||
        text.contains('bike') ||
        text.contains('two wheel') ||
        text.contains('2 wheel')) {
      return _VehicleTypeFilter.twoWheel;
    }

    return _VehicleTypeFilter.fourWheel;
  }

  Future<void> _openAllVehicles() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _AllAvailableVehiclesScreen(),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openVehicle(LiveTourPackage package) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePackageDetailScreen(package: package),
      ),
    );
    if (mounted) await _refresh();
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  static const _closed = {'Completed', 'Cancelled', 'NoShow'};
}

class _IncomingDriverCard extends StatelessWidget {
  const _IncomingDriverCard({required this.trip, required this.onTap});
  final MobileTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = trip.tripStatus == 'DriverEnRoute'
        ? 'Driver is on the way'
        : trip.tripStatus == 'DriverArrived'
            ? 'Driver has arrived'
            : trip.tripStatus == 'TripStarted'
                ? 'Trip in progress'
                : 'Live trip update';
    final subtitle = trip.tripStatus == 'TripStarted'
        ? '${trip.pickupLabel} → ${trip.destinationLabel}'
        : 'Track ${trip.driverName ?? 'your Driver'} coming to ${trip.pickupLabel}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0B6B50), Color(0xFF12A475)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.17),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE8FFF6), fontSize: 11)),
                    if (trip.vehicle != null) ...[
                      const SizedBox(height: 3),
                      Text('${trip.vehicle} · ${trip.registrationNumber ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_rounded, size: 16, color: Color(0xFF087654)),
                    SizedBox(width: 4),
                    Text('Track', style: TextStyle(color: Color(0xFF087654), fontWeight: FontWeight.w900, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingHero extends StatelessWidget {
  const _BookingHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF063F32), Color(0xFF129E6A)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF129E6A).withValues(alpha: .24),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('whereTo'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Book a private vehicle or reserve seats on a scheduled ride.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: AppColors.primaryDark),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Pickup and destination',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}


enum _VehicleTypeFilter {
  fourWheel('4 Wheel', Icons.directions_car_filled_rounded),
  twoWheel('2 Wheel', Icons.two_wheeler_rounded),
  threeWheel('3 Wheel', Icons.electric_rickshaw_rounded);

  const _VehicleTypeFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _VehicleTypeSelector extends StatelessWidget {
  const _VehicleTypeSelector({
    required this.selected,
    required this.onSelected,
  });

  final _VehicleTypeFilter selected;
  final ValueChanged<_VehicleTypeFilter> onSelected;

  @override
  Widget build(BuildContext context) => Row(
        children: _VehicleTypeFilter.values.map((type) {
          final active = type == selected;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: type == _VehicleTypeFilter.threeWheel ? 0 : 8,
              ),
              child: InkWell(
                onTap: () => onSelected(type),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: .18),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: 23,
                        color: active ? Colors.white : AppColors.primaryDark,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        type.label,
                        style: TextStyle(
                          color: active ? Colors.white : AppColors.navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
}


class _AllAvailableVehiclesScreen extends StatefulWidget {
  const _AllAvailableVehiclesScreen();

  @override
  State<_AllAvailableVehiclesScreen> createState() =>
      _AllAvailableVehiclesScreenState();
}

class _AllAvailableVehiclesScreenState
    extends State<_AllAvailableVehiclesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _destination;
  _VehicleTypeFilter? _vehicleType;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final value = _search.text.trim().toLowerCase();
      if (value != _query) setState(() => _query = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = AppControllerScope.of(context);
      if (controller.liveMarketplacePackages.isEmpty) {
        controller.refreshHomeVehicles();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final all = [...controller.liveMarketplacePackages]
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    final destinations = all
        .map((item) => item.destination.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final filtered = all.where((package) {
      final destinationText = package.destination.toLowerCase();
      final matchesSearch = _query.isEmpty || destinationText.contains(_query);
      final matchesDestination = _destination == null ||
          package.destination.toLowerCase() == _destination!.toLowerCase();
      final matchesType = _vehicleType == null ||
          _vehicleTypeForPackage(package) == _vehicleType;
      return matchesSearch && matchesDestination && matchesType;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a vehicle'),
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refreshHomeVehicles(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF073F32), Color(0xFF129E6A)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Where do you want to go?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Choose a tourist point or search a destination, then tap a vehicle to reserve your seat.',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search destination',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Popular tourist points',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _DestinationChoiceChip(
                    label: 'All',
                    selected: _destination == null,
                    onTap: () => setState(() => _destination = null),
                  ),
                  ...destinations.map(
                    (destination) => _DestinationChoiceChip(
                      label: destination,
                      selected: _destination == destination,
                      onTap: () => setState(() {
                        _destination = destination;
                        _search.clear();
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _DestinationChoiceChip(
                    label: 'All vehicles',
                    selected: _vehicleType == null,
                    onTap: () => setState(() => _vehicleType = null),
                  ),
                  ..._VehicleTypeFilter.values.map(
                    (type) => _DestinationChoiceChip(
                      label: type.label,
                      icon: type.icon,
                      selected: _vehicleType == type,
                      onTap: () => setState(() => _vehicleType = type),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Available departures',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                Text(
                  '${filtered.length} found',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (controller.marketplaceBusy && all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const _EmptyLiveData(
                message: 'No bookable vehicle is available for this destination right now.',
              )
            else
              ...filtered.map(
                (package) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ScheduledVehicleCard(
                    package: package,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LivePackageDetailScreen(package: package),
                        ),
                      );
                      if (mounted) {
                        await controller.refreshHomeVehicles(force: true);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _VehicleTypeFilter _vehicleTypeForPackage(LiveTourPackage package) {
    final text =
        '${package.vehicle} ${package.title} ${package.registrationNumber}'
            .toLowerCase();
    if (text.contains('rickshaw') ||
        text.contains('qinqi') ||
        text.contains('three wheel') ||
        text.contains('3 wheel')) {
      return _VehicleTypeFilter.threeWheel;
    }
    if (text.contains('motorcycle') ||
        text.contains('motor bike') ||
        text.contains('motorbike') ||
        text.contains('scooter') ||
        text.contains('bike') ||
        text.contains('two wheel') ||
        text.contains('2 wheel')) {
      return _VehicleTypeFilter.twoWheel;
    }
    return _VehicleTypeFilter.fourWheel;
  }
}

class _DestinationChoiceChip extends StatelessWidget {
  const _DestinationChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onTap(),
          avatar: icon == null
              ? null
              : Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : AppColors.primaryDark,
                ),
          label: Text(label),
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
          selectedColor: AppColors.primary,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
}

class _ScheduledVehicleCard extends StatelessWidget {
  const _ScheduledVehicleCard({required this.package, required this.onTap});

  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final seats = package.bookableSeats;
    final money = NumberFormat('#,###').format(package.pricePerSeat);
    final image = package.coverImageUrl?.trim();
    final seatBackground = seats <= 0
        ? const Color(0xFFFFE6E6)
        : seats <= 2
            ? const Color(0xFFFFE9C7)
            : const Color(0xFFD9F8E9);
    final seatForeground = seats <= 0
        ? AppColors.danger
        : seats <= 2
            ? const Color(0xFF9A5A00)
            : const Color(0xFF087A4B);

    return PremiumCard(
      onTap: seats > 0 ? onTap : null,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCDEADF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trip_origin_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      package.startingCity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7),
                    child: Icon(Icons.arrow_forward_rounded, size: 17, color: AppColors.primaryDark),
                  ),
                  Expanded(
                    child: Text(
                      package.destination,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: image != null && image.isNotEmpty
                      ? Image.network(image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _vehicleFallback())
                      : _vehicleFallback(),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.vehicle.isEmpty ? package.title : package.vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        package.registrationNumber.isEmpty
                            ? package.title
                            : '${package.registrationNumber} · ${package.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 12, color: AppColors.muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              DateFormat('dd MMM · hh:mm a').format(package.departureAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 9.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Fare per seat', style: TextStyle(color: AppColors.muted, fontSize: 9)),
                    Text('PKR $money', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 13.5)),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: seatBackground,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: seatForeground.withValues(alpha: .22)),
                      ),
                      child: Text(
                        seats > 0 ? '$seats seats free' : 'Full',
                        style: TextStyle(color: seatForeground, fontWeight: FontWeight.w900, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _vehicleFallback() => const DecoratedBox(
        decoration: BoxDecoration(color: Colors.white),
        child: Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark, size: 24),
      );
}

class _RoutePlace extends StatelessWidget {
  const _RoutePlace({
    required this.icon,
    required this.label,
    this.alignEnd = false,
  });

  final IconData icon;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!alignEnd) ...[
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: alignEnd ? AppColors.primaryDark : AppColors.navy,
              ),
            ),
          ),
          if (alignEnd) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 17, color: AppColors.primary),
          ],
        ],
      );
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.muted),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _VehicleFact extends StatelessWidget {
  const _VehicleFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => PremiumCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: .22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 13),
            ],
          ),
        ),
      );
}

class _LiveBookingCard extends StatelessWidget {
  const _LiveBookingCard({required this.booking, required this.onTap});

  final LiveBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.bookingReference,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusPill(label: booking.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${booking.pickupLabel} → ${booking.destinationLabel}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              '${DateFormat('dd MMM · hh:mm a').format(booking.pickupAt)} · ${booking.seatsBooked} seat(s)',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if ((booking.driverName ?? '').isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                '${booking.driverName} · ${booking.vehicle ?? 'Vehicle pending'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      );
}

class _EmptyLiveData extends StatelessWidget {
  const _EmptyLiveData({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PremiumCard(
        child: Row(
          children: [
            const Icon(Icons.directions_bus_outlined, color: AppColors.muted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => PremiumCard(
        color: const Color(0xFFFFF4F4),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
