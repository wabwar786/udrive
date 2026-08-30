import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_config.dart';
import '../../core/booking/vehicle_booking_mode.dart';
import '../../core/state/app_controller.dart';
import '../../models/booking_models.dart';
import 'driver_offers_screen.dart';

const _ink = Color(0xFF161816);
const _panel = Color(0xFF202220);
const _tile = Color(0xFF303330);
const _lime = Color(0xFFB7F20A);
const _muted = Color(0xFF9FA59F);

enum UDriveServiceType { city, tours, privateVehicle }

extension UDriveServiceTypeLabel on UDriveServiceType {
  String get title => switch (this) {
        UDriveServiceType.city => 'City-to-City Ride',
        UDriveServiceType.tours => 'Tours & Trips',
        UDriveServiceType.privateVehicle => 'Private Vehicle',
      };

  String get subtitle => switch (this) {
        UDriveServiceType.city => 'car, bike, rickshaw',
        UDriveServiceType.tours => 'coster, car',
        UDriveServiceType.privateVehicle => 'coster, car, bike',
      };
}

class UDriveRouteFlowScreen extends StatefulWidget {
  const UDriveRouteFlowScreen({
    required this.serviceType,
    required this.pickupLabel,
    required this.pickupPoint,
    this.initialDestinationLabel,
    this.initialDestinationLatitude,
    this.initialDestinationLongitude,
    this.skipRouteEntry = false,
    this.onlyVehicleKey,
    super.key,
  });

  final UDriveServiceType serviceType;
  final String pickupLabel;
  final LatLng pickupPoint;
  final String? initialDestinationLabel;
  final double? initialDestinationLatitude;
  final double? initialDestinationLongitude;
  final bool skipRouteEntry;

  /// Restricts the next screen to a single vehicle type ('car', 'bike',
  /// 'coster'). Set when the customer already chose a service on Home, so
  /// "Find a Car" never shows bikes or coasters.
  final String? onlyVehicleKey;

  @override
  State<UDriveRouteFlowScreen> createState() => _UDriveRouteFlowScreenState();
}

class _UDriveRouteFlowScreenState extends State<UDriveRouteFlowScreen> {
  late final TextEditingController _from;
  final _to = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  Timer? _debounce;
  bool _searching = false;
  bool _editingFrom = false;
  late LatLng _pickupPoint;
  late String _pickupLabel;
  late UDriveServiceType _serviceType;
  bool _initialWholeVehicle = false;
  static const List<_PlaceResult> _fallbackDestinations = [
    _PlaceResult('Muzaffarabad', 'AJK capital • Domel and city centre', 34.3700, 73.4700),
    _PlaceResult('Neelum Valley', 'Athmuqam, Keran, Sharda and Kel', 34.5985, 73.9070),
    _PlaceResult('Keran', 'Neelum District • Riverside destination', 34.6501, 73.9479),
    _PlaceResult('Sharda', 'Neelum Valley • Sharda bazaar and river', 34.7937, 74.1883),
    _PlaceResult('Kel', 'Upper Neelum Valley • Arang Kel access', 34.8077, 74.3460),
    _PlaceResult('Rawalakot', 'Poonch District • Banjosa and Toli Pir', 33.8578, 73.7604),
    _PlaceResult('Banjosa Lake', 'Rawalakot • Family tourism destination', 33.8107, 73.8135),
    _PlaceResult('Pir Chinasi', 'Muzaffarabad • Mountain viewpoint', 34.3858, 73.5485),
    _PlaceResult('Leepa Valley', 'Hattian Bala District • Scenic valley', 34.3103, 73.8674),
    _PlaceResult('Mirpur', 'AJK • Mangla Lake and city centre', 33.1484, 73.7519),
  ];

  List<_PlaceResult> _results = _fallbackDestinations;
  List<_PlaceResult> _recentSearches = const [];
  List<_PlaceResult> _catalogPlaces = _fallbackDestinations;
  String? _searchMessage;

  @override
  void initState() {
    super.initState();
    _pickupPoint = widget.pickupPoint;
    _pickupLabel = widget.pickupLabel;
    _serviceType = widget.serviceType;
    _initialWholeVehicle = widget.serviceType == UDriveServiceType.privateVehicle;
    _from = TextEditingController(text: widget.pickupLabel);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait([
        _loadRecentSearches(),
        _loadCatalogDestinations(),
      ]);
      if (widget.skipRouteEntry &&
          widget.initialDestinationLabel != null &&
          widget.initialDestinationLatitude != null &&
          widget.initialDestinationLongitude != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UDriveVehicleSelectionScreen(
              serviceType: _serviceType,
              initialWholeVehicle: _initialWholeVehicle,
              onlyVehicleKey: widget.onlyVehicleKey,
              pickupLabel: _pickupLabel,
              pickupPoint: _pickupPoint,
              destination: _PlaceResult(
                widget.initialDestinationLabel!,
                '',
                widget.initialDestinationLatitude!,
                widget.initialDestinationLongitude!,
              ),
            ),
          ),
        );
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('udrive_recent_destination_searches') ?? const [];
    final items = <_PlaceResult>[];
    for (final value in raw) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(value) as Map);
        items.add(_PlaceResult(
          '${map['title'] ?? ''}',
          '${map['subtitle'] ?? ''}',
          (map['latitude'] as num?)?.toDouble() ?? 0,
          (map['longitude'] as num?)?.toDouble() ?? 0,
        ));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recentSearches = items.where((e) => e.latitude != 0 && e.longitude != 0).take(8).toList();
      if (_to.text.trim().isEmpty && !_editingFrom) {
        _results = _defaultResults();
      }
    });
  }

  Future<void> _loadCatalogDestinations() async {
    try {
      final controller = AppControllerScope.of(context);
      final response = await controller.apiClient.getJson(
        '/api/v1/catalog/destinations?language=en',
        authenticated: false,
      );
      final raw = response['data'];
      final loaded = <_PlaceResult>[];
      if (raw is List) {
        for (final item in raw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final name = '${map['name'] ?? ''}'.trim();
          final district = '${map['district'] ?? ''}'.trim();
          final summary = '${map['summary'] ?? ''}'.trim();
          final latitude = (map['latitude'] as num?)?.toDouble() ?? 0;
          final longitude = (map['longitude'] as num?)?.toDouble() ?? 0;
          if (name.isEmpty || latitude == 0 || longitude == 0) continue;
          loaded.add(_PlaceResult(
            name,
            [district, summary].where((value) => value.isNotEmpty).join(' • '),
            latitude,
            longitude,
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        _catalogPlaces = _mergePlaces([
          ...loaded,
          ..._fallbackDestinations,
        ]);
        _searchMessage = null;
        if (_to.text.trim().isEmpty && !_editingFrom) {
          _results = _defaultResults();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catalogPlaces = _fallbackDestinations;
        _searchMessage = 'Live destination sync is unavailable. Saved Kashmir destinations are ready below.';
        if (_to.text.trim().isEmpty && !_editingFrom) {
          _results = _defaultResults();
        }
      });
    }
  }

  List<_PlaceResult> _defaultResults() => _mergePlaces([
        ..._recentSearches,
        ..._catalogPlaces,
      ]).take(14).toList();

  List<_PlaceResult> _localMatches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return _defaultResults();
    return _catalogPlaces.where((place) {
      final text = '${place.title} ${place.subtitle}'.toLowerCase();
      return text.contains(needle);
    }).take(12).toList();
  }

  List<_PlaceResult> _mergePlaces(Iterable<_PlaceResult> values) {
    final seen = <String>{};
    final merged = <_PlaceResult>[];
    for (final item in values) {
      final key = '${item.title.toLowerCase()}|${item.latitude.toStringAsFixed(4)}|${item.longitude.toStringAsFixed(4)}';
      if (seen.add(key)) merged.add(item);
    }
    return merged;
  }

  Future<void> _rememberSearch(_PlaceResult place) async {
    final prefs = await SharedPreferences.getInstance();
    final items = <_PlaceResult>[place, ..._recentSearches.where((e) =>
      e.title.toLowerCase() != place.title.toLowerCase() ||
      e.subtitle.toLowerCase() != place.subtitle.toLowerCase())].take(8).toList();
    await prefs.setStringList(
      'udrive_recent_destination_searches',
      items.map((e) => jsonEncode({
        'title': e.title,
        'subtitle': e.subtitle,
        'latitude': e.latitude,
        'longitude': e.longitude,
      })).toList(),
    );
    if (mounted) setState(() => _recentSearches = items);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _from.dispose();
    _to.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _onChanged(String value, {required bool from}) {
    _editingFrom = from;
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searching = false;
        _searchMessage = null;
        _results = from ? _localMatches(query) : _defaultResults();
      });
      return;
    }

    final local = _localMatches(query);
    setState(() {
      _results = local;
      _searchMessage = local.isEmpty ? 'Searching all Pakistan locations…' : null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    final local = _localMatches(query);
    setState(() => _searching = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$query, Pakistan',
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '10',
        'countrycodes': 'pk',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'UDrive-Mobile/1.0',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Location search unavailable');
      }
      final raw = jsonDecode(response.body);
      final online = <_PlaceResult>[];
      if (raw is List) {
        for (final entry in raw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(entry);
          final display = '${map['display_name'] ?? ''}'.trim();
          final parts = display
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
          final item = _PlaceResult(
            parts.isEmpty ? query : parts.first,
            parts.skip(1).take(4).join(', '),
            double.tryParse('${map['lat']}') ?? 0,
            double.tryParse('${map['lon']}') ?? 0,
          );
          if (item.latitude != 0 && item.longitude != 0) online.add(item);
        }
      }
      if (!mounted) return;
      final merged = _mergePlaces([...local, ...online]);
      setState(() {
        _results = merged;
        _searchMessage = merged.isEmpty
            ? 'No destination found. Try a nearby city, district or landmark.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = local;
        _searchMessage = local.isEmpty
            ? 'Online location search is unavailable. Try a saved Kashmir destination below.'
            : null;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _select(_PlaceResult place) {
    if (_editingFrom) {
      setState(() {
        _pickupPoint = LatLng(place.latitude, place.longitude);
        _pickupLabel = '${place.title}${place.subtitle.isEmpty ? '' : ', ${place.subtitle}'}';
        _from.text = _pickupLabel;
        _results = _recentSearches;
        _editingFrom = false;
      });
      _toFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    _rememberSearch(place);
    Navigator.push(context, MaterialPageRoute(builder: (_) => UDriveVehicleSelectionScreen(
      serviceType: _serviceType,
      initialWholeVehicle: _initialWholeVehicle,
      pickupLabel: _pickupLabel,
      pickupPoint: _pickupPoint,
      destination: place,
    )));
  }

  InputDecoration _fieldDecoration(String label, IconData icon, {Widget? suffix}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted, fontSize: 12),
    prefixIcon: Icon(icon, color: Colors.white, size: 25),
    suffixIcon: suffix,
    filled: true,
    fillColor: _tile,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white24)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white, width: 1.5)),
  );

  @override
  Widget build(BuildContext context) {
    final activeText = (_editingFrom ? _from.text : _to.text).trim();
    final typed = activeText.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _pickupPoint,
                  initialZoom: 13.4,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
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
                        point: _pickupPoint,
                        width: 46,
                        height: 46,
                        child: const Icon(
                          Icons.location_pin,
                          color: _lime,
                          size: 44,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Positioned.fill(
            child: ColoredBox(color: Color(0xB8121513)),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Row(
                    children: [
                      IconButton.filled(
                        onPressed: () => Navigator.maybePop(context),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xA8121413),
                        ),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _serviceType.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xA8121413),
                        ),
                        icon: const Icon(
                          Icons.home_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xE8151715),
                      border: Border(
                        top: BorderSide(color: Colors.white12),
                      ),
                    ),
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Column(
                            children: [
                              // Service/booking mode is chosen from the home card.
                              // Keep this screen focused only on pickup and destination.
                              TextField(
                                controller: _from,
                                focusNode: _fromFocus,
                                onTap: () {
                                  setState(() => _editingFrom = true);
                                  _onChanged(_from.text, from: true);
                                },
                                onChanged: (value) {
                                  setState(() => _editingFrom = true);
                                  _onChanged(value, from: true);
                                },
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: _fieldDecoration(
                                  'Pickup location',
                                  Icons.my_location_rounded,
                                ),
                              ),
                              const SizedBox(height: 9),
                              TextField(
                                controller: _to,
                                focusNode: _toFocus,
                                textInputAction: TextInputAction.search,
                                onTap: () =>
                                    setState(() => _editingFrom = false),
                                onChanged: (value) {
                                  setState(() => _editingFrom = false);
                                  _onChanged(value, from: false);
                                },
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: _fieldDecoration(
                                  'Search destination',
                                  Icons.search_rounded,
                                  suffix: _to.text.isEmpty
                                      ? const Icon(
                                          Icons.map_rounded,
                                          color: Color(0xFF75B8FF),
                                        )
                                      : IconButton(
                                          onPressed: () {
                                            _to.clear();
                                            _onChanged('', from: false);
                                            setState(() {});
                                          },
                                          icon: const Icon(
                                            Icons.cancel_rounded,
                                            color: Colors.white54,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          child: Row(
                            children: [
                              Flexible(
                                child: _FilterChip(
                                  label: typed
                                      ? 'Search results'
                                      : 'Popular Kashmir destinations',
                                  selected: true,
                                ),
                              ),
                              if (_searching) ...[
                                const Spacer(),
                                const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _lime,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: _results.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _searching
                                              ? Icons.travel_explore_rounded
                                              : Icons.search_rounded,
                                          color: _searching
                                              ? _lime
                                              : Colors.white38,
                                          size: 42,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _searchMessage ??
                                              'Type a city, district, hotel or Kashmir destination.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12.5,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    24,
                                  ),
                                  itemCount: _results.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    color: Colors.white10,
                                    height: 1,
                                    indent: 48,
                                  ),
                                  itemBuilder: (context, index) {
                                    final place = _results[index];
                                    final distance = const Distance().as(
                                      LengthUnit.Kilometer,
                                      _pickupPoint,
                                      LatLng(
                                        place.latitude,
                                        place.longitude,
                                      ),
                                    );
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      leading: Icon(
                                        typed
                                            ? Icons.location_on_outlined
                                            : Icons.place_rounded,
                                        color: typed ? Colors.white54 : _lime,
                                        size: 27,
                                      ),
                                      title: Text(
                                        place.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        place.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 11.5,
                                          height: 1.25,
                                        ),
                                      ),
                                      trailing: Text(
                                        '${distance.toStringAsFixed(0)} km',
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                      onTap: () => _select(place),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
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

enum _FareBookingMode { perSeat, wholeVehicle }

class UDriveVehicleSelectionScreen extends StatefulWidget {
  const UDriveVehicleSelectionScreen({
    required this.serviceType,
    required this.pickupLabel,
    required this.pickupPoint,
    required this.destination,
    this.initialWholeVehicle = false,
    this.onlyVehicleKey,
    super.key,
  });

  final UDriveServiceType serviceType;
  final String pickupLabel;
  final LatLng pickupPoint;
  final _PlaceResult destination;
  final bool initialWholeVehicle;

  /// When set, only this vehicle type is offered. Values match
  /// [_normaliseVehicle]: 'car', 'bike', 'coster', 'rickshaw'.
  final String? onlyVehicleKey;

  @override
  State<UDriveVehicleSelectionScreen> createState() => _UDriveVehicleSelectionScreenState();
}

class _UDriveVehicleSelectionScreenState extends State<UDriveVehicleSelectionScreen> {
  static const List<_PublicVehicle> _fallbackDemoVehicles = [
    _PublicVehicle(
      id: 'demo-bike-1',
      driverProfileId: 'demo-driver-bike',
      driverName: 'Usman Bike Rider',
      driverRating: 4.8,
      completedTrips: 186,
      safetyScore: 94,
      isOnline: true,
      category: 'Bike',
      bookingMode: VehicleBookingMode.wholeVehicle,
      make: 'Honda',
      model: 'CB 150F',
      year: 2025,
      registrationNumber: 'AJK-BK-101',
      colour: 'Black',
      passengerCapacity: 1,
      luggageCapacity: 1,
      hasAirConditioning: false,
      hasHeating: false,
      isFourByFour: false,
      mountainReadinessScore: 72,
      imageUrl: '',
      serviceAreas: ['Muzaffarabad', 'Mirpur'],
      isDemo: true,
    ),
    _PublicVehicle(
      id: 'demo-car-1',
      driverProfileId: 'demo-driver-car',
      driverName: 'Adeel Khan',
      driverRating: 4.9,
      completedTrips: 342,
      safetyScore: 97,
      isOnline: true,
      category: 'Car',
      make: 'Toyota',
      model: 'Corolla',
      year: 2024,
      registrationNumber: 'AJK-UD-201',
      colour: 'White',
      passengerCapacity: 4,
      luggageCapacity: 3,
      hasAirConditioning: true,
      hasHeating: true,
      isFourByFour: false,
      mountainReadinessScore: 82,
      imageUrl: '',
      serviceAreas: ['Muzaffarabad', 'Neelum Valley'],
      isDemo: true,
    ),
    _PublicVehicle(
      id: 'demo-rickshaw-1',
      driverProfileId: 'demo-driver-rickshaw',
      driverName: 'Bilal Local Ride',
      driverRating: 4.7,
      completedTrips: 221,
      safetyScore: 91,
      isOnline: true,
      category: 'Rickshaw',
      make: 'Sazgar',
      model: 'Royal',
      year: 2025,
      registrationNumber: 'AJK-RK-301',
      colour: 'Green',
      passengerCapacity: 3,
      luggageCapacity: 1,
      hasAirConditioning: false,
      hasHeating: false,
      isFourByFour: false,
      mountainReadinessScore: 65,
      imageUrl: '',
      serviceAreas: ['Muzaffarabad City'],
      isDemo: true,
    ),
    _PublicVehicle(
      id: 'demo-coaster-1',
      driverProfileId: 'demo-driver-coaster',
      driverName: 'Kashmir Group Transport',
      driverRating: 4.9,
      completedTrips: 128,
      safetyScore: 98,
      isOnline: true,
      category: 'Coster',
      bookingMode: VehicleBookingMode.both,
      make: 'Toyota',
      model: 'Coaster',
      year: 2023,
      registrationNumber: 'AJK-CT-401',
      colour: 'Silver',
      passengerCapacity: 22,
      luggageCapacity: 18,
      hasAirConditioning: true,
      hasHeating: true,
      isFourByFour: false,
      mountainReadinessScore: 88,
      imageUrl: '',
      serviceAreas: ['Muzaffarabad', 'Rawalakot', 'Neelum Valley'],
      isDemo: true,
    ),
    _PublicVehicle(
      id: 'demo-suv-1',
      driverProfileId: 'demo-driver-suv',
      driverName: 'Hamza Mountain Tours',
      driverRating: 4.9,
      completedTrips: 274,
      safetyScore: 98,
      isOnline: true,
      category: 'Car',
      make: 'Toyota',
      model: 'Fortuner 4x4',
      year: 2024,
      registrationNumber: 'AJK-SUV-501',
      colour: 'Black',
      passengerCapacity: 6,
      luggageCapacity: 5,
      hasAirConditioning: true,
      hasHeating: true,
      isFourByFour: true,
      mountainReadinessScore: 99,
      imageUrl: '',
      serviceAreas: ['Neelum Valley', 'Leepa Valley', 'Toli Pir'],
      isDemo: true,
    ),
  ];

  int _selected = 0;
  bool _submitting = false;
  bool _autoAccept = false;
  DateTime _tourDate = DateTime.now().add(const Duration(days: 1));
  _FareBookingMode _bookingMode = _FareBookingMode.perSeat;

  /// Booking mode of the vehicle the customer currently has selected. Drivers
  /// set this per vehicle; whole-vehicle is the default.
  VehicleBookingMode get _selectedVehicleBookingMode {
    final id = _selectedVehicleId;
    if (id == null) return VehicleBookingMode.both;
    for (final vehicle in _availableVehicles) {
      if (vehicle.id == id) return vehicle.bookingMode;
    }
    return VehicleBookingMode.both;
  }

  bool get _canBookPerSeat => _selectedVehicleBookingMode.allowsPerSeat;
  bool get _canBookWholeVehicle =>
      _selectedVehicleBookingMode.allowsWholeVehicle;

  /// Both modes are only offered when the driver actually allows both. With a
  /// single permitted mode the toggle is hidden and that mode is forced, so a
  /// seat-only vehicle can never be booked whole and vice versa.
  bool get _showBookingModeToggle => _canBookPerSeat && _canBookWholeVehicle;

  /// Keeps [_bookingMode] legal after the customer switches vehicle.
  void _clampBookingMode() {
    if (_bookingMode == _FareBookingMode.perSeat && !_canBookPerSeat) {
      _bookingMode = _FareBookingMode.wholeVehicle;
    } else if (_bookingMode == _FareBookingMode.wholeVehicle &&
        !_canBookWholeVehicle) {
      _bookingMode = _FareBookingMode.perSeat;
    }
  }

  /// One-line explanation shown in place of the toggle when the driver only
  /// permits a single mode, so the customer understands why there is no choice.
  String? get _bookingModeNotice {
    if (_showBookingModeToggle) return null;
    return _canBookPerSeat
        ? 'This vehicle is offered per seat only.'
        : 'This vehicle is booked as a whole vehicle only.';
  }
  int _seats = 1;
  final _perSeatOffer = TextEditingController();
  final _wholeVehicleOffer = TextEditingController();
  final Map<String, _DbRate> _dbRates = {};
  bool _loadingRates = true;
  List<_PublicVehicle> _availableVehicles = const [];
  bool _loadingVehicles = true;
  String? _vehicleLoadError;
  String? _selectedVehicleId;
  String? _selectedPackageId;
  Timer? _availabilityTimer;

  @override
  void initState() {
    super.initState();
    if (widget.serviceType == UDriveServiceType.privateVehicle || widget.initialWholeVehicle) {
      _bookingMode = _FareBookingMode.wholeVehicle;
    }

    // Every route service must have renderable data on the very first frame.
    // Do not wait for AppController, marketplace data or a network request; on
    // Flutter Web a first-frame exception can otherwise look like a blank page.
    _ensureFallbackRates();
    _availableVehicles = _interleaveVehicleCategories(_fallbackVehiclesForService());
    _loadingVehicles = false;
    _loadingRates = false;
    if (_availableVehicles.isNotEmpty) {
      _selectPublicVehicle(_availableVehicles.first, notify: false);
    }
    final initialChoice = _choices[_selected];
    final initialRate = _dbRates[_normaliseVehicle(initialChoice.name)];
    final initialSeat = _perSeatEstimate(initialChoice, initialRate);
    final initialWhole = _wholeVehicleEstimate(initialChoice, initialRate);
    if (initialSeat > 0) _perSeatOffer.text = initialSeat.round().toString();
    if (initialWhole > 0) _wholeVehicleOffer.text = initialWhole.round().toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadRates();
    });
    _availabilityTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && widget.serviceType == UDriveServiceType.tours) setState(() {});
    });
  }

  Future<void> _loadRates() async {
    try {
      // Inherited application state is intentionally resolved only after the
      // first frame and inside the guarded block.
      final controller = AppControllerScope.of(context);
      if (widget.serviceType == UDriveServiceType.tours) {
        await controller.refreshHomeVehicles(force: true);
      }

      final service = widget.serviceType == UDriveServiceType.privateVehicle
          ? 'PrivateVehicle'
          : widget.serviceType == UDriveServiceType.tours
              ? 'Tours'
              : 'City';

      final responses = await Future.wait([
        controller.apiClient.getJson(
          '/api/v1/catalog/service-rates?serviceType=${widget.serviceType == UDriveServiceType.privateVehicle ? 'PrivateVehicle' : 'City'}',
          authenticated: false,
        ),
        controller.apiClient.getJson(
          '/api/v1/catalog/vehicles?serviceType=$service&limit=120',
          authenticated: false,
        ),
      ]);

      final rateRaw = responses[0]['data'];
      if (rateRaw is List) {
        for (final item in rateRaw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final category = _normaliseVehicle('${map['vehicleCategory'] ?? ''}');
          _dbRates[category] = _DbRate(
            (map['perSeatRate'] as num?)?.toDouble() ?? 0,
            (map['wholeVehicleRate'] as num?)?.toDouble() ?? 0,
            (map['perKmRate'] as num?)?.toDouble() ?? 0,
          );
        }
      }

      final vehicleRaw = responses[1]['data'];
      final vehicles = <_PublicVehicle>[];
      if (vehicleRaw is List) {
        for (final item in vehicleRaw.whereType<Map>()) {
          vehicles.add(_PublicVehicle.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      if (!mounted) return;
      _ensureFallbackRates();
      final sourceVehicles = vehicles.isEmpty
          ? _fallbackVehiclesForService()
          : vehicles;
      final displayVehicles = _interleaveVehicleCategories(sourceVehicles);
      setState(() {
        _availableVehicles = displayVehicles;
        _loadingVehicles = false;
        _vehicleLoadError = null;

        if (displayVehicles.isNotEmpty) {
          final preferred = displayVehicles.firstWhere(
            (vehicle) => vehicle.isOnline,
            orElse: () => displayVehicles.first,
          );
          _selectPublicVehicle(preferred, notify: false);
        }

        if (widget.serviceType == UDriveServiceType.tours) {
          final packages = _matchingPackages(controller);
          if (packages.isNotEmpty) {
            _selectedPackageId ??= packages.first.id;
            final packageIndex = _choices.indexWhere(
              (choice) =>
                  _normaliseVehicle(choice.name) ==
                  _normaliseVehicle(packages.first.vehicle),
            );
            if (packageIndex >= 0) _selected = packageIndex;
          }
        }
      });
      _applySelectedDefaultRates();
    } catch (_) {
      if (!mounted) return;
      _ensureFallbackRates();
      final fallback = _interleaveVehicleCategories(
        _fallbackVehiclesForService(),
      );
      setState(() {
        _availableVehicles = fallback;
        _loadingVehicles = false;
        _vehicleLoadError = null;
      });
      if (fallback.isNotEmpty) {
        _selectPublicVehicle(fallback.first, notify: false);
        _applySelectedDefaultRates();
      }
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  List<_PublicVehicle> _fallbackVehiclesForService() {
    return switch (widget.serviceType) {
      UDriveServiceType.city => _fallbackDemoVehicles,
      UDriveServiceType.tours => _fallbackDemoVehicles
          .where((vehicle) => vehicle.passengerCapacity >= 4)
          .toList(growable: false),
      UDriveServiceType.privateVehicle => _fallbackDemoVehicles
          .where((vehicle) =>
              _normaliseVehicle(vehicle.category) != 'rickshaw')
          .toList(growable: false),
    };
  }

  void _ensureFallbackRates() {
    if (widget.serviceType == UDriveServiceType.tours) {
      _dbRates.putIfAbsent('car', () => const _DbRate(2800, 16500, 95));
      _dbRates.putIfAbsent('coster', () => const _DbRate(2200, 42000, 180));
      return;
    }

    _dbRates.putIfAbsent('bike', () => const _DbRate(450, 1200, 32));
    _dbRates.putIfAbsent('car', () => const _DbRate(1200, 4800, 65));
    _dbRates.putIfAbsent('rickshaw', () => const _DbRate(650, 2200, 40));
    _dbRates.putIfAbsent('coster', () => const _DbRate(900, 18000, 160));
  }

  List<_PublicVehicle> _interleaveVehicleCategories(
    List<_PublicVehicle> vehicles,
  ) {
    final buckets = <String, List<_PublicVehicle>>{
      'bike': <_PublicVehicle>[],
      'car': <_PublicVehicle>[],
      'rickshaw': <_PublicVehicle>[],
      'coster': <_PublicVehicle>[],
    };
    for (final vehicle in vehicles) {
      final type = _normaliseVehicle(
        '${vehicle.category} ${vehicle.make} ${vehicle.model}',
      );
      buckets[type]!.add(vehicle);
    }

    final ordered = <_PublicVehicle>[];
    var index = 0;
    var added = true;
    while (added) {
      added = false;
      for (final type in const ['bike', 'car', 'rickshaw', 'coster']) {
        final bucket = buckets[type]!;
        if (index < bucket.length) {
          ordered.add(bucket[index]);
          added = true;
        }
      }
      index++;
    }
    return ordered;
  }

  _PublicVehicle? get _selectedPublicVehicle {
    if (_selectedVehicleId == null) return null;
    for (final vehicle in _availableVehicles) {
      if (vehicle.id == _selectedVehicleId) return vehicle;
    }
    return null;
  }

  void _selectPublicVehicle(_PublicVehicle vehicle, {bool notify = true}) {
    void apply() {
      _selectedVehicleId = vehicle.id;
      final type = _normaliseVehicle('${vehicle.category} ${vehicle.make} ${vehicle.model}');
      final index = _choices.indexWhere(
        (choice) => _normaliseVehicle(choice.name) == type,
      );
      if (index >= 0) _selected = index;
      _seats = _seats.clamp(1, vehicle.passengerCapacity.clamp(1, 50)).toInt();
      // A different vehicle may permit a different set of booking modes, so
      // snap back to a legal one rather than carrying an illegal choice over.
      _clampBookingMode();
    }

    if (notify) {
      setState(apply);
      _applySelectedDefaultRates();
    } else {
      apply();
    }
  }

  String _publicVehicleAsset(_PublicVehicle vehicle) {
    final type = _normaliseVehicle('${vehicle.category} ${vehicle.make} ${vehicle.model}');
    if (type == 'coster') return 'assets/vehicles_photo/coaster_clean.png';
    if (type == 'bike') return 'assets/vehicles_photo/bike_clean.png';
    if (type == 'rickshaw') return 'assets/vehicles_photo/rickshaw_clean.png';
    return widget.serviceType == UDriveServiceType.privateVehicle
        ? 'assets/vehicles_photo/private_car_clean.png'
        : 'assets/vehicles_photo/car_clean.png';
  }

  Widget _publicVehicleImage(_PublicVehicle vehicle) {
    final fallback = Image.asset(
      _publicVehicleAsset(vehicle),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (vehicle.imageUrl.isEmpty) return fallback;
    return Image.network(
      vehicle.imageUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Stack(
              alignment: Alignment.center,
              children: [
                fallback,
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _lime),
                ),
              ],
            ),
    );
  }

  void _applySelectedDefaultRates() {
    final choice = _choices[_selected];
    LiveTourPackage? package;
    if (widget.serviceType == UDriveServiceType.tours) {
      try {
        package = _matchingPackage(AppControllerScope.of(context), choice);
      } catch (_) {
        // Live tour marketplace state is optional for rendering and fare input.
      }
    }
    final db = _dbRates[_normaliseVehicle(choice.name)];
    final perSeat = package?.pricePerSeat ?? _perSeatEstimate(choice, db);
    final whole = package?.wholeVehiclePrice ?? _wholeVehicleEstimate(choice, db);
    if (perSeat > 0) _perSeatOffer.text = perSeat.round().toString();
    if (whole > 0) _wholeVehicleOffer.text = whole.round().toString();
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _perSeatOffer.dispose();
    _wholeVehicleOffer.dispose();
    super.dispose();
  }

  /// Vehicle options offered on this screen.
  ///
  /// When the customer already picked a service on Home, [onlyVehicleKey]
  /// narrows this to that one type — "Find a Car" must never list bikes or
  /// coasters. If the filter matches nothing (a service/type combination that
  /// does not exist) the unfiltered list is returned rather than an empty
  /// screen, so the customer always has something to book.
  List<_VehicleChoiceData> get _choices {
    final all = _choicesForService;
    final key = widget.onlyVehicleKey;
    if (key == null || key.isEmpty) return all;

    final filtered = all
        .where((choice) => _normaliseVehicle(choice.name) == key)
        .toList(growable: false);
    return filtered.isEmpty ? all : filtered;
  }

  List<_VehicleChoiceData> get _choicesForService => switch (widget.serviceType) {
        UDriveServiceType.city => const [
            _VehicleChoiceData('Bike', '1 seat', 'Fast city travel', 1, 'assets/vehicles_photo/bike_clean.png'),
            _VehicleChoiceData('Car', '4 seats', 'Comfortable city ride', 4, 'assets/vehicles_photo/car_clean.png'),
            _VehicleChoiceData('Rickshaw', '3 seats', 'Economical local ride', 3, 'assets/vehicles_photo/rickshaw_clean.png'),
            _VehicleChoiceData('Coster', '22 seats', 'Shared seat or complete vehicle', 22, 'assets/vehicles_photo/coaster_clean.png'),
          ],
        UDriveServiceType.tours => const [
            _VehicleChoiceData('Car', '4 seats', 'Tour car or shared seat', 4, 'assets/vehicles_photo/car_clean.png'),
            _VehicleChoiceData('Coster', '22 seats', 'Group tour and per-seat travel', 22, 'assets/vehicles_photo/coaster_clean.png'),
          ],
        UDriveServiceType.privateVehicle => const [
            _VehicleChoiceData('Car', '4 seats', 'Book the complete car', 4, 'assets/vehicles_photo/private_car_clean.png'),
            _VehicleChoiceData('Coster', '22 seats', 'Private vehicle for groups', 22, 'assets/vehicles_photo/coaster_clean.png'),
            _VehicleChoiceData('Bike', '1 seat', 'Private bike ride', 1, 'assets/vehicles_photo/bike_clean.png'),
          ],
      };

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _tourDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (value != null) setState(() => _tourDate = value);
  }

  String _normaliseVehicle(String value) {
    final v = value.toLowerCase();
    if (v.contains('coster') || v.contains('coaster') || v.contains('bus') ||
        v.contains('hiace') || v.contains('van') || v.contains('mpv')) {
      return 'coster';
    }
    if (v.contains('bike') || v.contains('motorcycle') || v.contains('motor')) return 'bike';
    if (v.contains('rickshaw') || v.contains('auto')) return 'rickshaw';
    return 'car';
  }

  List<LiveTourPackage> _matchingPackages(AppController controller) {
    if (widget.serviceType != UDriveServiceType.tours) return const [];
    final destination = widget.destination.title.trim().toLowerCase();
    final now = DateTime.now();
    final end = now.add(const Duration(days: 30));
    final candidates = controller.liveMarketplacePackages.where((package) {
      final searchable = '${package.destination} ${package.title} ${package.pickupPoint} ${package.startingCity}'.toLowerCase();
      final matchesDestination = searchable.contains(destination) || destination.contains(package.destination.toLowerCase());
      final withinThirtyDays = package.departureAt.isAfter(now.subtract(const Duration(hours: 2))) && package.departureAt.isBefore(end);
      return matchesDestination && withinThirtyDays;
    }).toList()..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return candidates;
  }

  LiveTourPackage? _matchingPackage(AppController controller, _VehicleChoiceData choice) {
    final packages = _matchingPackages(controller);
    if (packages.isEmpty) return null;
    if (_selectedPackageId != null) {
      for (final package in packages) {
        if (package.id == _selectedPackageId) return package;
      }
    }
    for (final package in packages) {
      if (_normaliseVehicle(package.vehicle) == _normaliseVehicle(choice.name)) return package;
    }
    return packages.first;
  }

  bool _packageBookable(LiveTourPackage package) {
    final minutes = package.departureAt.difference(DateTime.now()).inMinutes;
    return package.bookableSeats > 0 && minutes > 10;
  }

  String _packageTiming(LiveTourPackage package) {
    final minutes = package.departureAt.difference(DateTime.now()).inMinutes;
    if (minutes <= 10) return 'Pickup closed';
    if (minutes < 60) return 'Reaches pickup in about $minutes min';
    if (minutes < 180) return 'Reaches pickup in about ${(minutes / 60).toStringAsFixed(1)} hr';
    final d = package.departureAt;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _packageImage(LiveTourPackage package) {
    final type = _normaliseVehicle(package.vehicle);
    if (type == 'coster') return 'assets/vehicles_photo/coaster_clean.png';
    if (type == 'bike') return 'assets/vehicles_photo/bike_clean.png';
    if (type == 'rickshaw') return 'assets/vehicles_photo/rickshaw_clean.png';
    return 'assets/vehicles_photo/car_clean.png';
  }

  double get _routeDistanceKm {
    final direct = const Distance().as(
      LengthUnit.Kilometer,
      widget.pickupPoint,
      LatLng(widget.destination.latitude, widget.destination.longitude),
    );
    // Approximate road distance until a routing engine is configured.
    return (direct * 1.18).clamp(1.0, 2000.0).toDouble();
  }

  double _wholeVehicleEstimate(_VehicleChoiceData choice, _DbRate? rate) {
    if (rate == null) return 0;
    final double distanceFare = rate.perKmRate > 0 ? rate.perKmRate * _routeDistanceKm : 0.0;
    return distanceFare > rate.wholeVehicleRate ? distanceFare : rate.wholeVehicleRate;
  }

  double _perSeatEstimate(_VehicleChoiceData choice, _DbRate? rate) {
    if (rate == null) return 0;
    final whole = _wholeVehicleEstimate(choice, rate);
    final capacity = choice.capacity <= 0 ? 1 : choice.capacity;
    final calculated = whole / capacity;
    return calculated > rate.perSeatRate ? calculated : rate.perSeatRate;
  }

  double _estimatedAmountForChoice(_VehicleChoiceData choice, {required bool wholeVehicle}) {
    final rate = _dbRates[_normaliseVehicle(choice.name)];
    return wholeVehicle ? _wholeVehicleEstimate(choice, rate) : _perSeatEstimate(choice, rate);
  }

  List<Widget> _publicVehicleCards() {
    if (_loadingVehicles) {
      return [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF222522),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: _lime),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Loading approved vehicles from the UDrive server…',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    if (_availableVehicles.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF222522),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x55F79009)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.directions_car_filled_rounded, color: Color(0xFFF79009)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No customer vehicles were returned by the API.',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _vehicleLoadError ?? 'Add demo data from Admin → Data Management, then retry.',
                style: const TextStyle(color: Colors.white60, fontSize: 10.5, height: 1.35),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _loadingVehicles = true;
                      _vehicleLoadError = null;
                    });
                    _loadRates();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry vehicles'),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return _availableVehicles.map((vehicle) {
      final active = vehicle.id == _selectedVehicleId;
      final type = _normaliseVehicle('${vehicle.category} ${vehicle.make} ${vehicle.model}');
      final rate = _dbRates[type];
      final areas = vehicle.serviceAreas.take(2).join(', ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: active ? const Color(0xFF292C2A) : const Color(0xFF181B19),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: vehicle.isOnline ? () => _selectPublicVehicle(vehicle) : null,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: active ? _lime.withValues(alpha: .75) : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 88,
                    height: 66,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: active ? .07 : .035),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _publicVehicleImage(vehicle),
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
                                '${vehicle.make} ${vehicle.model} ${vehicle.year}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _StatusBadge(
                              label: vehicle.isOnline ? 'Online' : 'Offline',
                              color: vehicle.isOnline
                                  ? const Color(0xFF8ED12B)
                                  : const Color(0xFFF79009),
                            ),
                            if (vehicle.isDemo) ...[
                              const SizedBox(width: 4),
                              const _StatusBadge(label: 'Demo', color: Color(0xFF75B8FF)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${vehicle.driverName} • ★ ${vehicle.driverRating.toStringAsFixed(1)} • ${vehicle.completedTrips} trips',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            _RatePill(label: 'Type', value: vehicle.category),
                            _RatePill(label: 'Seats', value: '${vehicle.passengerCapacity}'),
                            _RatePill(label: '/ km', value: _money(rate?.perKmRate ?? 0)),
                            _RatePill(
                              label: _bookingMode == _FareBookingMode.wholeVehicle ? 'Est. full' : 'Est. seat',
                              value: _money(
                                _bookingMode == _FareBookingMode.wholeVehicle
                                    ? _wholeVehicleEstimate(_choices.firstWhere((c) => _normaliseVehicle(c.name) == type, orElse: () => _choices.first), rate)
                                    : _perSeatEstimate(_choices.firstWhere((c) => _normaliseVehicle(c.name) == type, orElse: () => _choices.first), rate),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${vehicle.registrationNumber}${areas.isEmpty ? '' : ' • $areas'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    active
                        ? Icons.radio_button_checked_rounded
                        : vehicle.isOnline
                            ? Icons.radio_button_off_rounded
                            : Icons.lock_clock_rounded,
                    color: active
                        ? _lime
                        : vehicle.isOnline
                            ? Colors.white30
                            : const Color(0xFFF79009),
                    size: 23,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  double? _typedAmount(TextEditingController controller) {
    final clean = controller.text.replaceAll(',', '').trim();
    return double.tryParse(clean);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final controller = AppControllerScope.of(context);
    final choice = _choices[_selected];
    final package = _matchingPackage(controller, choice);
    final wholeVehicle = _bookingMode == _FareBookingMode.wholeVehicle;
    final enteredRate = _typedAmount(wholeVehicle ? _wholeVehicleOffer : _perSeatOffer);
    final amount = enteredRate == null ? null : (wholeVehicle ? enteredRate : enteredRate * _seats);

    if (package != null && !_packageBookable(package)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This vehicle has already passed the booking cutoff and cannot be booked.')));
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your fare offer before finding a driver.')),
      );
      return;
    }
    if (!controller.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again to submit this booking request.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final pickupAt = package?.departureAt ?? (widget.serviceType == UDriveServiceType.city
          ? DateTime.now()
          : DateTime(_tourDate.year, _tourDate.month, _tourDate.day, 8));
      final capacity = package?.totalSeats ?? choice.capacity;
      final requestedSeats = wholeVehicle ? capacity : _seats.clamp(1, package?.bookableSeats ?? capacity).toInt();
      final request = await controller.createLiveRideRequest({
        'pickupLabel': widget.pickupLabel,
        'destinationLabel': widget.destination.title,
        'pickupLatitude': widget.pickupPoint.latitude,
        'pickupLongitude': widget.pickupPoint.longitude,
        'destinationLatitude': widget.destination.latitude,
        'destinationLongitude': widget.destination.longitude,
        'pickupAt': pickupAt.toUtc().toIso8601String(),
        'bookingType': wholeVehicle ? 'WholeVehicle' : 'PerSeat',
        'seatsRequested': requestedSeats,
        'adults': requestedSeats,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': amount,
        'vehicleCategory': choice.name,
        'partyType': requestedSeats > 1 ? 'Group' : 'Individual',
        'familyOnly': false,
        'womenOnly': false,
        'instantRide': widget.serviceType == UDriveServiceType.city,
        'notes': '${widget.serviceType.title} • ${_routeDistanceKm.toStringAsFixed(1)} km estimated • ${wholeVehicle ? 'whole vehicle' : 'per seat'}${package == null ? ' • customer fare offer' : ' • published tour rate'}${_selectedPublicVehicle == null ? '' : ' • preferred ${_selectedPublicVehicle!.make} ${_selectedPublicVehicle!.model} (${_selectedPublicVehicle!.registrationNumber})'}${_autoAccept ? ' • auto-accept enabled' : ''}',
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverOffersScreen(
            rideRequestId: request.id,
            pickup: request.pickupLabel,
            destination: request.destinationLabel,
            customerOffer: request.customerOffer.round(),
            vehicleName: request.vehicleCategory,
            autoMatch: false,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? 'Booking request could not be submitted.' : message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmCityRide({
    required int choiceIndex,
    required _FareBookingMode mode,
  }) async {
    if (_submitting) return;
    final choice = _choices[choiceIndex];
    final rate = _dbRates[_normaliseVehicle(choice.name)];
    final perSeat = _perSeatEstimate(choice, rate);
    final whole = _wholeVehicleEstimate(choice, rate);
    final vehicle = _availableVehicles.cast<_PublicVehicle?>().firstWhere(
      (v) => v != null && _normaliseVehicle(v.category) == _normaliseVehicle(choice.name) && v.isOnline,
      orElse: () => _availableVehicles.isEmpty ? null : _availableVehicles.first,
    );
    final capacity = (vehicle?.passengerCapacity ?? choice.capacity).clamp(1, 50).toInt();
    int seats = 1;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final amount = mode == _FareBookingMode.wholeVehicle ? whole : perSeat * seats;
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Confirm your ride', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.surface)),
                  const SizedBox(height: 6),
                  Text('${widget.pickupLabel}  →  ${widget.destination.title}', style: const TextStyle(color: AppText.secondary, fontSize: 12, height: 1.35)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF7F8F9), borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Row(children: [
                          Icon(_cityVehicleIcon(choice.name), color: AppColors.surface),
                          const SizedBox(width: 10),
                          Expanded(child: Text(choice.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                          Text(_money(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF365314))),
                        ]),
                        const Divider(height: 24),
                        Row(children: [
                          const Text('Booking', style: TextStyle(color: AppText.secondary, fontSize: 12)),
                          const Spacer(),
                          Text(mode == _FareBookingMode.wholeVehicle ? 'Full vehicle' : '$seats seat${seats == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                        if (mode == _FareBookingMode.perSeat) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            const Text('Seats', style: TextStyle(color: AppText.secondary, fontSize: 12)),
                            const Spacer(),
                            IconButton.filledTonal(
                              onPressed: seats > 1 ? () => setSheetState(() => seats--) : null,
                              icon: const Icon(Icons.remove_rounded, size: 18),
                            ),
                            SizedBox(width: 34, child: Text('$seats', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                            IconButton.filledTonal(
                              onPressed: seats < capacity ? () => setSheetState(() => seats++) : null,
                              icon: const Icon(Icons.add_rounded, size: 18),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 8),
                        const Row(children: [
                          Text('Payment', style: TextStyle(color: AppText.secondary, fontSize: 12)),
                          Spacer(),
                          Icon(Icons.payments_outlined, size: 17, color: Color(0xFF374151)),
                          SizedBox(width: 5),
                          Text('Cash', style: TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: amount <= 0 ? null : () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF84CC16),
                        foregroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Confirm Ride', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _selected = choiceIndex;
      _bookingMode = mode;
      _seats = seats;
      _selectedVehicleId = vehicle?.id;
      _perSeatOffer.text = perSeat.round().toString();
      _wholeVehicleOffer.text = whole.round().toString();
    });
    await _submit();
  }

  Widget _buildCityMinimalResultsScreen(BuildContext context) {
    final choices = _choices;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.surface,
        title: const Text('Choose your ride', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded, size: 20, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.pickupLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF9CA3AF))),
                  const Icon(Icons.location_on_rounded, size: 21, color: Color(0xFFF97316)),
                  const SizedBox(width: 5),
                  Expanded(child: Text(widget.destination.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('${_routeDistanceKm.toStringAsFixed(1)} km estimated route', style: const TextStyle(color: AppText.secondary, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 15),
            ...choices.asMap().entries.map((entry) {
              final index = entry.key;
              final choice = entry.value;
              final rate = _dbRates[_normaliseVehicle(choice.name)];
              final perSeat = _perSeatEstimate(choice, rate);
              final whole = _wholeVehicleEstimate(choice, rate);
              final matching = _availableVehicles.where((v) => _normaliseVehicle(v.category) == _normaliseVehicle(choice.name)).toList();
              final available = matching.where((v) => v.isOnline).length;
              final availability = available > 0 ? '$available available now' : 'Searching nearby drivers';

              return Container(
                margin: const EdgeInsets.only(bottom: 11),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
                child: Column(
                  children: [
                    Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                        child: Icon(_cityVehicleIcon(choice.name), color: AppColors.surface, size: 25),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(choice.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.surface)),
                        const SizedBox(height: 3),
                        Text('${choice.capacity} seat${choice.capacity == 1 ? '' : 's'} • $availability', style: const TextStyle(color: AppText.secondary, fontSize: 11)),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: perSeat <= 0 ? null : () => _confirmCityRide(choiceIndex: index, mode: _FareBookingMode.perSeat),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: Text(perSeat <= 0 ? 'Seat fare loading' : '1 Seat  •  ${_money(perSeat)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: whole <= 0 ? null : () => _confirmCityRide(choiceIndex: index, mode: _FareBookingMode.wholeVehicle),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF84CC16), foregroundColor: AppColors.surface, padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: Text(whole <= 0 ? 'Full fare loading' : 'Full  •  ${_money(whole)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ]),
                  ],
                ),
              );
            }),
            if (_loadingRates || _loadingVehicles)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Refreshing live availability…', style: TextStyle(color: AppText.secondary, fontSize: 11)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeRouteResultsScreen(BuildContext context) {
    // Shared safe results screen for City-to-City, Tours & Trips and Private
    // Vehicle. The first frame uses only local state and basic Material widgets.
    // Live rates/vehicles/packages may enhance it after rendering, but can never
    // make the page blank.
    final choices = _choices;
    final safeIndex = (_selected >= 0 && _selected < choices.length) ? _selected : 0;
    final selected = choices[safeIndex];
    final selectedVehicle = _selectedPublicVehicle;
    final selectedDbRate = _dbRates[_normaliseVehicle(selected.name)];
    final capacity = (selectedVehicle?.passengerCapacity ?? selected.capacity).clamp(1, 50).toInt();
    final routeKm = _routeDistanceKm;
    final defaultPerSeat = _perSeatEstimate(selected, selectedDbRate);
    final defaultWhole = _wholeVehicleEstimate(selected, selectedDbRate);
    final perSeatAmount = _typedAmount(_perSeatOffer) ?? defaultPerSeat;
    final wholeAmount = _typedAmount(_wholeVehicleOffer) ?? defaultWhole;
    final estimatedTotal = _bookingMode == _FareBookingMode.wholeVehicle
        ? wholeAmount
        : perSeatAmount * _seats;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.surface,
        title: Text(
          widget.serviceType.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.my_location_rounded, color: Color(0xFF16A34A), size: 21),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PICKUP', style: TextStyle(color: AppText.secondary, fontSize: 10, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.pickupLabel, style: const TextStyle(color: AppColors.surface, fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 9),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(height: 18, child: VerticalDivider(width: 2, thickness: 2, color: Color(0xFFD1D5DB))),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, color: Color(0xFFF97316), size: 22),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DESTINATION', style: TextStyle(color: AppText.secondary, fontSize: 10, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.destination.title, style: const TextStyle(color: AppColors.surface, fontSize: 14, fontWeight: FontWeight.w900)),
                            if (widget.destination.subtitle.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(widget.destination.subtitle, style: const TextStyle(color: AppText.secondary, fontSize: 11)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _cityInfoBox('Distance', '${routeKm.toStringAsFixed(1)} km')),
                const SizedBox(width: 8),
                Expanded(child: _cityInfoBox('Rate / km', selectedDbRate == null || selectedDbRate.perKmRate <= 0 ? 'Loading' : _money(selectedDbRate.perKmRate))),
                const SizedBox(width: 8),
                Expanded(child: _cityInfoBox('Estimate', estimatedTotal <= 0 ? 'Loading' : _money(estimatedTotal))),
              ],
            ),
            if (widget.serviceType == UDriveServiceType.tours) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    const Icon(Icons.calendar_month_rounded, color: Color(0xFF374151)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Tour date', style: TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.w800))),
                    Text('${_tourDate.day.toString().padLeft(2, '0')}/${_tourDate.month.toString().padLeft(2, '0')}/${_tourDate.year}', style: const TextStyle(color: AppColors.surface, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text('Choose vehicle', style: TextStyle(color: AppColors.surface, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            ...choices.asMap().entries.map((entry) {
              final index = entry.key;
              final choice = entry.value;
              final active = index == safeIndex;
              final rate = _dbRates[_normaliseVehicle(choice.name)];
              final seatEstimate = _perSeatEstimate(choice, rate);
              final wholeEstimate = _wholeVehicleEstimate(choice, rate);
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() {
                      _selected = index;
                      _seats = _seats.clamp(1, choice.capacity.clamp(1, 50)).toInt();
                      _selectedVehicleId = null;
                    });
                    _applySelectedDefaultRates();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: active ? const Color(0xFF84CC16) : AppColors.border, width: active ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                          child: Icon(_cityVehicleIcon(choice.name), color: AppColors.surface),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(choice.name, style: const TextStyle(color: AppColors.surface, fontSize: 14, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text('${choice.meta} • ${choice.note}', style: const TextStyle(color: AppText.secondary, fontSize: 10.5)),
                              const SizedBox(height: 5),
                              Text(
                                'Seat ${seatEstimate <= 0 ? 'rate loading' : _money(seatEstimate)}  •  Full ${wholeEstimate <= 0 ? 'rate loading' : _money(wholeEstimate)}',
                                style: const TextStyle(color: Color(0xFF374151), fontSize: 10.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Icon(active ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: active ? const Color(0xFF65A30D) : const Color(0xFF9CA3AF)),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            // Only offer modes the driver enabled on this vehicle. When just one
            // is allowed we show a short reason instead of a dead toggle.
            if (widget.serviceType != UDriveServiceType.privateVehicle &&
                !_showBookingModeToggle)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 15, color: AppText.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bookingModeNotice ?? '',
                      style: const TextStyle(fontSize: 11.5, color: AppText.secondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            if (widget.serviceType != UDriveServiceType.privateVehicle &&
                _showBookingModeToggle)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => setState(() => _bookingMode = _FareBookingMode.perSeat),
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _bookingMode == _FareBookingMode.perSeat ? Colors.white : Colors.transparent,
                          foregroundColor: AppColors.surface,
                        ),
                        child: const Text('Per seat', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => setState(() => _bookingMode = _FareBookingMode.wholeVehicle),
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _bookingMode == _FareBookingMode.wholeVehicle ? Colors.white : Colors.transparent,
                          foregroundColor: AppColors.surface,
                        ),
                        child: const Text('Whole vehicle', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: const Row(children: [Icon(Icons.directions_car_filled_rounded, color: Color(0xFF65A30D)), SizedBox(width: 9), Text('Complete vehicle booking', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.w900))]),
              ),
            if (_bookingMode == _FareBookingMode.perSeat) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    const Text('Seats', style: TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(onPressed: _seats > 1 ? () => setState(() => _seats--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                    Text('$_seats', style: const TextStyle(color: AppColors.surface, fontSize: 16, fontWeight: FontWeight.w900)),
                    IconButton(onPressed: _seats < capacity ? () => setState(() => _seats++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _bookingMode == _FareBookingMode.perSeat ? _perSeatOffer : _wholeVehicleOffer,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _bookingMode == _FareBookingMode.perSeat ? 'Fare per seat (PKR)' : 'Whole vehicle fare (PKR)',
                prefixIcon: const Icon(Icons.payments_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingRates || _loadingVehicles)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Refreshing live rates and vehicles…', style: TextStyle(color: AppText.secondary, fontSize: 11)),
                  ],
                ),
              ),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF84CC16),
                  foregroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                    : const Icon(Icons.local_taxi_rounded),
                label: Text(_submitting ? 'Creating booking…' : 'Book selected ride', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cityInfoBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppText.secondary, fontSize: 9.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.surface, fontSize: 11, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  IconData _cityVehicleIcon(String name) {
    final type = _normaliseVehicle(name);
    if (type == 'bike') return Icons.two_wheeler_rounded;
    if (type == 'rickshaw') return Icons.electric_rickshaw_rounded;
    if (type == 'coster') return Icons.directions_bus_rounded;
    return Icons.directions_car_filled_rounded;
  }

  Widget _buildRouteRenderRecovery(BuildContext context, Object error) {
    return Scaffold(
      backgroundColor: const Color(0xFF111312),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111312),
        foregroundColor: Colors.white,
        title: Text(widget.serviceType.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.directions_car_filled_rounded, color: _lime, size: 42),
              const SizedBox(height: 14),
              const Text('This booking screen could not finish rendering.', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('${widget.pickupLabel} → ${widget.destination.title}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selected = 0;
                      _loadingVehicles = true;
                      _vehicleLoadError = null;
                    });
                    _loadRates();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reload rides'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _money(double value) => value <= 0 ? 'Not set' : 'PKR ${value.round()}';

  @override
  Widget build(BuildContext context) {
    // All route blocks use the same guarded first-frame renderer. This removes
    // the old Tours/Private black renderer as a blank-screen failure point.
    try {
      if (widget.serviceType == UDriveServiceType.city) {
        return _buildCityMinimalResultsScreen(context);
      }
      return _buildSafeRouteResultsScreen(context);
    } catch (error) {
      return _buildRouteRenderRecovery(context, error);
    }

    final app = AppControllerScope.of(context);
    final tourPackages = _matchingPackages(app);
    final selected = _choices[_selected];
    final selectedVehicle = _selectedPublicVehicle;
    final selectedPackage = _matchingPackage(app, selected);
    final effectiveCapacity = selectedPackage?.totalSeats ??
        selectedVehicle?.passengerCapacity ??
        selected.capacity;
    final selectedPackageBookable = selectedPackage == null || _packageBookable(selectedPackage);
    final selectedDbRate = _dbRates[_normaliseVehicle(selected.name)];
    final perSeatAmount = _typedAmount(_perSeatOffer) ?? selectedPackage?.pricePerSeat ?? _perSeatEstimate(selected, selectedDbRate);
    final wholeAmount = _typedAmount(_wholeVehicleOffer) ?? selectedPackage?.wholeVehiclePrice ?? _wholeVehicleEstimate(selected, selectedDbRate);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E0D),
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF111312))),
          Positioned.fill(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 76, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202321),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location_rounded, color: _lime, size: 20),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${widget.pickupLabel}  →  ${widget.destination.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _RatePill(label: 'Distance', value: '${_routeDistanceKm.toStringAsFixed(1)} km'),
                      if (selectedDbRate != null) _RatePill(label: 'Rate', value: '${_money(selectedDbRate.perKmRate)} / km'),
                      _RatePill(
                        label: 'Estimated fare',
                        value: _money(_bookingMode == _FareBookingMode.wholeVehicle ? wholeAmount : perSeatAmount * _seats),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.serviceType.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(widget.serviceType == UDriveServiceType.tours ? 'Published tour rates are shown when available' : 'Choose a ride, review the fare and book', style: const TextStyle(color: _muted, fontSize: 10.5)),
                      ])),
                      if (widget.serviceType == UDriveServiceType.tours)
                        TextButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded, size: 17), label: Text('${_tourDate.day}/${_tourDate.month}', style: const TextStyle(fontSize: 11))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_showBookingModeToggle)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Expanded(child: _ModeButton(label: 'Per seat', selected: _bookingMode == _FareBookingMode.perSeat, onTap: () => setState(() => _bookingMode = _FareBookingMode.perSeat))),
                        Expanded(child: _ModeButton(label: 'Whole vehicle', selected: _bookingMode == _FareBookingMode.wholeVehicle, onTap: () => setState(() => _bookingMode = _FareBookingMode.wholeVehicle))),
                      ]),
                    )
                  else
                    Text(
                      _bookingModeNotice ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  if (_bookingMode == _FareBookingMode.perSeat) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Seats', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      _RoundMiniButton(icon: Icons.remove, onTap: _seats > 1 ? () => setState(() => _seats--) : null),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 13), child: Text('$_seats', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
                      _RoundMiniButton(icon: Icons.add, onTap: _seats < effectiveCapacity ? () => setState(() => _seats++) : null),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  if (widget.serviceType == UDriveServiceType.tours && tourPackages.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF222522), borderRadius: BorderRadius.circular(18)),
                      child: const Row(children: [
                        Icon(Icons.directions_bus_filled_rounded, color: _lime),
                        SizedBox(width: 10),
                        Expanded(child: Text('No fixed tour package is scheduled for this destination in the next 30 days. Choose an approved tour-capable vehicle below and submit your offer.', style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35))),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    ..._publicVehicleCards(),
                  ] else if (widget.serviceType == UDriveServiceType.tours)
                    ...tourPackages.map((package) {
                      final active = package.id == (_selectedPackageId ?? tourPackages.first.id);
                      final bookable = _packageBookable(package);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: active ? const Color(0xFF292D2A) : const Color(0xFF181B19),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: bookable ? () {
                              setState(() {
                                _selectedPackageId = package.id;
                                final vehicleIndex = _choices.indexWhere((choice) => _normaliseVehicle(choice.name) == _normaliseVehicle(package.vehicle));
                                if (vehicleIndex >= 0) _selected = vehicleIndex;
                                _seats = _seats.clamp(1, package.bookableSeats.clamp(1, package.totalSeats)).toInt();
                              });
                              _applySelectedDefaultRates();
                            } : null,
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: active ? _lime.withValues(alpha: .75) : Colors.white10),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 84,
                                  height: 62,
                                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(14)),
                                  child: Image.asset(_packageImage(package), fit: BoxFit.contain, filterQuality: FilterQuality.high),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text('${package.vehicle} • ${package.driverName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900))),
                                    if (!bookable) const _StatusBadge(label: 'Closed', color: Color(0xFFE5484D)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(_packageTiming(package), style: TextStyle(color: bookable ? _lime : Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 5),
                                  Wrap(spacing: 5, runSpacing: 4, children: [
                                    _RatePill(label: 'Seats left', value: '${package.bookableSeats}'),
                                    _RatePill(label: 'Seat', value: _money(package.pricePerSeat)),
                                    _RatePill(label: 'Full', value: _money(package.wholeVehiclePrice)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text('${package.pickupPoint} • ${package.registrationNumber}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 9.5)),
                                ])),
                                const SizedBox(width: 5),
                                Icon(active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: active ? _lime : Colors.white30),
                              ]),
                            ),
                          ),
                        ),
                      );
                    })
                  else
                    ..._publicVehicleCards(),
                  const SizedBox(height: 3),
                  if (selectedPackage == null)
                    TextField(
                      controller: _bookingMode == _FareBookingMode.perSeat ? _perSeatOffer : _wholeVehicleOffer,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        labelText: _bookingMode == _FareBookingMode.perSeat ? 'Your offer per seat (PKR)' : 'Your whole vehicle offer (PKR)',
                        labelStyle: const TextStyle(color: _muted, fontSize: 11),
                        prefixIcon: const Icon(Icons.payments_outlined, color: _lime, size: 20),
                        filled: true,
                        fillColor: const Color(0xFF242725),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF242725), borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        const Icon(Icons.verified_rounded, color: _lime, size: 20),
                        const SizedBox(width: 9),
                        Expanded(child: Text('Published by ${selectedPackage.driverName} • ${selectedPackage.availableSeats} seats available', style: const TextStyle(color: Colors.white70, fontSize: 10.5))),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF202321), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        selectedPackage == null
                            ? 'Fare is calculated from the database per-km rate and estimated route distance. You can keep this fare or adjust your offer before booking.'
                            : 'Per-seat and whole-vehicle prices come directly from the selected tour package.',
                        style: const TextStyle(color: Colors.white60, fontSize: 10.5, height: 1.35),
                      )),
                    ]),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    value: _autoAccept,
                    activeThumbColor: _lime,
                    onChanged: (value) => setState(() => _autoAccept = value),
                    secondary: const Icon(Icons.send_rounded, color: Colors.white70, size: 19),
                    title: Text('Auto-accept offers up to ${_money(_bookingMode == _FareBookingMode.perSeat ? (selectedPackage == null ? perSeatAmount : perSeatAmount * _seats) : wholeAmount)}', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _submitting ||
                              (widget.serviceType == UDriveServiceType.tours &&
                                  selectedPackage != null &&
                                  !selectedPackageBookable)
                          ? null
                          : _submit,
                      style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
                          : Text(widget.serviceType == UDriveServiceType.tours ? 'Find tour vehicle' : 'Book selected ride', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(backgroundColor: const Color(0x84121413)),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  IconButton.filled(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    style: IconButton.styleFrom(backgroundColor: const Color(0x84121413)),
                    icon: const Icon(Icons.home_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: selected ? _lime : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w900)),
        ),
      );
}

class _RoundMiniButton extends StatelessWidget {
  const _RoundMiniButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(width: 30, height: 30, decoration: BoxDecoration(color: Colors.white.withValues(alpha: onTap == null ? .03 : .08), shape: BoxShape.circle), child: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white, size: 17)),
      );
}

class _RatePill extends StatelessWidget {
  const _RatePill({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
        child: Text('$label: $value', style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w700)),
      );
}

class _RouteField extends StatelessWidget {
  const _RouteField({required this.label, required this.value, required this.icon, this.readOnly = false});
  final String label;
  final String value;
  final IconData icon;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 29),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
          ])),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(color: selected ? Colors.white : _tile, borderRadius: BorderRadius.circular(24)),
        child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w800)),
      );
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.pickup, required this.destination});
  final String pickup;
  final String destination;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xEB181A18), borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)]),
        child: Column(children: [
          Row(children: [const Icon(Icons.circle, size: 12, color: _lime), const SizedBox(width: 10), Expanded(child: Text(pickup, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))]),
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.flag_rounded, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(destination, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))]),
        ]),
      );
}


class _DbRate {
  const _DbRate(this.perSeatRate, this.wholeVehicleRate, this.perKmRate);
  final double perSeatRate;
  final double wholeVehicleRate;
  final double perKmRate;
}
class _PlaceResult {
  const _PlaceResult(this.title, this.subtitle, this.latitude, this.longitude);
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
}

class _PublicVehicle {
  const _PublicVehicle({
    required this.id,
    required this.driverProfileId,
    required this.driverName,
    required this.driverRating,
    required this.completedTrips,
    required this.safetyScore,
    required this.isOnline,
    required this.category,
    required this.make,
    required this.model,
    required this.year,
    required this.registrationNumber,
    required this.colour,
    required this.passengerCapacity,
    required this.luggageCapacity,
    required this.hasAirConditioning,
    required this.hasHeating,
    required this.isFourByFour,
    required this.mountainReadinessScore,
    required this.imageUrl,
    required this.serviceAreas,
    required this.isDemo,
    this.bookingMode = VehicleBookingMode.wholeVehicle,
  });

  factory _PublicVehicle.fromJson(Map<String, dynamic> json) {
    final rawAreas = json['serviceAreas'];
    final areas = rawAreas is List
        ? rawAreas
            .map((item) => '$item'.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return _PublicVehicle(
      id: '${json['id'] ?? ''}',
      driverProfileId: '${json['driverProfileId'] ?? ''}',
      driverName: '${json['driverName'] ?? 'Verified driver'}'.trim(),
      driverRating: (json['driverRating'] as num?)?.toDouble() ?? 0,
      completedTrips: (json['completedTrips'] as num?)?.toInt() ?? 0,
      safetyScore: (json['safetyScore'] as num?)?.toInt() ?? 0,
      isOnline: json['isOnline'] == true,
      category: '${json['category'] ?? 'Car'}'.trim(),
      make: '${json['make'] ?? ''}'.trim(),
      model: '${json['model'] ?? ''}'.trim(),
      year: (json['year'] as num?)?.toInt() ?? 0,
      registrationNumber: '${json['registrationNumber'] ?? ''}'.trim(),
      colour: '${json['colour'] ?? ''}'.trim(),
      passengerCapacity: (json['passengerCapacity'] as num?)?.toInt() ?? 1,
      luggageCapacity: (json['luggageCapacity'] as num?)?.toInt() ?? 0,
      hasAirConditioning: json['hasAirConditioning'] == true,
      hasHeating: json['hasHeating'] == true,
      isFourByFour: json['isFourByFour'] == true,
      mountainReadinessScore:
          (json['mountainReadinessScore'] as num?)?.toInt() ?? 0,
      imageUrl: ApiConfig.absoluteUrl(json['imageUrl']?.toString()),
      serviceAreas: areas,
      isDemo: json['isDemo'] == true,
      bookingMode:
          VehicleBookingModeInfo.fromApi(json['bookingMode']?.toString()),
    );
  }

  final String id;
  final String driverProfileId;
  final String driverName;
  final double driverRating;
  final int completedTrips;
  final int safetyScore;
  final bool isOnline;
  final String category;
  final String make;
  final String model;
  final int year;
  final String registrationNumber;
  final String colour;
  final int passengerCapacity;
  final int luggageCapacity;
  final bool hasAirConditioning;
  final bool hasHeating;
  final bool isFourByFour;
  final int mountainReadinessScore;
  final String imageUrl;
  final List<String> serviceAreas;
  final bool isDemo;

  /// How the driver allows this vehicle to be booked. Drives which fare modes
  /// the customer is offered.
  final VehicleBookingMode bookingMode;
}

class _VehicleChoiceData {
  const _VehicleChoiceData(this.name, this.meta, this.note, this.capacity, this.imageAsset);
  final String name;
  final String meta;
  final String note;
  final int capacity;
  final String imageAsset;
}

class _RouteModeChoice extends StatelessWidget {
  const _RouteModeChoice({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _lime : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
}
