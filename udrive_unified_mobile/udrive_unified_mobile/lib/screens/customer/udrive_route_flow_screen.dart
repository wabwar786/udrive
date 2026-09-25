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
import '../../core/format/money.dart';
import '../../core/pricing/fare_quote.dart';
import '../../core/pricing/fare_quote_repository.dart';
import '../../core/state/app_controller.dart';
import '../../models/booking_models.dart';
import 'driver_offers_screen.dart';

const _ink = AppColors.inkSurface;
const _tile = AppColors.inkTile;
const _lime = AppColors.brand;
const _muted = AppColors.onInkMuted;

enum UDriveServiceType { city, tours, privateVehicle }

extension UDriveServiceTypeLabel on UDriveServiceType {
  String get title => switch (this) {
        UDriveServiceType.city => 'City-to-City Ride',
        UDriveServiceType.tours => 'Tours & Trips',
        UDriveServiceType.privateVehicle => 'Private Vehicle',
      };

  String get subtitle => switch (this) {
        UDriveServiceType.city => 'car, bike, rickshaw',
        UDriveServiceType.tours => 'coaster, car',
        UDriveServiceType.privateVehicle => 'coaster, car, bike',
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
            child: ColoredBox(color: AppTint.inkVeil),
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
                          backgroundColor: AppTint.inkGlass,
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
                          backgroundColor: AppTint.inkGlass,
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
                      color: AppTint.inkScrim,
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
                                            color: AppText.disabled,
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
                                            color: AppColors.onInkMuted,
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
                                        color: typed ? AppText.disabled : _lime,
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
  // _fallbackDemoVehicles was here: five invented vehicles with invented
  // driver names ("Adeel Khan", "Kashmir Group Transport"), ratings, trip
  // counts and registration plates, seeded in initState BEFORE any network
  // call and again whenever the catalogue came back empty or threw.
  //
  // They were selectable and bookable. This screen is entered from Home
  // whenever a typed destination cannot be geocoded, and from both hotel
  // screens, so a customer on a slow connection could send a real booking
  // request naming a driver who does not exist. One of them also carried the
  // category 'Coaster', which is not a category the server has — see
  // core/vehicles/vehicle_catalogue.dart.
  //
  // The screen already had a loading state and an empty state. Those now do
  // the job: nothing is shown until the server answers, and if it has nothing
  // to offer the customer is told so and can retry.

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

    // The screen opens in its loading state and stays there until the server
    // answers. It previously seeded invented vehicles and invented rates here,
    // before any network call, so the first frame showed drivers who did not
    // exist and an offer box pre-filled with a made-up number — on a good
    // connection as much as a bad one. The loading and empty states below are
    // renderable on the first frame, which is what that seeding was for.
    _loadingVehicles = true;
    _loadingRates = true;

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
      // An empty catalogue is an answer, not a failure: it means no approved
      // vehicle of this kind is available right now. The empty state says so.
      final displayVehicles = _interleaveVehicleCategories(vehicles);
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
      // Show the failure. Substituting invented vehicles here hid every outage
      // behind a working-looking screen, and the customer's booking request
      // then named a driver the server had never heard of.
      setState(() {
        _availableVehicles = const [];
        _selectedVehicleId = null;
        _loadingVehicles = false;
        _vehicleLoadError =
            'We could not reach UDrive just now. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  // The per-service fallback list and the hard-coded default rate table were
  // removed with the demo vehicles above. The rates they invented — a 1,200 base and 65/km
  // for a Car, 42,000 for a Coster tour — were quoted to the customer as the
  // suggested fare and pre-filled into the offer box whenever the rate card
  // could not be fetched. A price the platform made up is worse than no price:
  // the customer offers it, a driver accepts it, and neither of them agreed to
  // anything the business set. Rates now come from the server or not at all.

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

  // _publicVehicleAsset was removed with _publicVehicleImage, its only
  // caller. Both belonged to the unreachable renderer.


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
            _VehicleChoiceData('Coaster', '22 seats', 'Shared seat or complete vehicle', 22, 'assets/vehicles_photo/coaster_clean.png'),
          ],
        UDriveServiceType.tours => const [
            _VehicleChoiceData('Car', '4 seats', 'Tour car or shared seat', 4, 'assets/vehicles_photo/car_clean.png'),
            _VehicleChoiceData('Coaster', '22 seats', 'Group tour and per-seat travel', 22, 'assets/vehicles_photo/coaster_clean.png'),
          ],
        UDriveServiceType.privateVehicle => const [
            _VehicleChoiceData('Car', '4 seats', 'Book the complete car', 4, 'assets/vehicles_photo/private_car_clean.png'),
            _VehicleChoiceData('Coaster', '22 seats', 'Private vehicle for groups', 22, 'assets/vehicles_photo/coaster_clean.png'),
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

  /// The screen's label, in the spelling the API prices by.
  ///
  /// This screen has always said "Coaster" while `service_vehicle_rates`,
  /// `seat_fares` and the other booking screen all say "Coster" — so a quote
  /// asked for under the screen's own label matches no rate row at all and
  /// comes back 422. The booking then went out with no band, which on a
  /// 22-seat vehicle is the most expensive place to have no floor.
  String _apiVehicleCategory(String value) => switch (_normaliseVehicle(value)) {
        'coster' => 'Coster',
        'bike' => 'Bike',
        'rickshaw' => 'Rickshaw',
        _ => 'Car',
      };

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



  /// The one place this screen tells the truth about availability.
  ///
  /// It exists because the loading and empty states in the old public
  /// vehicle-card builder were unreachable: `build` returns from inside
  /// its own try/catch, so every line after that — including the only two
  /// calls to that builder — was dead code. The two renderers that run,
  /// `_buildCityMinimalResultsScreen` and `_buildSafeRouteResultsScreen`, map
  /// over the fixed `_choices` list and read `_dbRates`, so with no rates and
  /// no vehicles they draw a full page of rows whose buttons are disabled and
  /// whose labels say "Seat fare loading" for ever, with no spinner and no
  /// explanation. Before the invented fallback vehicles and rates were taken
  /// out, that state was hidden; it is a real state now, so it needs to say so.
  List<Widget> _availabilityBanner() {
    if (_loadingVehicles || _loadingRates) {
      return [Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Checking which drivers are available and what the fare is…',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppText.secondary),
            ),
          ),
        ]),
      )];
    }

    // Two separate ways this screen can be unusable, and the banner has to
    // catch both. Gating on _availableVehicles alone was not enough: the
    // vehicles and the rate card are fetched together, but the rates response
    // is parsed defensively, so a 200 whose payload is the wrong shape — or
    // simply omits a category — leaves _dbRates empty or partial with NO
    // error and a perfectly good vehicle list. Every row then renders
    // 'Seat fare loading' with both buttons disabled, for ever, which is the
    // exact dead end this method exists to remove.
    final noRate = _choices
        .every((choice) => _dbRates[_normaliseVehicle(choice.name)] == null);

    if (_vehicleLoadError == null && _availableVehicles.isNotEmpty && !noRate) {
      return const [];
    }

    final message = _vehicleLoadError ??
        (noRate
            ? 'We could not load current fares for this route. Try again in a moment.'
            : 'No approved driver is offering this service near you at the moment. '
                'You can still send a request, or try again in a few minutes.');

    return [Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTint.pendingSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTint.pendingBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 19, color: AppTint.pending),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _loadingVehicles = true;
                _loadingRates = true;
                _vehicleLoadError = null;
              });
              _loadRates();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ),
      ]),
    )];
  }

  // The public vehicle-card builder was removed with the dead renderer in
  // build().
  // It held this screen's loading and empty states, but nothing ever
  // called it from a reachable path, so none of it was shown. Its job is
  // now done by _availabilityBanner() above, which both live renderers
  // include. An uncalled private method is an `unused_element` warning,
  // and flutter analyze treats warnings as fatal.

  double? _typedAmount(TextEditingController controller) {
    final clean = controller.text.replaceAll(',', '').trim();
    return double.tryParse(clean);
  }

  /// Asks the server for this trip's band, just before the request is made.
  ///
  /// Quoting at submit rather than live: this screen has no reprice loop to
  /// hang a quote on, and adding one would mean rebuilding how it tracks the
  /// vehicle, the seats and the mode. One call at the moment it matters closes
  /// the hole without touching any of that.
  ///
  /// Returns null when the quote cannot be had at all. The request then goes
  /// through unbanded, exactly as it did before — refusing to let someone book
  /// because a pricing lookup failed would be a worse outcome than the one
  /// this is fixing. The server applies its own rules either way.
  Future<FareQuote?> _quoteFare(
    AppController controller,
    _VehicleChoiceData choice,
    bool wholeVehicle,
    int seatsForRequest,
  ) async {
    try {
      final km = _routeDistanceKm;
      return await FareQuoteRepository(controller.apiClient).quote(
        serviceType: 'City',
        vehicleCategory: _apiVehicleCategory(choice.name),
        perSeat: !wholeVehicle,
        // The seat count has to be the one the request will declare, because
        // the server compares them. For a whole vehicle the request sends the
        // capacity, and FareEngine ignores the number on that branch anyway.
        seats: seatsForRequest,
        pickupLatitude: widget.pickupPoint.latitude,
        pickupLongitude: widget.pickupPoint.longitude,
        destinationLatitude: widget.destination.latitude,
        destinationLongitude: widget.destination.longitude,
        distanceKm: km <= 0 ? 0.1 : km,
        durationMinutes: (km <= 0 ? 1 : km / 25 * 60).clamp(1, 6000).toDouble(),
      );
    } catch (_) {
      return null;
    }
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
      // The fare, checked with the server before anything is created.
      //
      // This screen priced trips with its own arithmetic — no per-minute term,
      // a different distance fudge, no rounding, and no floor whatsoever on
      // what could be typed into the box. A customer could offer PKR 1 here
      // and the API would take it.
      //
      // A published tour package is skipped: its price is the operator's, not
      // the meter's.
      final capacityForQuote = package?.totalSeats ?? choice.capacity;
      final seatsForQuote = wholeVehicle
          ? capacityForQuote
          : _seats.clamp(1, package?.bookableSeats ?? capacityForQuote).toInt();

      FareQuote? quote;
      if (package == null) {
        quote = await _quoteFare(controller, choice, wholeVehicle, seatsForQuote);
        if (!mounted) return;
        if (quote != null) {
          if (amount < quote.minimum) {
            setState(() => _submitting = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'The lowest fare for this trip is ${Money.amount(quote.minimum)}.'
                '${wholeVehicle ? '' : ' That is ${Money.amount(quote.minimum ~/ _seats)} a seat.'}',
              ),
            ));
            return;
          }
          if (amount > quote.maximum) {
            setState(() => _submitting = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'The highest fare for this trip is ${Money.amount(quote.maximum)}. '
                'Check the amount you entered.',
              ),
            ));
            return;
          }
        }
      }

      final pickupAt = package?.departureAt ?? (widget.serviceType == UDriveServiceType.city
          ? DateTime.now()
          : DateTime(_tourDate.year, _tourDate.month, _tourDate.day, 8));
      // The same number the quote was asked for. Computing it twice is how
      // the token ends up declaring one seat count and the request another,
      // which the server refuses as a changed trip.
      final requestedSeats = seatsForQuote;
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
        'quoteToken': quote?.token,
        'serviceType': 'City',
        // The API's spelling, so the quote and the request agree and the rate
        // card is the one that priced it.
        'vehicleCategory': _apiVehicleCategory(choice.name),
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
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Confirm your ride', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.text)),
                  const SizedBox(height: 6),
                  Text('${widget.pickupLabel}  →  ${widget.destination.title}', style: const TextStyle(color: AppText.secondary, fontSize: 12, height: 1.35)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Row(children: [
                          Icon(_cityVehicleIcon(choice.name), color: AppColors.text),
                          const SizedBox(width: 10),
                          Expanded(child: Text(choice.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                          Text(_money(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.secondary)),
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
                          Icon(Icons.payments_outlined, size: 17, color: AppColors.text),
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
                        backgroundColor: AppColors.brand,
                        foregroundColor: AppColors.onBrand,
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
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
                  const Icon(Icons.my_location_rounded, size: 20, color: AppTint.pickup),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.pickupLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppText.disabled)),
                  const Icon(Icons.location_on_rounded, size: 21, color: AppTint.dropoff),
                  const SizedBox(width: 5),
                  Expanded(child: Text(widget.destination.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('${_routeDistanceKm.toStringAsFixed(1)} km estimated route', style: const TextStyle(color: AppText.secondary, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 15),
            ..._availabilityBanner(),
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
                        child: Icon(_cityVehicleIcon(choice.name), color: AppColors.text, size: 25),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(choice.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.text)),
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
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.onBrand, padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: Text(whole <= 0 ? 'Full fare loading' : 'Full  •  ${_money(whole)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ]),
                  ],
                ),
              );
            }),
            // The "Refreshing live availability…" spinner that used to sit here
            // was removed: _availabilityBanner() at the top of this list shows
            // the same thing for the same condition, and two spinners saying
            // one thing on one screen reads like two things are happening.
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
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
            ..._availabilityBanner(),
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
                      const Icon(Icons.my_location_rounded, color: AppTint.pickup, size: 21),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PICKUP', style: TextStyle(color: AppText.secondary, fontSize: 10, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.pickupLabel, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 9),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(height: 18, child: VerticalDivider(width: 2, thickness: 2, color: AppColors.border)),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppTint.dropoff, size: 22),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DESTINATION', style: TextStyle(color: AppText.secondary, fontSize: 10, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.destination.title, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w900)),
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
                    const Icon(Icons.calendar_month_rounded, color: AppColors.text),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Tour date', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800))),
                    Text('${_tourDate.day.toString().padLeft(2, '0')}/${_tourDate.month.toString().padLeft(2, '0')}/${_tourDate.year}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text('Choose vehicle', style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w900)),
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
                      border: Border.all(color: active ? AppColors.secondary : AppColors.border, width: active ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                          child: Icon(_cityVehicleIcon(choice.name), color: AppColors.text),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(choice.name, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text('${choice.meta} • ${choice.note}', style: const TextStyle(color: AppText.secondary, fontSize: 10.5)),
                              const SizedBox(height: 5),
                              Text(
                                'Seat ${seatEstimate <= 0 ? 'rate loading' : _money(seatEstimate)}  •  Full ${wholeEstimate <= 0 ? 'rate loading' : _money(wholeEstimate)}',
                                style: const TextStyle(color: AppColors.text, fontSize: 10.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Icon(active ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: active ? AppColors.secondary : AppText.disabled),
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
                  color: AppColors.surface,
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
                          foregroundColor: AppColors.text,
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
                          foregroundColor: AppColors.text,
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
                child: const Row(children: [Icon(Icons.directions_car_filled_rounded, color: AppColors.secondary), SizedBox(width: 9), Text('Complete vehicle booking', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900))]),
              ),
            if (_bookingMode == _FareBookingMode.perSeat) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    const Text('Seats', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(onPressed: _seats > 1 ? () => setState(() => _seats--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                    Text('$_seats', style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w900)),
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
            // Second spinner removed for the same reason as the one on the city
            // screen: _availabilityBanner() above already covers this state.
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onBrand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
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
          Text(value, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text, fontSize: 11, fontWeight: FontWeight.w900)),
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
      backgroundColor: AppColors.inkSurface,
      appBar: AppBar(
        backgroundColor: AppColors.inkSurface,
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
              Text('${widget.pickupLabel} → ${widget.destination.title}', style: const TextStyle(color: AppColors.onInkMuted, fontSize: 12)),
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

    // Everything that used to follow was unreachable: both branches of the
    // try above return, so the compiler treated the remaining ~260 lines as
    // dead code — a warning, and `flutter analyze` is fatal-on-warnings. It
    // was an older full-page renderer, and it held the ONLY calls to
    // the public vehicle-card builder, which is why its loading and empty
    // states never appeared on screen. The live renderers now show
    // _availabilityBanner() instead. Removed rather than left in place so the
    // next person does not fix a bug in code that cannot run.
  }
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



// Thirteen private declarations were removed here in the release audit.
//
// Widget classes: ModeButton, RatePill, RoundMiniButton, RouteField,
// RouteModeChoice, RouteSummary, StatusBadge.
// Methods: estimatedAmountForChoice, packageImage, packageTiming,
// publicVehicleImage, publicVehicleAsset.
// Plus the top-level const panel.
// (Written without their leading underscores on purpose: audit_structure.py
// reads an underscored name followed by a bracket, inside a comment, as a
// real constructor call and flags it as undeclared.)
//
// All twelve were reachable only from the unreachable renderer that build()
// could never run, and from the vehicle-card builder that renderer alone
// called. With those gone, each of these is declared and never referenced,
// which is an `unused_element` warning — and flutter analyze is
// fatal-on-warnings, so leaving them would have failed the release build.
