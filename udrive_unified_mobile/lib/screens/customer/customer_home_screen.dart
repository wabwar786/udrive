
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/booking/trip_operations_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import '../operations/live_trip_navigation_screen.dart';
import '../safety/customer_sos_sheet.dart';
import 'live_packages_screen.dart';
import 'live_explore_screen.dart';
import 'udrive_route_flow_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

enum _HomeServiceMode { localRide, exploreKashmir }

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  static const _ink = Color(0xFF10212B);
  static const _lime = Color(0xFF8ED12B);
  static const _muted = Color(0xFF667781);
  static const _surface = Color(0xFFF6F8FA);

  final _pickup = TextEditingController(text: 'Detecting current address…');
  final _destination = TextEditingController();
  final _pageController = PageController();
  final _scrollController = ScrollController();
  final _mapController = MapController();
  final _resultsKey = GlobalKey();
  late final ApiClient _api;

  Timer? _heroTimer;
  Timer? _tripTimer;
  int _heroIndex = 0;
  bool _loadingDestinations = true;
  bool _showDestinationList = false;
  bool _searched = true;
  bool _locating = false;
  String _destinationQuery = '';
  String? _selectedVehicleType;
  DateTime? _selectedDepartureDay;
  bool _historyNextMonthOnly = true;
  bool _showVehicleTypeBar = false;
  _HomeServiceMode _serviceMode = _HomeServiceMode.localRide;
  DateTime _travelDate = DateTime.now();
  bool _offline = false;
  LatLng _currentPoint = const LatLng(34.3700, 73.4711);
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _resultsTitle = 'Available local rides';
  List<_HeroDestination> _destinations = const [];
  TripOperationsRepository? _tripRepository;
  MobileTrip? _activeTrip;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(SessionStore());
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() => _offline = results.every((value) => value == ConnectivityResult.none));
    });
    Connectivity().checkConnectivity().then((results) {
      if (mounted) setState(() => _offline = results.every((value) => value == ConnectivityResult.none));
    });
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
    _pickup.text = 'Detecting current address…';

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _pickup.text = 'Turn on location to use current address';
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _pickup.text = 'Allow location from app settings';
        return;
      }
      if (permission == LocationPermission.denied) {
        _pickup.text = 'Allow location to detect pickup';
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _pickup.text = 'Tap location icon to try again';
        return;
      }

      final latitude = position.latitude;
      final longitude = position.longitude;
      final address = await _reverseGeocode(latitude, longitude);
      _pickup.text = address.isNotEmpty
          ? address
          : '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
      if (mounted) {
        final point = LatLng(latitude, longitude);
        setState(() {
          _currentPoint = point;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(point, 15.8);
        });
      }
    } catch (_) {
      _pickup.text = 'Tap location icon to try again';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location could not be detected. Please allow location access and try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }


  Future<String> _reverseGeocode(double latitude, double longitude) async {
    if (!kIsWeb) {
      try {
        final marks = await placemarkFromCoordinates(latitude, longitude);
        if (marks.isNotEmpty) {
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
          if (values.isNotEmpty) return values.join(', ');
        }
      } catch (_) {
        // Fall through to the web-compatible reverse-geocoding service.
      }
    }

    final uri = Uri.https(
      'api.bigdatacloud.net',
      '/data/reverse-geocode-client',
      {
        'latitude': latitude.toStringAsFixed(7),
        'longitude': longitude.toStringAsFixed(7),
        'localityLanguage': 'en',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) return '';
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) return '';
    final values = [
      json['locality'],
      json['city'],
      json['principalSubdivision'],
      json['countryName'],
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    return values.join(', ');
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
      _searched = true;
      _selectedDepartureDay = null;
      _historyNextMonthOnly = true;
      _resultsTitle = _serviceMode == _HomeServiceMode.localRide
          ? 'Local rides to ${value.name}'
          : 'Kashmir trips to ${value.name}';
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

  Future<void> _pickTravelDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _travelDate.isBefore(DateTime.now()) ? DateTime.now() : _travelDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (selected != null && mounted) setState(() => _travelDate = selected);
  }

  void _findRides() {
    FocusScope.of(context).unfocus();
    if (_pickup.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter or detect your pickup location.')),
      );
      return;
    }
    final destination = _destination.text.trim();
    setState(() {
      _destinationQuery = destination.toLowerCase();
      _showDestinationList = false;
      _searched = true;
      _selectedDepartureDay = _serviceMode == _HomeServiceMode.exploreKashmir && destination.isNotEmpty
          ? _travelDate
          : null;
      _historyNextMonthOnly = true;
      _resultsTitle = destination.isEmpty
          ? (_serviceMode == _HomeServiceMode.localRide
              ? 'Available local rides'
              : 'Kashmir tours · next 30 days')
          : (_serviceMode == _HomeServiceMode.localRide
              ? 'Local rides to $destination'
              : 'Kashmir trips to $destination');
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

  bool _looksLikeTour(LiveTourPackage ride) {
    final text = '${ride.title} ${ride.description ?? ''}'.toLowerCase();
    return ride.returnAt != null ||
        ride.itinerary.isNotEmpty ||
        ride.inclusions.isNotEmpty ||
        text.contains('tour') ||
        text.contains('trip') ||
        text.contains('package') ||
        text.contains('valley') ||
        text.contains('lake');
  }

  List<LiveTourPackage> _matchingRides(List<LiveTourPackage> source) {
    if (!_searched) return const [];
    final now = DateTime.now();
    final end = now.add(const Duration(days: 30));
    final query = _destinationQuery.trim();
    final day = _selectedDepartureDay;
    final type = _selectedVehicleType;

    final modeMatches = source.where((ride) {
      final isTour = _looksLikeTour(ride);
      return _serviceMode == _HomeServiceMode.exploreKashmir ? isTour : !isTour;
    }).toList();
    // Older API records may not yet contain a service type. In that case,
    // keep the screen useful instead of showing an empty list.
    final candidates = modeMatches.isEmpty ? source : modeMatches;

    final filtered = candidates.where((ride) {
      final searchable = '${ride.destination} ${ride.title} ${ride.pickupPoint} ${ride.startingCity}'
          .toLowerCase();
      final matchesQuery = query.isEmpty || searchable.contains(query);
      final matchesDay = day == null || DateUtils.isSameDay(ride.departureAt, day);
      final matchesType = type == null || _vehicleTypeForRide(ride) == type;
      final inNextThirtyDays = !ride.departureAt.isBefore(now) && ride.departureAt.isBefore(end);
      return matchesQuery && matchesDay && matchesType && inNextThirtyDays;
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
    final hour = DateTime.now().toLocal().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 22) return 'Good evening';
    return 'Good night';
  }

  String _firstName(String value) {
    final clean = value.trim();
    return clean.isEmpty ? 'Traveller' : clean.split(RegExp(r'\s+')).first;
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _connectivitySubscription?.cancel();
    _tripTimer?.cancel();
    _pickup.dispose();
    _destination.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final recentBookings = controller.liveBookings.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ColoredBox(
      color: const Color(0xFF111311),
      child: Stack(
        children: [
          Positioned.fill(child: _buildMapBackground()),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .36),
                      Colors.transparent,
                      Colors.black.withValues(alpha: .18),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _MapActionButton(
                    icon: Icons.menu_rounded,
                    onTap: () => Scaffold.of(context).openDrawer(),
                  ),
                  const Spacer(),
                  if (_activeTrip != null) ...[
                    _MapActionButton(
                      icon: Icons.route_rounded,
                      onTap: _openActiveTrip,
                      showDot: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _CompactSosButton(onTap: () => CustomerSosSheet.show(context)),
                  const SizedBox(width: 8),
                  _MapActionButton(
                    icon: Icons.notifications_none_rounded,
                    onTap: () => widget.onNavigate('notifications'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 92,
            left: 16,
            right: 16,
            child: _PickupMapCard(
              address: _pickup.text,
              locating: _locating,
              onTap: _loadLocation,
            ),
          ),
          if (_offline)
            const Positioned(
              top: 158,
              left: 16,
              right: 16,
              child: _OfflineMapPill(),
            ),
          DraggableScrollableSheet(
            initialChildSize: .56,
            minChildSize: .48,
            maxChildSize: .90,
            snap: true,
            snapSizes: const [.56, .90],
            builder: (context, sheetController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFA181A18),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, -8)),
                  ],
                ),
                child: ListView(
                  controller: sheetController,
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 32),
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _UDriveServicesGrid(
                      onCity: () => _openRouteFlow(UDriveServiceType.city),
                      onTours: () => _openRouteFlow(UDriveServiceType.tours),
                      onPrivate: () => _openRouteFlow(UDriveServiceType.privateVehicle),
                      onExplore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveExploreScreen())),
                    ),
                    const SizedBox(height: 14),
                    Material(
                      color: const Color(0xFF303330),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () => _openRouteFlow(UDriveServiceType.city),
                        borderRadius: BorderRadius.circular(18),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: Colors.white, size: 30),
                              SizedBox(width: 14),
                              Expanded(child: Text('Where to?', style: TextStyle(color: Colors.white70, fontSize: 19, fontWeight: FontWeight.w800))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Text('Recent bookings', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 4),
                    if (recentBookings.isEmpty)
                      const _EmptyRecentBookings()
                    else
                      ...recentBookings.take(2).map((booking) => _RecentBookingTile(
                            booking: booking,
                            onTap: () => _openRecentBooking(booking),
                          )),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }


  Future<void> _openRecentBooking(LiveBooking booking) async {
    final label = booking.destinationLabel.trim();
    if (label.isEmpty) return;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$label, Pakistan',
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'pk',
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'UDrive-Mobile/1.0',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      double lat = _currentPoint.latitude;
      double lng = _currentPoint.longitude;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final raw = jsonDecode(response.body);
        if (raw is List && raw.isNotEmpty && raw.first is Map) {
          final first = Map<String, dynamic>.from(raw.first as Map);
          lat = double.tryParse('${first['lat']}') ?? lat;
          lng = double.tryParse('${first['lon']}') ?? lng;
        }
      }
      final isTour = booking.tourPackageId != null || booking.packageBookingId != null;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UDriveRouteFlowScreen(
            serviceType: isTour ? UDriveServiceType.tours : UDriveServiceType.city,
            pickupLabel: _pickup.text.trim().isEmpty ? booking.pickupLabel : _pickup.text.trim(),
            pickupPoint: _currentPoint,
            initialDestinationLabel: label,
            initialDestinationLatitude: lat,
            initialDestinationLongitude: lng,
            skipRouteEntry: true,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This booking destination could not be opened right now.')),
      );
    }
  }

  Future<void> _openRouteFlow(UDriveServiceType type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UDriveRouteFlowScreen(
          serviceType: type,
          pickupLabel: _pickup.text.trim().isEmpty ? 'Current location' : _pickup.text.trim(),
          pickupPoint: _currentPoint,
        ),
      ),
    );
  }

  void _switchMode(_HomeServiceMode mode) {
    _destination.clear();
    setState(() {
      _serviceMode = mode;
      _destinationQuery = '';
      _searched = true;
      _selectedDepartureDay = null;
      _historyNextMonthOnly = true;
      _resultsTitle = mode == _HomeServiceMode.localRide
          ? 'Available local rides'
          : 'Kashmir tours · next 30 days';
      _showDestinationList = false;
    });
  }

  Widget _buildMapBackground() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPoint,
        initialZoom: 14.8,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.udrive.mobile',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _currentPoint,
              width: 116,
              height: 92,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202220),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10)],
                    ),
                    child: const Text(
                      'PICKUP POINT',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Icon(Icons.location_pin, color: _lime, size: 50),
                ],
              ),
            ),
          ],
        ),
        RichAttributionWidget(
          attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({required this.icon, required this.onTap, this.showDot = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xE8202220),
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: Colors.black45,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 25),
                if (showDot)
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(radius: 4, backgroundColor: _CustomerHomeScreenState._lime),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _CompactSosButton extends StatelessWidget {
  const _CompactSosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFD92D20),
        borderRadius: BorderRadius.circular(24),
        elevation: 8,
        shadowColor: Colors.black45,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: const SizedBox(
            height: 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sos_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 5),
                  Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PickupMapCard extends StatelessWidget {
  const _PickupMapCard({required this.address, required this.locating, required this.onTap});
  final String address;
  final bool locating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: const Color(0xEE202220),
          borderRadius: BorderRadius.circular(16),
          elevation: 8,
          shadowColor: Colors.black45,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    const Icon(Icons.my_location_rounded, color: _CustomerHomeScreenState._lime, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Pickup point', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700)),
                          Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    locating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _OfflineMapPill extends StatelessWidget {
  const _OfflineMapPill();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF79009),
            borderRadius: BorderRadius.circular(99),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: const Text(
            'Offline mode · confirmation will need SMS',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
      );
}

class _SmallModePill extends StatelessWidget {
  const _SmallModePill({required this.selected, required this.icon, required this.label, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? _CustomerHomeScreenState._lime : const Color(0xFF343734),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: selected ? _CustomerHomeScreenState._ink : Colors.white70),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(color: selected ? _CustomerHomeScreenState._ink : Colors.white70, fontSize: 11, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      );
}

class _InDriveSearchField extends StatelessWidget {
  const _InDriveSearchField({
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.hint,
    this.suffix,
    this.onTap,
    this.onChanged,
  });

  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final String hint;
  final Widget? suffix;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onTap: onTap,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600),
          prefixIcon: Icon(icon, color: iconColor, size: 21),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFF343734),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _CustomerHomeScreenState._lime, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        ),
      );
}

class _TourDateTile extends StatelessWidget {
  const _TourDateTile({required this.date, required this.onTap});
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF343734),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: _CustomerHomeScreenState._lime),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Travel date', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(date),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              ],
            ),
          ),
        ),
      );
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


class _TopSosButton extends StatelessWidget {
  const _TopSosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x55E53935), blurRadius: 12)],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sos_rounded, color: Colors.white, size: 20),
                SizedBox(width: 5),
                Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      );
}

class _CompactModeSelector extends StatelessWidget {
  const _CompactModeSelector({required this.mode, required this.onChanged});
  final _HomeServiceMode mode;
  final ValueChanged<_HomeServiceMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xDD202322),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(_HomeServiceMode.localRide, Icons.directions_bus_rounded, 'Local'),
            _item(_HomeServiceMode.exploreKashmir, Icons.landscape_rounded, 'Tours'),
          ],
        ),
      );

  Widget _item(_HomeServiceMode value, IconData icon, String label) {
    final selected = mode == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _CustomerHomeScreenState._lime : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? _CustomerHomeScreenState._ink : Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: selected ? _CustomerHomeScreenState._ink : Colors.white70, fontWeight: FontWeight.w900, fontSize: 12)),
          ],
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
                                style: TextStyle(
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
    this.onChanged,
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
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final dark = fillColor.computeLuminance() < .35;
    return Row(
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
            onChanged: onChanged,
            style: TextStyle(
              color: dark ? Colors.white : _CustomerHomeScreenState._ink,
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
                borderSide: BorderSide(
                  color: dark ? Colors.white24 : const Color(0xFFE5ECEF),
                ),
              ),
              labelText: label,
              labelStyle: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
              hintText: hint,
              hintStyle: TextStyle(
                color: dark ? Colors.white54 : const Color(0xFF9AA7AD),
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
      return 'assets/vehicles_photo/bike_photo.png';
    }
    if (raw.contains('rickshaw') || raw.contains('auto')) {
      return 'assets/vehicles_photo/rickshaw_photo.png';
    }
    if (raw.contains('coaster') || raw.contains('coster') || raw.contains('bus')) {
      return 'assets/vehicles_photo/coaster_photo.png';
    }
    if (raw.contains('van')) return 'assets/vehicles_photo/coaster_photo.png';
    if (raw.contains('suv') || raw.contains('prado') || raw.contains('fortuner')) {
      return 'assets/vehicles_photo/private_car_clean.png';
    }
    return 'assets/vehicles_photo/car_clean.png';
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
                              const SizedBox(width: 5),
                              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
                              Text(
                                ride.destinationRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: _CustomerHomeScreenState._ink,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
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
                            _RideMeta(
                              icon: Icons.star_rounded,
                              text: 'Vehicle ${ride.vehicleRating.toStringAsFixed(1)}',
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

class _ServiceModeSelector extends StatelessWidget {
  const _ServiceModeSelector({required this.mode, required this.onChanged});
  final _HomeServiceMode mode;
  final ValueChanged<_HomeServiceMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 16, offset: Offset(0, 7))],
        ),
        child: Row(
          children: [
            Expanded(child: _item(_HomeServiceMode.localRide, Icons.directions_bus_rounded, 'Local Ride', 'Per-seat travel')),
            Expanded(child: _item(_HomeServiceMode.exploreKashmir, Icons.landscape_rounded, 'Explore Kashmir', 'Tour packages')),
          ],
        ),
      );

  Widget _item(_HomeServiceMode value, IconData icon, String title, String subtitle) {
    final selected = mode == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF10212B) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : const Color(0xFF10212B), size: 21),
            const SizedBox(width: 7),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, style: TextStyle(color: selected ? Colors.white : const Color(0xFF10212B), fontWeight: FontWeight.w900, fontSize: 13)),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white70 : const Color(0xFF667781), fontSize: 9.5, fontWeight: FontWeight.w600)),
            ])),
          ],
        ),
      ),
    );
  }
}

class _OfflineBookingBanner extends StatelessWidget {
  const _OfflineBookingBanner();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: const Color(0xFFFFF3D8), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFD789))),
        child: const Row(children: [
          Icon(Icons.signal_wifi_connected_no_internet_4_rounded, color: Color(0xFF9A6500), size: 20),
          SizedBox(width: 9),
          Expanded(child: Text('Offline mode: saved routes remain visible. SMS confirmation will be required for offline bookings.', style: TextStyle(color: Color(0xFF714B00), fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _ActiveTripHomeCard extends StatelessWidget {
  const _ActiveTripHomeCard({required this.trip, required this.onTap});
  final MobileTrip trip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF10212B), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Color(0xFF8ED12B), child: Icon(Icons.route_rounded, color: Colors.white)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trip.tripStatus == 'TripStarted' ? 'Trip in progress' : 'Driver is coming', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                Text('${trip.pickupLabel} → ${trip.destinationLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),
      );
}

class _UDriveServicesGrid extends StatelessWidget {
  const _UDriveServicesGrid({
    required this.onCity,
    required this.onTours,
    required this.onPrivate,
    required this.onExplore,
  });

  final VoidCallback onCity;
  final VoidCallback onTours;
  final VoidCallback onPrivate;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 218,
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 9,
          mainAxisSpacing: 9,
          childAspectRatio: 1.75,
          children: [
            _ServiceTile(
              title: 'Tours & Trips',
              subtitle: 'seat or full vehicle',
              imageAsset: 'assets/vehicles_photo/tour_clean.png',
              onTap: onTours,
            ),
            _ServiceTile(
              title: 'Travel within city',
              subtitle: 'car, bike, rickshaw',
              imageAsset: 'assets/vehicles_photo/car_clean.png',
              onTap: onCity,
            ),
            _ServiceTile(
              title: 'Private Vehicle',
              subtitle: 'coster, car, bike',
              imageAsset: 'assets/vehicles_photo/private_car_clean.png',
              onTap: onPrivate,
            ),
            _ServiceTile(
              title: 'Explore Kashmir',
              subtitle: 'destinations & experiences',
              imageAsset: 'assets/images/neelum.png',
              onTap: onExplore,
              landscape: true,
            ),
          ],
        ),
      );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.onTap,
    this.landscape = false,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final VoidCallback onTap;
  final bool landscape;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF181B19),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF3A3F3B)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF272B28), Color(0xFF111311)],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  right: -26,
                  bottom: -34,
                  child: Container(
                    width: 126,
                    height: 126,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB7F20A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: landscape ? -8 : 4,
                  bottom: landscape ? -5 : 5,
                  child: SizedBox(
                    width: landscape ? 108 : 100,
                    height: landscape ? 72 : 58,
                    child: ClipRect(
                      child: Image.asset(
                        imageAsset,
                        fit: landscape ? BoxFit.cover : BoxFit.contain,
                        alignment: Alignment.bottomRight,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.directions_car_filled_rounded,
                          color: Color(0xFF111311),
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFF181B19),
                            const Color(0xFF181B19).withValues(alpha: .92),
                            Colors.transparent,
                          ],
                          stops: const [0, .48, .78],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 13, 76, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 9.5,
                          height: 1.18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RecentBookingTile extends StatelessWidget {
  const _RecentBookingTile({required this.booking, required this.onTap});

  final LiveBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd MMM, h:mm a').format(booking.pickupAt);
    final isTour = booking.tourPackageId != null || booking.packageBookingId != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                child: Icon(isTour ? Icons.landscape_rounded : Icons.route_rounded, color: _CustomerHomeScreenState._lime, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.destinationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.pickupLabel}  •  $date',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentBookings extends StatelessWidget {
  const _EmptyRecentBookings();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
        child: const Row(
          children: [
            Icon(Icons.receipt_long_rounded, color: Colors.white38, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Your completed and upcoming bookings will appear here.', style: TextStyle(color: Colors.white54, fontSize: 11.5))),
          ],
        ),
      );
}

class _RecentPlaceTile extends StatelessWidget {
  const _RecentPlaceTile({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () {},
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        leading: const Icon(Icons.history_rounded, color: Colors.white54, size: 29),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      );
}
