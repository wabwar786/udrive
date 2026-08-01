
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import '../operations/live_trip_navigation_screen.dart';
import 'live_packages_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  static const _ink = Color(0xFF10212B);
  static const _lime = Color(0xFF8ED12B);
  static const _muted = Color(0xFF667781);
  static const _surface = Color(0xFFF6F8FA);

  final _pickup = TextEditingController(text: 'Detecting current address…');
  final _destination = TextEditingController();
  final _pageController = PageController();
  final _scrollController = ScrollController();
  final _resultsKey = GlobalKey();
  late final ApiClient _api;

  Timer? _heroTimer;
  Timer? _tripTimer;
  int _heroIndex = 0;
  bool _loadingDestinations = true;
  bool _showDestinationList = false;
  bool _searched = false;
  bool _locating = false;
  String _destinationQuery = '';
  String? _selectedVehicleType;
  DateTime? _selectedDepartureDay;
  bool _historyNextMonthOnly = false;
  bool _showVehicleTypeBar = false;
  String? _resultsTitle;
  List<_HeroDestination> _destinations = const [];
  TripOperationsRepository? _tripRepository;
  MobileTrip? _activeTrip;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(SessionStore());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([
        _loadDestinations(),
        _loadLocation(),
        _loadMarketplace(),
      ]);
    });
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients || _destinations.length < 2) {
        return;
      }
      final next = (_heroIndex + 1) % _destinations.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripRepository ??=
        TripOperationsRepository(AppControllerScope.of(context).apiClient);
    _refreshActiveTrip();
    _tripTimer ??=
        Timer.periodic(const Duration(seconds: 12), (_) => _refreshActiveTrip());
  }

  Future<void> _loadMarketplace() async {
    final controller = AppControllerScope.of(context);
    await controller.refreshHomeVehicles();
    await controller.refreshPhase9Marketplace();
    await controller.refreshLiveBookings();
  }

  Future<void> _loadDestinations() async {
    try {
      final response = await _api.getJson(
        '/api/v1/catalog/destinations?language=en',
        authenticated: false,
      );
      final raw = response['data'] as List? ?? const [];
      final loaded = raw.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        return _HeroDestination(
          name: '${map['name'] ?? ''}'.trim(),
          district: '${map['district'] ?? ''}'.trim(),
          summary: '${map['summary'] ?? ''}'.trim(),
          imageUrl: ApiConfig.absoluteUrl(map['coverImageUrl']?.toString()),
        );
      }).where((item) => item.name.isNotEmpty && item.imageUrl.isNotEmpty).toList();
      if (mounted) {
        setState(() {
          _destinations = loaded.isEmpty ? _fallbackDestinations : loaded;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _destinations = _fallbackDestinations);
    } finally {
      if (mounted) setState(() => _loadingDestinations = false);
    }
  }

  Future<void> _loadLocation() async {
    if (_locating) return;
    if (mounted) setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _pickup.text = 'Enter pickup address';
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _pickup.text = 'Enter pickup address';
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final marks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      if (marks.isEmpty) {
        _pickup.text = 'Enter pickup address';
        return;
      }
      final mark = marks.first;
      final values = [
        mark.street,
        mark.subLocality,
        mark.locality,
        mark.administrativeArea,
        mark.country,
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      _pickup.text = values.join(', ');
      if (mounted) setState(() {});
    } catch (_) {
      _pickup.text = 'Enter pickup address';
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _refreshActiveTrip() async {
    final repository = _tripRepository;
    if (repository == null) return;
    try {
      final trips = await repository.customerTrips();
      final active = trips
          .where((trip) => const {
                'DriverEnRoute',
                'DriverArrived',
                'TripStarted',
                'Emergency',
              }.contains(trip.tripStatus))
          .toList();
      if (mounted) {
        setState(() => _activeTrip = active.isEmpty ? null : active.first);
      }
    } catch (_) {}
  }

  Future<void> _openActiveTrip() async {
    if (_activeTrip == null || _tripRepository == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFullScreenTrackingScreen(
          trip: _activeTrip!,
          repository: _tripRepository!,
        ),
      ),
    );
    await _refreshActiveTrip();
  }

  void _selectDestination(_HeroDestination value) {
    _destination.text = value.name;
    setState(() {
      _destinationQuery = value.name.toLowerCase();
      _showDestinationList = false;
      _searched = false;
      _selectedDepartureDay = null;
      _historyNextMonthOnly = false;
      _resultsTitle = null;
    });
  }

  void _showResultsForDestination(String destination) {
    _destination.text = destination;
    setState(() {
      _destinationQuery = destination.toLowerCase();
      _showDestinationList = false;
      _searched = true;
      _selectedDepartureDay = null;
      _historyNextMonthOnly = true;
      _resultsTitle = 'Rides to $destination · next 30 days';
    });
    _scrollToResults();
  }

  void _showResultsForUpcoming(LiveTourPackage ride) {
    _destination.text = ride.destination;
    setState(() {
      _destinationQuery = ride.destination.trim().toLowerCase();
      _searched = true;
      _showDestinationList = false;
      _selectedDepartureDay = DateTime(
        ride.departureAt.year,
        ride.departureAt.month,
        ride.departureAt.day,
      );
      _historyNextMonthOnly = false;
      _resultsTitle =
          '${ride.destination} · ${DateFormat('EEE, dd MMM').format(ride.departureAt)}';
    });
    _scrollToResults();
  }

  void _showResultsForVehicleType(String type) {
    final title = '${type[0].toUpperCase()}${type.substring(1)} rides';
    setState(() {
      _selectedVehicleType = type;
      _searched = true;
      _showDestinationList = false;
      _selectedDepartureDay = null;
      _historyNextMonthOnly = false;
      _destinationQuery = '';
      _showVehicleTypeBar = false;
      _resultsTitle = title;
    });
    _scrollToResults();
  }

  void _scrollToResults() {
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      final context = _resultsKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      } else {
        _scrollController.animateTo(
          MediaQuery.sizeOf(this.context).height * .78,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _findRides() {
    FocusScope.of(context).unfocus();
    if (_pickup.text.trim().isEmpty || _destination.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter pickup and destination.')),
      );
      return;
    }
    setState(() {
      _destinationQuery = _destination.text.trim().toLowerCase();
      _showDestinationList = false;
      _searched = true;
      _selectedDepartureDay = null;
      _historyNextMonthOnly = false;
      _resultsTitle = 'Available rides for ${_destination.text.trim()}';
    });
    _scrollToResults();
  }

  String _vehicleTypeForRide(LiveTourPackage ride) {
    final raw = '${ride.vehicle} ${ride.title} ${ride.registrationNumber}'.toLowerCase();
    if (raw.contains('bike') || raw.contains('motor')) return 'bike';
    if (raw.contains('rickshaw') || raw.contains('auto')) return 'rickshaw';
    if (raw.contains('coaster') || raw.contains('coster') || raw.contains('bus') || raw.contains('van')) {
      return 'coster';
    }
    return 'car';
  }

  List<LiveTourPackage> _matchingRides(List<LiveTourPackage> source) {
    if (!_searched) return const [];
    final query = _destinationQuery.trim();
    final day = _selectedDepartureDay;
    final type = _selectedVehicleType;
    final filtered = source.where((ride) {
      final matchesQuery = query.isEmpty
          ? true
          : '${ride.destination} ${ride.title} ${ride.pickupPoint}'
              .toLowerCase()
              .contains(query);
      final matchesDay = day == null
          ? true
          : DateUtils.isSameDay(ride.departureAt, day);
      final matchesType = type == null ? true : _vehicleTypeForRide(ride) == type;
      final now = DateTime.now();
      final matchesHistoryWindow = !_historyNextMonthOnly
          ? true
          : !ride.departureAt.isBefore(now) &&
              ride.departureAt.isBefore(now.add(const Duration(days: 30)));
      return matchesQuery && matchesDay && matchesType && matchesHistoryWindow;
    }).toList();
    filtered.sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return filtered;
  }

  List<LiveTourPackage> _nextSevenDayRides(List<LiveTourPackage> source) {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 7));
    final rides = source
        .where((ride) =>
            !ride.departureAt.isBefore(now) && ride.departureAt.isBefore(end))
        .toList();
    rides.sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return rides;
  }

  List<LiveTourPackage> _halfBookedRides(List<LiveTourPackage> source) {
    return _nextSevenDayRides(source).where((ride) {
      if (ride.totalSeats <= 0) return false;
      final reserved = ride.totalSeats - ride.bookableSeats;
      return reserved / ride.totalSeats >= .5;
    }).toList();
  }

  List<String> _destinationHistory(List<LiveBooking> bookings) {
    final sorted = bookings
        .where((booking) => booking.destinationLabel.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final seen = <String>{};
    final results = <String>[];
    for (final booking in sorted) {
      final key = booking.destinationLabel.trim().toLowerCase();
      if (seen.add(key)) {
        results.add(booking.destinationLabel.trim());
      }
      if (results.length >= 8) break;
    }
    return results;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstName(String value) {
    final clean = value.trim();
    return clean.isEmpty ? 'Traveller' : clean.split(RegExp(r'\s+')).first;
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _tripTimer?.cancel();
    _pickup.dispose();
    _destination.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final marketplace = controller.liveMarketplacePackages;
    final rides = _matchingRides(marketplace);
    final upcoming = _nextSevenDayRides(marketplace);
    final halfBooked = _halfBookedRides(marketplace);
    final pastDestinations = _destinationHistory(controller.liveBookings);
    final height = MediaQuery.sizeOf(context).height;

    return ColoredBox(
      color: _surface,
      child: RefreshIndicator(
        color: _lime,
        onRefresh: () async => Future.wait([
          _loadDestinations(),
          _loadMarketplace(),
          _loadLocation(),
        ]),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: height - 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _HeroSlider(
                      items: _destinations,
                      loading: _loadingDestinations,
                      controller: _pageController,
                      onChanged: (value) => setState(() => _heroIndex = value),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x52030B12),
                            Color(0x12030B12),
                            Color(0x65FFFFFF),
                            Color(0xDDF6F8FA),
                          ],
                          stops: [0, .26, .72, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 170,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, _surface],
                              stops: [.0, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              bottom: 252,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _CircleButton(
                                        icon: Icons.menu_rounded,
                                        onTap: () => Scaffold.of(context).openDrawer(),
                                      ),
                                      const Spacer(),
                                      if (_activeTrip != null) ...[
                                        _CircleButton(
                                          icon: Icons.route_rounded,
                                          onTap: _openActiveTrip,
                                          showDot: true,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      _CircleButton(
                                        icon: Icons.notifications_none_rounded,
                                        onTap: () => widget.onNavigate('notifications'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '$_greeting, ${_firstName(controller.currentUserName)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -.35,
                                      shadows: [
                                        Shadow(color: Colors.black38, blurRadius: 10),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _destinations.isEmpty
                                        ? 'Explore Kashmir'
                                        : _destinations[_heroIndex.clamp(
                                                0, _destinations.length - 1)]
                                            .name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      height: 1.02,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -.9,
                                      shadows: [
                                        Shadow(color: Colors.black45, blurRadius: 14),
                                      ],
                                    ),
                                  ),
                                  if (upcoming.isNotEmpty) ...[
                                    const SizedBox(height: 9),
                                    _UpcomingDestinations(
                                      rides: upcoming,
                                      onSelected: _showResultsForUpcoming,
                                    ),
                                  ],
                                  if (halfBooked.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _HalfBookedStrip(
                                      rides: halfBooked,
                                      onSelected: _showResultsForUpcoming,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  _VehicleTypePanel(
                                    onSelected: _showResultsForVehicleType,
                                    highlighted: true,
                                  ),
                                ],
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: .97),
                                      borderRadius: BorderRadius.circular(26),
                                      border: Border.all(
                                        color: const Color(0xFFF1F3F6),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x15000000),
                                          blurRadius: 18,
                                          offset: Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        _LocationInput(
                                          controller: _pickup,
                                          label: 'From',
                                          icon: Icons.radio_button_checked_rounded,
                                          accent: _lime,
                                          hint: 'Enter pickup address',
                                          fillColor: const Color(0xFFF8FAFB),
                                          onTap: () {
                                            final value = _pickup.text.trim();
                                            if (value == 'Enter pickup address' ||
                                                value == 'Detecting current address…') {
                                              _pickup.clear();
                                            }
                                          },
                                          suffix: IconButton(
                                            tooltip: 'Use current location',
                                            onPressed: _locating ? null : _loadLocation,
                                            icon: _locating
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: _lime,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.my_location_rounded,
                                                    color: _ink,
                                                    size: 20,
                                                  ),
                                          ),
                                        ),
                                        const Divider(height: 12),
                                        _LocationInput(
                                          controller: _destination,
                                          label: 'To',
                                          icon: Icons.location_on_rounded,
                                          accent: const Color(0xFFF38A2E),
                                          hint: 'Select destination',
                                          fillColor: const Color(0xFFF8FAFB),
                                          readOnly: true,
                                          onTap: () => setState(() =>
                                              _showDestinationList = !_showDestinationList),
                                          suffix: Icon(
                                            _showDestinationList
                                                ? Icons.keyboard_arrow_up_rounded
                                                : Icons.keyboard_arrow_down_rounded,
                                            color: _ink,
                                          ),
                                        ),
                                        AnimatedSize(
                                          duration: const Duration(milliseconds: 220),
                                          child: !_showDestinationList
                                              ? const SizedBox.shrink()
                                              : _DestinationDropdown(
                                                  items: _destinations,
                                                  onSelected: _selectDestination,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 58,
                                    child: FilledButton.icon(
                                      onPressed: _findRides,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _lime,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        surfaceTintColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(19),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.directions_car_filled_rounded,
                                        size: 22,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        'Find rides',
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_searched)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 125),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Container(key: _resultsKey),
                    if (pastDestinations.isNotEmpty) ...[
                      _DestinationHistoryStrip(
                        items: pastDestinations,
                        onSelected: _showResultsForDestination,
                        darkText: true,
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _resultsTitle ?? 'Available rides',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${rides.length} found',
                          style: const TextStyle(
                            color: Color(0xFF629B18),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rides.isEmpty)
                      _EmptyRides(destination: _destination.text)
                    else
                      ...rides.map(
                        (ride) => Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: _RideCard(
                            ride: ride,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LivePackageDetailScreen(
                                  package: ride,
                                  initialBookingType: 'PerSeat',
                                ),
                              ),
                            ),
                            onWholeVehicle: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LivePackageDetailScreen(
                                  package: ride,
                                  initialBookingType: 'WholeVehicle',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroDestination {
  const _HeroDestination({
    required this.name,
    required this.district,
    required this.summary,
    required this.imageUrl,
  });

  final String name;
  final String district;
  final String summary;
  final String imageUrl;
}

const _fallbackDestinations = <_HeroDestination>[
  _HeroDestination(
    name: 'Neelum Valley',
    district: 'Azad Kashmir',
    summary: 'Mountains, rivers and unforgettable journeys',
    imageUrl:
        'https://images.unsplash.com/photo-1595815771614-ade9d652a65d?auto=format&fit=crop&w=1400&q=85',
  ),
  _HeroDestination(
    name: 'Gulmarg',
    district: 'Kashmir',
    summary: 'Snow, gondolas and alpine adventure',
    imageUrl:
        'https://images.unsplash.com/photo-1598091383021-15ddea10925d?auto=format&fit=crop&w=1400&q=85',
  ),
  _HeroDestination(
    name: 'Dal Lake',
    district: 'Srinagar',
    summary: 'Shikara rides and beautiful houseboats',
    imageUrl:
        'https://images.unsplash.com/photo-1621232082074-1a7750ecc557?auto=format&fit=crop&w=1400&q=85',
  ),
];

class _HeroSlider extends StatelessWidget {
  const _HeroSlider({
    required this.items,
    required this.loading,
    required this.controller,
    required this.onChanged,
  });

  final List<_HeroDestination> items;
  final bool loading;
  final PageController controller;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading || items.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFEAF0F2),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF8ED12B))),
      );
    }
    return PageView.builder(
      controller: controller,
      itemCount: items.length,
      onPageChanged: onChanged,
      itemBuilder: (_, index) => Image.network(
        items[index].imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFFDCE6E9),
          child: Center(
            child: Icon(Icons.landscape_rounded, color: Colors.white, size: 70),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 12),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: _CustomerHomeScreenState._ink, size: 21),
                if (showDot)
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: CircleAvatar(
                      radius: 4,
                      backgroundColor: _CustomerHomeScreenState._lime,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _VehicleTypeToggle extends StatelessWidget {
  const _VehicleTypeToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Color(0x18000000), blurRadius: 10),
              ],
            ),
            child: Icon(
              expanded ? Icons.close_rounded : Icons.commute_rounded,
              size: 20,
              color: _CustomerHomeScreenState._ink,
            ),
          ),
        ),
      );
}

class _VehicleTypePanel extends StatelessWidget {
  const _VehicleTypePanel({
    required this.onSelected,
    this.highlighted = false,
  });

  final ValueChanged<String> onSelected;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    const items = <({String key, IconData icon, String label})>[
      (key: 'car', icon: Icons.directions_car_filled_rounded, label: 'Car'),
      (key: 'bike', icon: Icons.two_wheeler_rounded, label: 'Bike'),
      (key: 'rickshaw', icon: Icons.electric_rickshaw_rounded, label: 'Rickshaw'),
      (key: 'coster', icon: Icons.airport_shuttle_rounded, label: 'Coster'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? _CustomerHomeScreenState._lime.withValues(alpha: .90)
            : Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: highlighted
              ? Colors.white.withValues(alpha: .55)
              : const Color(0xFFE5EAEC),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        mainAxisSize: MainAxisSize.max,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: () => onSelected(items[i].key),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      items[i].icon,
                      size: 16,
                      color: highlighted ? Colors.white : _CustomerHomeScreenState._ink,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      items[i].label,
                      style: TextStyle(
                        color: highlighted ? Colors.white : _CustomerHomeScreenState._ink,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i != items.length - 1)
              Container(
                width: 1,
                height: 22,
                color: highlighted ? Colors.white38 : const Color(0xFFE5EAEC),
              ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingDestinations extends StatelessWidget {
  const _UpcomingDestinations({required this.rides, required this.onSelected});

  final List<LiveTourPackage> rides;
  final ValueChanged<LiveTourPackage> onSelected;

  String _typeLabel(LiveTourPackage ride) {
    final raw = '${ride.vehicle} ${ride.title}'.toLowerCase();
    if (raw.contains('bike') || raw.contains('motor')) return 'Bike';
    if (raw.contains('rickshaw') || raw.contains('auto')) return 'Rickshaw';
    if (raw.contains('coaster') || raw.contains('coster') || raw.contains('bus')) {
      return 'Coster';
    }
    return ride.vehicle.trim().isEmpty ? 'Car' : ride.vehicle.trim();
  }

  @override
  Widget build(BuildContext context) {
    final items = rides.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehicles departing in next 7 days',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final ride = items[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(ride),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 154,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .80),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: .70)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_car_filled_rounded,
                              size: 15,
                              color: Color(0xFF5C9417),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                ride.destination,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _CustomerHomeScreenState._ink,
                                  fontSize: 10.8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('EEE, dd MMM').format(ride.departureAt),
                          style: const TextStyle(
                            color: _CustomerHomeScreenState._muted,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _typeLabel(ride),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _CustomerHomeScreenState._ink,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(Icons.event_seat_rounded, size: 11, color: Color(0xFF5C9417)),
                            Text(
                              ' ${ride.bookableSeats}',
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: _CustomerHomeScreenState._ink,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'PKR ${ride.pricePerSeat.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFF4F8214),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HalfBookedStrip extends StatelessWidget {
  const _HalfBookedStrip({required this.rides, required this.onSelected});

  final List<LiveTourPackage> rides;
  final ValueChanged<LiveTourPackage> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: rides.take(5).length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, index) {
            final ride = rides[index];
            final reserved = ride.totalSeats - ride.bookableSeats;
            final percentage = ride.totalSeats <= 0
                ? 0
                : ((reserved / ride.totalSeats) * 100).round();
            return ActionChip(
              onPressed: () => onSelected(ride),
              avatar: const Icon(
                Icons.local_fire_department_rounded,
                size: 14,
                color: Color(0xFFE87427),
              ),
              label: Text(
                '${ride.destination} $percentage% booked',
                style: const TextStyle(
                  color: _CustomerHomeScreenState._ink,
                  fontSize: 8.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              backgroundColor: Colors.white.withValues(alpha: .94),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      );
}

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    required this.hint,
    required this.fillColor,
    this.readOnly = false,
    this.onTap,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accent;
  final String hint;
  final Color fillColor;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 17),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              onTap: onTap,
              style: const TextStyle(
                color: _CustomerHomeScreenState._ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: fillColor,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(14, 15, 8, 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE5ECEF)),
                ),
                labelText: label,
                labelStyle: TextStyle(
                  color: accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFF9AA7AD),
                  fontSize: 11.5,
                ),
                suffixIcon: suffix,
                suffixIconConstraints: const BoxConstraints(minWidth: 36),
              ),
            ),
          ),
        ],
      );
}

class _DestinationDropdown extends StatelessWidget {
  const _DestinationDropdown({required this.items, required this.onSelected});

  final List<_HeroDestination> items;
  final ValueChanged<_HeroDestination> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxHeight: 190),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F8),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE1E8EA)),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final item = items[index];
            return ListTile(
              dense: true,
              onTap: () => onSelected(item),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  item.imageUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.landscape_rounded),
                  ),
                ),
              ),
              title: Text(
                item.name,
                style: const TextStyle(
                  color: _CustomerHomeScreenState._ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                item.district,
                style: const TextStyle(
                  color: _CustomerHomeScreenState._muted,
                  fontSize: 9.5,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF6FAE20),
                size: 19,
              ),
            );
          },
        ),
      );
}

class _DestinationHistoryStrip extends StatelessWidget {
  const _DestinationHistoryStrip({
    required this.items,
    required this.onSelected,
    this.darkText = false,
  });

  final List<String> items;
  final ValueChanged<String> onSelected;
  final bool darkText;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 35,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, index) => ActionChip(
            onPressed: () => onSelected(items[index]),
            label: Text(
              items[index],
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: _CustomerHomeScreenState._ink,
              ),
            ),
            avatar: const Icon(
              Icons.history_rounded,
              size: 15,
              color: Color(0xFF739F18),
            ),
            backgroundColor: Colors.white.withValues(alpha: .92),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
}

class _RideCard extends StatelessWidget {
  const _RideCard({
    required this.ride,
    required this.onTap,
    required this.onWholeVehicle,
  });

  final LiveTourPackage ride;
  final VoidCallback onTap;
  final VoidCallback onWholeVehicle;

  String get _vehicleAsset {
    final raw = '${ride.vehicle} ${ride.title}'.toLowerCase();
    if (raw.contains('bike') || raw.contains('motor')) {
      return 'assets/vehicles/bike.png';
    }
    if (raw.contains('rickshaw') || raw.contains('auto')) {
      return 'assets/vehicles/rickshaw.png';
    }
    if (raw.contains('coaster') || raw.contains('coster') || raw.contains('bus')) {
      return 'assets/vehicles/coaster.png';
    }
    if (raw.contains('van')) return 'assets/vehicles/van.png';
    if (raw.contains('suv') || raw.contains('prado') || raw.contains('fortuner')) {
      return 'assets/vehicles/suv.png';
    }
    return 'assets/vehicles/sedan.png';
  }

  Widget _vehicleImage() {
    final url = ride.coverImageUrl;
    if (url != null && url.trim().isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        cacheWidth: 300,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Image.asset(
          _vehicleAsset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }
    return Image.asset(
      _vehicleAsset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E9EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 94,
                    height: 78,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: _vehicleImage(),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF6D9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: Color(0xFF5C9417),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  ride.destination,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _CustomerHomeScreenState._ink,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${ride.pickupPoint} → ${ride.destination}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _CustomerHomeScreenState._muted,
                            fontSize: 9.8,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _RideMeta(
                              icon: Icons.event_seat_rounded,
                              text: '${ride.bookableSeats} seats left',
                            ),
                            _RideMeta(
                              icon: Icons.schedule_rounded,
                              text: DateFormat('dd MMM, hh:mm a')
                                  .format(ride.departureAt),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _RateBox(
                      label: 'Per seat',
                      amount: ride.pricePerSeat,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RateBox(
                      label: 'Whole vehicle',
                      amount: ride.wholeVehiclePrice,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(38),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        side: const BorderSide(color: Color(0xFF87C72B)),
                        foregroundColor: const Color(0xFF568B15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.event_seat_rounded, size: 15),
                      label: const Text(
                        'Book seat',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onWholeVehicle,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(38),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        backgroundColor: _CustomerHomeScreenState._lime,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.directions_car_filled_rounded, size: 15),
                      label: const Text(
                        'Whole vehicle',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _RideMeta extends StatelessWidget {
  const _RideMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6FAE20)),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              color: _CustomerHomeScreenState._muted,
              fontSize: 8.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _RateBox extends StatelessWidget {
  const _RateBox({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EDEF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _CustomerHomeScreenState._muted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'PKR ${NumberFormat('#,##0').format(amount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF5A9018),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _EmptyRides extends StatelessWidget {
  const _EmptyRides({required this.destination});

  final String destination;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E9EB)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.directions_car_outlined,
              color: Color(0xFF6FAE20),
              size: 38,
            ),
            const SizedBox(height: 10),
            const Text(
              'No matching ride available',
              style: TextStyle(
                color: _CustomerHomeScreenState._ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              destination.trim().isEmpty
                  ? 'No ride is currently available for this filter.'
                  : 'No active ride is currently going towards $destination.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _CustomerHomeScreenState._muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}
