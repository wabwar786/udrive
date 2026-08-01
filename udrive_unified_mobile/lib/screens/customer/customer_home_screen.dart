import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/vehicle_art.dart';
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

  final MapController _mapController = MapController();
  LatLng? _myLocation;

  @override
  void initState() {
    super.initState();
    _vehicleSearch.addListener(() {
      final value = _vehicleSearch.text.trim().toLowerCase();
      if (value != _query) setState(() => _query = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHome();
      _loadMyLocation();
    });
  }

  Future<void> _loadMyLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _myLocation = LatLng(position.latitude, position.longitude));
    } catch (_) {
      // Location is a nice-to-have on the map; ignore failures silently.
    }
  }

  void _recenter() {
    final target = _myLocation ?? KashmirPlaces.hub;
    _mapController.move(target, _myLocation != null ? 13 : 9);
  }

  void _openDestination(String destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TourismBookingScreen(initialDestination: destination),
      ),
    );
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
    _mapController.dispose();
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
    final vehicles = _filteredVehicles(controller.liveMarketplacePackages);
    final featuredPlaces = KashmirPlaces.all
        .where((place) => const {'Neelum Valley', 'Pir Chinasi', 'Banjosa Lake'}.contains(place.name))
        .toList();

    return ColoredBox(
      color: const Color(0xFF071D2B),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .47,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _KashmirMap(
                        controller: _mapController,
                        myLocation: _myLocation,
                        onPlaceTap: (place) => _openDestination(place.name),
                        localize: (place) => controller.locale.languageCode == 'ur'
                            ? place.urdu
                            : place.name,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF061925).withValues(alpha: .86),
                                const Color(0xFF061925).withValues(alpha: .12),
                                const Color(0xFF071D2B).withValues(alpha: .92),
                              ],
                              stops: const [0, .42, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Builder(
                              builder: (context) => InkWell(
                                onTap: () => Scaffold.of(context).openDrawer(),
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF07141D).withValues(alpha: .88),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: .08)),
                                  ),
                                  child: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800),
                                children: [
                                  TextSpan(text: 'Discover '),
                                  TextSpan(
                                    text: 'Kashmir',
                                    style: TextStyle(color: Color(0xFF9CDA2A), fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Paradise on Earth  🍃',
                              style: TextStyle(color: Color(0xFFD7E2E8), fontSize: 16),
                            ),
                            const Spacer(),
                            Align(
                              alignment: Alignment.center,
                              child: InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const TourismBookingScreen()),
                                ),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111820).withValues(alpha: .94),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withValues(alpha: .08)),
                                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 8))],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Pickup point', style: TextStyle(color: Color(0xFF9DA6AE), fontSize: 12)),
                                          SizedBox(height: 2),
                                          Text('Current location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                        ],
                                      ),
                                      SizedBox(width: 18),
                                      Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 18,
                      child: FloatingActionButton.small(
                        heroTag: 'customer-home-recenter',
                        backgroundColor: const Color(0xFF111820),
                        foregroundColor: Colors.white,
                        onPressed: _recenter,
                        child: const Icon(Icons.navigation_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_incomingTrip != null) ...[
                    _IncomingDriverCard(trip: _incomingTrip!, onTap: _openIncomingTrip),
                    const SizedBox(height: 14),
                  ],
                  _ExploreBanner(onTap: () => widget.onNavigate('explore')),
                  const SizedBox(height: 16),
                  _TourismServiceGrid(
                    onExplore: () => widget.onNavigate('explore'),
                    onStay: () => widget.onNavigate('packages'),
                    onTransport: () => widget.onNavigate('bookRide'),
                    onActivities: () => widget.onNavigate('joinTour'),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101A22),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: .06)),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _vehicleSearch,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Where do you want to go in Kashmir?',
                            hintStyle: const TextStyle(color: Color(0xFF9CA6AE)),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFD5DEE3)),
                            filled: true,
                            fillColor: const Color(0xFF202930),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < featuredPlaces.length; i++) ...[
                          _DestinationListTile(
                            place: featuredPlaces[i],
                            imagePath: switch (featuredPlaces[i].name) {
                              'Neelum Valley' => 'assets/images/neelum.png',
                              'Pir Chinasi' => 'assets/images/pir_chinasi.png',
                              _ => 'assets/images/banjosa.png',
                            },
                            onTap: () => _openDestination(featuredPlaces[i].name),
                          ),
                          if (i != featuredPlaces.length - 1)
                            Divider(height: 1, color: Colors.white.withValues(alpha: .08)),
                        ],
                      ],
                    ),
                  ),
                  if (vehicles.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Available rides', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                        ),
                        TextButton(onPressed: _openAllVehicles, child: const Text('View all')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 154,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: vehicles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, index) {
                          final package = vehicles[index];
                          return _CompactRideCard(package: package, onTap: () => _openVehicle(package));
                        },
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
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


class _ExploreBanner extends StatelessWidget {
  const _ExploreBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF101A22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/images/neelum.png', width: 128, height: 84, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Explore Kashmir', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('Top destinations, handpicked experiences & local guides', style: TextStyle(color: Color(0xFFB6C0C7), fontSize: 12, height: 1.3)),
                    SizedBox(height: 7),
                    Text('Best time to visit: Mar – Oct', style: TextStyle(color: Color(0xFF9CDA2A), fontWeight: FontWeight.w700, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      );
}

class _TourismServiceGrid extends StatelessWidget {
  const _TourismServiceGrid({required this.onExplore, required this.onStay, required this.onTransport, required this.onActivities});
  final VoidCallback onExplore, onStay, onTransport, onActivities;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 260,
        child: Row(
          children: [
            Expanded(
              flex: 11,
              child: _ServicePanel(
                title: 'Explore Kashmir',
                subtitle: 'Tours, Activities & More',
                icon: Icons.landscape_rounded,
                highlighted: true,
                onTap: onExplore,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 10,
              child: Column(
                children: [
                  Expanded(child: _ServicePanel(title: 'Stay', subtitle: 'Hotels, Resorts, Houseboats', icon: Icons.houseboat_rounded, onTap: onStay)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _ServicePanel(title: 'Transport', subtitle: 'Cabs, Bikes, Buses', icon: Icons.directions_car_rounded, compact: true, onTap: onTransport)),
                        const SizedBox(width: 10),
                        Expanded(child: _ServicePanel(title: 'Activities', subtitle: 'Adventure, Skiing, Trekking', icon: Icons.hiking_rounded, compact: true, onTap: onActivities)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ServicePanel extends StatelessWidget {
  const _ServicePanel({required this.title, required this.subtitle, required this.icon, required this.onTap, this.highlighted = false, this.compact = false});
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted, compact;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
            gradient: highlighted
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA3D928), Color(0xFF5A9C13)])
                : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF273038), Color(0xFF151D23)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Stack(
            children: [
              Positioned(right: compact ? -5 : 4, bottom: compact ? -3 : 2, child: Icon(icon, size: compact ? 50 : 78, color: Colors.white.withValues(alpha: highlighted ? .92 : .72))),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Colors.white, fontSize: compact ? 14 : 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: compact ? 3 : 2, style: TextStyle(color: highlighted ? Colors.white : const Color(0xFFB5BEC5), fontSize: compact ? 10.5 : 13, height: 1.25)),
                ],
              ),
            ],
          ),
        ),
      );
}

class _DestinationListTile extends StatelessWidget {
  const _DestinationListTile({required this.place, required this.imagePath, required this.onTap});
  final KashmirPlace place;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        onTap: onTap,
        leading: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(imagePath, width: 58, height: 58, fit: BoxFit.cover)),
        title: Text(place.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: Text('Scenic beauty, local experiences & more', style: const TextStyle(color: Color(0xFF9EA8AF), fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white),
      );
}

class _CompactRideCard extends StatelessWidget {
  const _CompactRideCard({required this.package, required this.onTap});
  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF101A22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.directions_car_filled_rounded, color: Color(0xFF9CDA2A)),
                const SizedBox(width: 8),
                Expanded(child: Text(package.vehicle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              ]),
              const Spacer(),
              Text(package.destination, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('${package.availableSeats} seats available', style: const TextStyle(color: Color(0xFF9EA8AF), fontSize: 11)),
              const SizedBox(height: 8),
              Text('PKR ${package.pricePerSeat.toStringAsFixed(0)} / seat', style: const TextStyle(color: Color(0xFF9CDA2A), fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ),
        ),
      );
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

/// Full-bleed OpenStreetMap of Azad Kashmir with tourist-destination pins and
/// a scatter of "live" vehicles around the Muzaffarabad hub.
class _KashmirMap extends StatelessWidget {
  const _KashmirMap({
    required this.controller,
    required this.myLocation,
    required this.onPlaceTap,
    required this.localize,
  });

  final MapController controller;
  final LatLng? myLocation;
  final ValueChanged<KashmirPlace> onPlaceTap;
  final String Function(KashmirPlace) localize;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: KashmirPlaces.hub,
        initialZoom: 9,
        minZoom: 6,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.udrive.mobile',
          maxZoom: 19,
        ),
        // Nearby "live" vehicles around the hub.
        MarkerLayer(
          markers: [
            for (final point in KashmirPlaces.nearbyVehicles)
              Marker(
                point: point,
                width: 34,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 1.6),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: .18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_rounded,
                    size: 17,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
          ],
        ),
        // Tourist destination pins (tap to book toward that spot).
        MarkerLayer(
          markers: [
            for (final place in KashmirPlaces.all)
              Marker(
                point: place.point,
                width: 132,
                height: 46,
                child: _PlacePin(
                  label: localize(place),
                  hub: place.name == 'Muzaffarabad',
                  onTap: () => onPlaceTap(place),
                ),
              ),
          ],
        ),
        if (myLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: myLocation!,
                width: 26,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.info.withValues(alpha: .4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}

class _PlacePin extends StatelessWidget {
  const _PlacePin({required this.label, required this.hub, required this.onTap});

  final String label;
  final bool hub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = hub ? AppColors.navy : AppColors.primaryDark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: .24),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hub ? Icons.trip_origin_rounded : Icons.place_rounded,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_drop_down_rounded, size: 16, color: color),
        ],
      ),
    );
  }
}

/// inDrive-style floating "Where to?" search bar shown over the map.
class _WhereToBar extends StatelessWidget {
  const _WhereToBar({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: AppColors.navy.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search_rounded, size: 18, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    hint,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        elevation: 2,
        shadowColor: AppColors.navy.withValues(alpha: .12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _MapFab extends StatelessWidget {
  const _MapFab({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 5,
        shadowColor: AppColors.navy.withValues(alpha: .2),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: AppColors.primaryDark, size: 22),
          ),
        ),
      );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFD3DBD8),
            borderRadius: BorderRadius.circular(999),
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
                borderRadius: BorderRadius.circular(13),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 52,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: .18),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: 20,
                        color: active ? Colors.white : AppColors.primaryDark,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        type.label,
                        style: TextStyle(
                          color: active ? Colors.white : AppColors.navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
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
                VehicleThumb(
                  vehicleText: '${package.vehicle} ${package.title} ${package.registrationNumber}',
                  size: 62,
                  radius: 14,
                ),
                const SizedBox(width: 11),
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
