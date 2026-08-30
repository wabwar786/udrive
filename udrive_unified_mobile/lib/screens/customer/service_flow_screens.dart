import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/state/app_controller.dart';
import '../../models/booking_models.dart';
import 'driver_offers_screen.dart';

// ── Shared palette (matches the ride/booking flow) ──────────────────────────
const _ink = Color(0xFF0C0E0D);
const _sheet = Color(0xFF111312);
const _card = Color(0xFF171A18);
const _tile = Color(0xFF232724);
const _lime = Color(0xFFB7F20A);
const _muted = Color(0xFF9AA09A);

const _mapFilter = ColorFilter.matrix([
  .34, 0, 0, 0, 0,
  0, .40, 0, 0, 0,
  0, 0, .54, 0, 0,
  0, 0, 0, 1, 0,
]);

class _Place {
  const _Place(this.title, this.subtitle, this.lat, this.lng);
  final String title, subtitle;
  final double lat, lng;
  String get label => subtitle.isEmpty ? title : '$title, $subtitle';
}

/// Nominatim search shared by the flow screens.
Future<List<_Place>> _searchPlaces(String query) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query, 'format': 'jsonv2', 'addressdetails': '1', 'limit': '8', 'countrycodes': 'pk',
    });
    final response = await http
        .get(uri, headers: const {'User-Agent': 'UDrive-Mobile/1.0', 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) return const [];
    final raw = jsonDecode(response.body);
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) {
      final map = Map<String, dynamic>.from(entry);
      final display = '${map['display_name'] ?? ''}'.trim();
      final parts = display.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return _Place(
        parts.isEmpty ? query : parts.first,
        parts.skip(1).take(4).join(', '),
        double.tryParse('${map['lat']}') ?? 0,
        double.tryParse('${map['lon']}') ?? 0,
      );
    }).where((p) => p.lat != 0 && p.lng != 0).toList();
  } catch (_) {
    return const [];
  }
}

class _VehicleType {
  const _VehicleType(this.name, this.capacity, this.note, this.asset);
  final String name;
  final int capacity;
  final String note;
  final String asset;
}

const _cityVehicles = <_VehicleType>[
  _VehicleType('Bike', 1, 'Fast city travel', 'assets/vehicles_photo/bike_clean.png'),
  _VehicleType('Car', 4, 'Comfortable city ride', 'assets/vehicles_photo/car_clean.png'),
  _VehicleType('Rickshaw', 3, 'Economical local ride', 'assets/vehicles_photo/rickshaw_clean.png'),
  _VehicleType('Coaster', 22, 'Shared seat or full vehicle', 'assets/vehicles_photo/coaster_clean.png'),
];

const _privateVehicles = <_VehicleType>[
  _VehicleType('Car', 4, 'Sedan • city & highway', 'assets/vehicles_photo/car_clean.png'),
  _VehicleType('SUV', 6, 'Higher clearance for hills', 'assets/vehicles_photo/private_car_clean.png'),
  _VehicleType('Coaster', 22, 'Group & family travel', 'assets/vehicles_photo/coaster_clean.png'),
  _VehicleType('Bike', 1, 'Solo private ride', 'assets/vehicles_photo/bike_clean.png'),
];

String _normalise(String value) {
  final v = value.toLowerCase();
  if (v.contains('coster') || v.contains('coaster') || v.contains('bus') || v.contains('van')) return 'coster';
  if (v.contains('suv') || v.contains('jeep')) return 'suv';
  if (v.contains('bike') || v.contains('motor')) return 'bike';
  if (v.contains('rickshaw')) return 'rickshaw';
  return 'car';
}

// Small shared widgets ───────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
            IconButton.filled(
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(backgroundColor: const Color(0xF0121413)),
              icon: const Icon(Icons.arrow_back_rounded, size: 20, color: Colors.white),
            ),
            const Spacer(),
            IconButton.filled(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              style: IconButton.styleFrom(backgroundColor: const Color(0xF0121413)),
              icon: const Icon(Icons.home_rounded, size: 20, color: Colors.white),
            ),
          ]),
        ),
      );
}

class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 42,
          height: 4,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 1) TRAVEL WITHIN CITY — map + From/Destination on top, vehicles below
// ═════════════════════════════════════════════════════════════════════════════
class CityRideScreen extends StatefulWidget {
  const CityRideScreen({required this.pickupLabel, required this.pickupPoint, super.key});
  final String pickupLabel;
  final LatLng pickupPoint;
  @override
  State<CityRideScreen> createState() => _CityRideScreenState();
}

class _CityRideScreenState extends State<CityRideScreen> {
  late final TextEditingController _from = TextEditingController(text: widget.pickupLabel);
  final _to = TextEditingController();
  final _offer = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;

  late LatLng _pickup = widget.pickupPoint;
  late String _pickupLabel = widget.pickupLabel;
  _Place? _destination;
  List<_Place> _results = const [];
  bool _searching = false;

  bool _wholeVehicle = false;
  int _seats = 1;
  int _selected = 1; // default to Car
  bool _submitting = false;
  final Map<String, List<double>> _rates = {}; // key -> [perSeat, whole]

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRates());
  }

  Future<void> _loadRates() async {
    try {
      final controller = AppControllerScope.of(context);
      final response =
          await controller.apiClient.getJson('/api/v1/catalog/service-rates?serviceType=City', authenticated: false);
      final raw = response['data'];
      if (raw is List) {
        for (final item in raw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          _rates[_normalise('${map['vehicleCategory'] ?? ''}')] = [
            (map['perSeatRate'] as num?)?.toDouble() ?? 0,
            (map['wholeVehicleRate'] as num?)?.toDouble() ?? 0,
          ];
        }
      }
    } catch (_) {
      // Rates stay editable if the pricing endpoint is unavailable.
    }
    if (mounted) setState(() {});
  }

  void _onDestinationChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _searching = false;
        _results = const [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final r = await _searchPlaces(q);
      if (mounted) {
        setState(() {
          _results = r;
          _searching = false;
        });
      }
    });
  }

  void _pickDestination(_Place place) {
    FocusScope.of(context).unfocus();
    setState(() {
      _destination = place;
      _to.text = place.label;
      _results = const [];
    });
    _applyOffer();
    final mid = LatLng((_pickup.latitude + place.lat) / 2, (_pickup.longitude + place.lng) / 2);
    _mapController.move(mid, 11.4);
  }

  double _rateFor(int index, {required bool whole}) {
    final r = _rates[_normalise(_cityVehicles[index].name)];
    if (r == null) return 0;
    return whole ? r[1] : r[0];
  }

  void _applyOffer() {
    final rate = _rateFor(_selected, whole: _wholeVehicle);
    if (rate > 0) _offer.text = rate.round().toString();
  }

  Future<void> _findDriver() async {
    if (_submitting || _destination == null) return;
    final controller = AppControllerScope.of(context);
    final entered = double.tryParse(_offer.text.replaceAll(',', '').trim());
    final amount = entered == null ? null : (_wholeVehicle ? entered : entered * _seats);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter your fare offer before finding a driver.')));
      return;
    }
    if (!controller.loggedIn) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please sign in again to submit this booking request.')));
      return;
    }
    final choice = _cityVehicles[_selected];
    final seats = _wholeVehicle ? choice.capacity : _seats;
    setState(() => _submitting = true);
    try {
      final pickupAt = DateTime.now().add(const Duration(minutes: 10));
      final request = await controller.createLiveRideRequest({
        'pickupLabel': _pickupLabel,
        'destinationLabel': _destination!.title,
        'pickupLatitude': _pickup.latitude,
        'pickupLongitude': _pickup.longitude,
        'destinationLatitude': _destination!.lat,
        'destinationLongitude': _destination!.lng,
        'pickupAt': pickupAt.toUtc().toIso8601String(),
        'bookingType': _wholeVehicle ? 'WholeVehicle' : 'PerSeat',
        'seatsRequested': seats,
        'adults': seats,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': amount,
        'vehicleCategory': choice.name,
        'partyType': seats > 1 ? 'Group' : 'Individual',
        'familyOnly': false,
        'womenOnly': false,
        'notes': 'Travel within city • ${_wholeVehicle ? 'whole vehicle' : 'per seat'} • customer fare offer',
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
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.isEmpty ? 'Booking request could not be submitted.' : message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _from.dispose();
    _to.dispose();
    _offer.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasDestination = _destination != null;
    return Scaffold(
      backgroundColor: _ink,
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: _mapFilter,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: _pickup, initialZoom: 13.5),
              children: [
                TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.udrive.mobile'),
                if (hasDestination)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: [_pickup, LatLng(_destination!.lat, _destination!.lng)],
                        strokeWidth: 5,
                        color: Colors.white),
                  ]),
                MarkerLayer(markers: [
                  Marker(point: _pickup, width: 44, height: 44, child: const Icon(Icons.location_pin, color: _lime, size: 42)),
                  if (hasDestination)
                    Marker(
                        point: LatLng(_destination!.lat, _destination!.lng),
                        width: 42,
                        height: 42,
                        child: const Icon(Icons.flag_rounded, color: Colors.white, size: 34)),
                ]),
              ],
            ),
          ),
        ),
        const _TopBar(),
        // Top From / Destination fields
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 60, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _sheet,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Column(children: [
                _field(_from, 'From', Icons.my_location_rounded, onChanged: (v) => _pickupLabel = v),
                const SizedBox(height: 8),
                _field(_to, 'Destination', Icons.search_rounded,
                    autofocus: true, onChanged: _onDestinationChanged, showClear: true),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _lime)),
                  ),
                if (_results.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 210),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(top: 6),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 40),
                      itemBuilder: (context, i) {
                        final place = _results[i];
                        final km = const Distance().as(LengthUnit.Kilometer, _pickup, LatLng(place.lat, place.lng));
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on_outlined, color: Colors.white54, size: 22),
                          title: Text(place.title, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          subtitle: Text(place.subtitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 10.5)),
                          trailing: Text('${km.toStringAsFixed(1)} km', style: const TextStyle(color: _muted, fontSize: 10.5)),
                          onTap: () => _pickDestination(place),
                        );
                      },
                    ),
                  ),
              ]),
            ),
          ),
        ),
        // Bottom sheet: vehicles going that way + booking
        if (hasDestination)
          DraggableScrollableSheet(
            initialChildSize: .48,
            minChildSize: .30,
            maxChildSize: .90,
            snap: true,
            snapSizes: const [.48, .90],
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: _sheet,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 28, offset: Offset(0, -8))],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                children: [
                  const _Grabber(),
                  Text('Vehicles to ${_destination!.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  const Text('Pick a vehicle and send your fare offer to drivers heading this way',
                      style: TextStyle(color: _muted, fontSize: 10.5)),
                  const SizedBox(height: 12),
                  _modeToggle(),
                  if (!_wholeVehicle) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Seats', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      _round(Icons.remove, _seats > 1 ? () => setState(() => _seats--) : null),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          child: Text('$_seats', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
                      _round(Icons.add, _seats < _cityVehicles[_selected].capacity ? () => setState(() => _seats++) : null),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  ...List.generate(_cityVehicles.length, (i) => _vehicleTile(i)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _offer,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      labelText: _wholeVehicle ? 'Your whole vehicle offer (PKR)' : 'Your offer per seat (PKR)',
                      labelStyle: const TextStyle(color: _muted, fontSize: 11),
                      prefixIcon: const Icon(Icons.payments_outlined, color: _lime, size: 20),
                      filled: true,
                      fillColor: _tile,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _submitting ? null : _findDriver,
                      style: FilledButton.styleFrom(
                          backgroundColor: _lime,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
                          : const Text('Find a driver', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
      {bool autofocus = false, bool showClear = false, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.white, size: 22),
        suffixIcon: showClear && controller.text.isNotEmpty
            ? IconButton(
                onPressed: () {
                  controller.clear();
                  _onDestinationChanged('');
                  setState(() => _destination = null);
                },
                icon: const Icon(Icons.cancel_rounded, color: Colors.white54, size: 20))
            : null,
        filled: true,
        fillColor: _tile,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Colors.white24, width: 1.4)),
      ),
    );
  }

  Widget _modeToggle() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          Expanded(child: _segment('Per seat', !_wholeVehicle, () => setState(() { _wholeVehicle = false; _applyOffer(); }))),
          Expanded(child: _segment('Whole vehicle', _wholeVehicle, () => setState(() { _wholeVehicle = true; _applyOffer(); }))),
        ]),
      );

  Widget _segment(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? _lime : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(label,
              style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w900)),
        ),
      );

  Widget _round(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: onTap == null ? .03 : .08), shape: BoxShape.circle),
          child: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white, size: 17),
        ),
      );

  Widget _vehicleTile(int index) {
    final v = _cityVehicles[index];
    final active = _selected == index;
    final perSeat = _rateFor(index, whole: false);
    final whole = _rateFor(index, whole: true);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? const Color(0xFF292C2A) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            _selected = index;
            _seats = _seats.clamp(1, v.capacity).toInt();
            _applyOffer();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? Colors.white24 : Colors.white.withValues(alpha: .05))),
            child: Row(children: [
              Container(
                width: 84,
                height: 60,
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: active ? .06 : .03), borderRadius: BorderRadius.circular(14)),
                child: Image.asset(v.asset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                  Text('${v.capacity} seats • ${v.note}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 10.5)),
                  const SizedBox(height: 5),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _pill('Seat', perSeat > 0 ? 'PKR ${perSeat.round()}' : '—'),
                    _pill('Full', whole > 0 ? 'PKR ${whole.round()}' : '—'),
                  ]),
                ]),
              ),
              Icon(active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: active ? _lime : Colors.white38, size: 24),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _pill(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $value', style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );

// ═════════════════════════════════════════════════════════════════════════════
// 2) TOURS & TRIPS — destination → matching scheduled tour packages
// ═════════════════════════════════════════════════════════════════════════════
class ToursScreen extends StatefulWidget {
  const ToursScreen({required this.pickupLabel, required this.pickupPoint, super.key});
  final String pickupLabel;
  final LatLng pickupPoint;
  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  final _to = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;
  _Place? _destination;
  List<_Place> _results = const [];
  bool _searching = false;
  bool _submitting = false;

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _searching = false;
        _results = const [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final r = await _searchPlaces(q);
      if (mounted) setState(() { _results = r; _searching = false; });
    });
  }

  void _pick(_Place place) {
    FocusScope.of(context).unfocus();
    setState(() {
      _destination = place;
      _to.text = place.label;
      _results = const [];
    });
    _mapController.move(LatLng(place.lat, place.lng), 9.5);
  }

  List<LiveTourPackage> _matching(AppController controller) {
    if (_destination == null) return const [];
    final destination = _destination!.title.trim().toLowerCase();
    final now = DateTime.now();
    final end = now.add(const Duration(days: 30));
    final list = controller.liveMarketplacePackages.where((p) {
      final searchable = '${p.destination} ${p.title} ${p.pickupPoint} ${p.startingCity}'.toLowerCase();
      final matches = searchable.contains(destination) || destination.contains(p.destination.toLowerCase());
      final within = p.departureAt.isAfter(now.subtract(const Duration(hours: 2))) && p.departureAt.isBefore(end);
      return matches && within;
    }).toList()
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return list;
  }

  bool _bookable(LiveTourPackage p) => p.availableSeats > 0 && p.departureAt.difference(DateTime.now()).inMinutes > 10;

  String _timing(LiveTourPackage p) {
    final d = p.departureAt;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _image(LiveTourPackage p) {
    switch (_normalise(p.vehicle)) {
      case 'coster':
        return 'assets/vehicles_photo/coaster_clean.png';
      case 'bike':
        return 'assets/vehicles_photo/bike_clean.png';
      case 'rickshaw':
        return 'assets/vehicles_photo/rickshaw_clean.png';
      default:
        return 'assets/vehicles_photo/car_clean.png';
    }
  }

  Future<void> _book(LiveTourPackage package, {required bool whole}) async {
    if (_submitting) return;
    final controller = AppControllerScope.of(context);
    if (!_bookable(package)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This tour has passed its booking cutoff.')));
      return;
    }
    if (!controller.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in again to book this tour.')));
      return;
    }
    final seats = whole ? package.totalSeats : 1;
    final amount = whole ? package.wholeVehiclePrice : package.pricePerSeat;
    setState(() => _submitting = true);
    try {
      final request = await controller.createLiveRideRequest({
        'pickupLabel': widget.pickupLabel,
        'destinationLabel': _destination!.title,
        'pickupLatitude': widget.pickupPoint.latitude,
        'pickupLongitude': widget.pickupPoint.longitude,
        'destinationLatitude': _destination!.lat,
        'destinationLongitude': _destination!.lng,
        'pickupAt': package.departureAt.toUtc().toIso8601String(),
        'bookingType': whole ? 'WholeVehicle' : 'PerSeat',
        'seatsRequested': seats,
        'adults': seats,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': amount,
        'vehicleCategory': package.vehicle,
        'partyType': seats > 1 ? 'Group' : 'Individual',
        'familyOnly': false,
        'womenOnly': false,
        'notes': 'Tours & Trips • ${package.title} • published tour rate',
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
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.isEmpty ? 'Tour booking could not be submitted.' : message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _to.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final packages = _matching(controller);
    final hasDestination = _destination != null;
    return Scaffold(
      backgroundColor: _ink,
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: _mapFilter,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: widget.pickupPoint, initialZoom: 9),
              children: [
                TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.udrive.mobile'),
                if (hasDestination)
                  MarkerLayer(markers: [
                    Marker(
                        point: LatLng(_destination!.lat, _destination!.lng),
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.landscape_rounded, color: _lime, size: 40)),
                  ]),
              ],
            ),
          ),
        ),
        const _TopBar(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 60, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _sheet,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Column(children: [
                TextField(
                  controller: _to,
                  autofocus: true,
                  onChanged: _onChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Where do you want to tour?',
                    labelStyle: const TextStyle(color: _muted, fontSize: 12),
                    prefixIcon: const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 22),
                    filled: true,
                    fillColor: _tile,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Colors.white24, width: 1.4)),
                  ),
                ),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _lime)),
                  ),
                if (_results.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 210),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(top: 6),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 40),
                      itemBuilder: (context, i) {
                        final place = _results[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined, color: Colors.white54, size: 22),
                          title: Text(place.title, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          subtitle: Text(place.subtitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 10.5)),
                          onTap: () => _pick(place),
                        );
                      },
                    ),
                  ),
              ]),
            ),
          ),
        ),
        if (hasDestination)
          DraggableScrollableSheet(
            initialChildSize: .46,
            minChildSize: .28,
            maxChildSize: .90,
            snap: true,
            snapSizes: const [.46, .90],
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: _sheet,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 28, offset: Offset(0, -8))],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                children: [
                  const _Grabber(),
                  Text('Tours to ${_destination!.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('${packages.length} scheduled ${packages.length == 1 ? 'tour' : 'tours'} in the next 30 days',
                      style: const TextStyle(color: _muted, fontSize: 10.5)),
                  const SizedBox(height: 12),
                  if (packages.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(16)),
                      child: const Row(children: [
                        Icon(Icons.directions_bus_filled_rounded, color: _lime),
                        SizedBox(width: 10),
                        Expanded(child: Text('No scheduled tour to this destination in the next 30 days. Try a nearby valley or check back soon.',
                            style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35))),
                      ]),
                    )
                  else
                    ...packages.map(_packageCard),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  Widget _packageCard(LiveTourPackage p) {
    final bookable = _bookable(p);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 84,
              height: 62,
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(14)),
              child: Image.asset(_image(p), fit: BoxFit.contain, filterQuality: FilterQuality.high),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('${p.vehicle} • ${p.driverName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 10.5)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.schedule_rounded, size: 12, color: _lime),
                  const SizedBox(width: 4),
                  Text(_timing(p), style: TextStyle(color: bookable ? _lime : Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${p.availableSeats} seats', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: bookable ? () => _book(p, whole: false) : null,
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(42),
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Per seat • PKR ${p.pricePerSeat.round()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: FilledButton(
                onPressed: bookable ? () => _book(p, whole: true) : null,
                style: FilledButton.styleFrom(
                    backgroundColor: _lime,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Full • PKR ${p.wholeVehiclePrice.round()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3) PRIVATE VEHICLES — searchable catalog with capacity + daily / driver charges
// ═════════════════════════════════════════════════════════════════════════════
class PrivateVehiclesScreen extends StatefulWidget {
  const PrivateVehiclesScreen({required this.pickupLabel, required this.pickupPoint, super.key});
  final String pickupLabel;
  final LatLng pickupPoint;
  @override
  State<PrivateVehiclesScreen> createState() => _PrivateVehiclesScreenState();
}

class _PrivateVehiclesScreenState extends State<PrivateVehiclesScreen> {
  final _search = TextEditingController();
  String _query = '';
  final Map<String, double> _baseRate = {}; // normalised name -> whole vehicle rate
  bool _loading = true;

  // Indicative charge model derived from the whole-vehicle base rate when the
  // backend does not yet supply dedicated per-day / driver fields. If the API
  // returns withDriverRate / withoutDriverRate / perDayRate they override these.
  static const double _driverFeePerDay = 2500;

  final Map<String, Map<String, double>> _apiRates = {}; // name -> {withDriver, withoutDriver, perDay}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final controller = AppControllerScope.of(context);
      final response = await controller.apiClient
          .getJson('/api/v1/catalog/service-rates?serviceType=PrivateVehicle', authenticated: false);
      final raw = response['data'];
      if (raw is List) {
        for (final item in raw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final key = _normalise('${map['vehicleCategory'] ?? ''}');
          _baseRate[key] = (map['wholeVehicleRate'] as num?)?.toDouble() ?? 0;
          final withDriver = (map['withDriverRate'] as num?)?.toDouble();
          final withoutDriver = (map['withoutDriverRate'] as num?)?.toDouble();
          final perDay = (map['perDayRate'] as num?)?.toDouble();
          if (withDriver != null || withoutDriver != null || perDay != null) {
            _apiRates[key] = {
              if (withDriver != null) 'withDriver': withDriver,
              if (withoutDriver != null) 'withoutDriver': withoutDriver,
              if (perDay != null) 'perDay': perDay,
            };
          }
        }
      }
    } catch (_) {
      // Charges fall back to the indicative model below.
    }
    if (mounted) setState(() => _loading = false);
  }

  double _perDay(_VehicleType v) {
    final key = _normalise(v.name);
    return _apiRates[key]?['perDay'] ?? _baseRate[key] ?? 0;
  }

  double _withoutDriver(_VehicleType v) {
    final key = _normalise(v.name);
    return _apiRates[key]?['withoutDriver'] ?? _perDay(v);
  }

  double _withDriver(_VehicleType v) {
    final key = _normalise(v.name);
    return _apiRates[key]?['withDriver'] ?? (_perDay(v) + _driverFeePerDay);
  }

  List<_VehicleType> get _filtered {
    if (_query.trim().isEmpty) return _privateVehicles;
    final q = _query.toLowerCase();
    return _privateVehicles.where((v) => v.name.toLowerCase().contains(q) || v.note.toLowerCase().contains(q)).toList();
  }

  void _openBooking(_VehicleType v) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PrivateBookingSheet(
        vehicle: v,
        perDay: _perDay(v),
        withDriver: _withDriver(v),
        withoutDriver: _withoutDriver(v),
        pickupLabel: widget.pickupLabel,
        pickupPoint: widget.pickupPoint,
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        backgroundColor: _ink,
        surfaceTintColor: _ink,
        foregroundColor: Colors.white,
        title: const Text('Private Vehicle', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.white70),
              hintText: 'Search vehicle type (car, SUV, coaster, bike)',
              hintStyle: const TextStyle(color: _muted, fontSize: 12.5),
              isDense: true,
              filled: true,
              fillColor: _tile,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _lime))
              : items.isEmpty
                  ? const Center(child: Text('No vehicle matches your search.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 26),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _vehicleCard(items[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _vehicleCard(_VehicleType v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openBooking(v),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 104,
                  height: 74,
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04), borderRadius: BorderRadius.circular(14)),
                  child: Image.asset(v.asset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(v.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.event_seat_rounded, size: 13, color: _lime),
                        const SizedBox(width: 4),
                        Text('${v.capacity} seats', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _charge('Per day', _perDay(v))),
                const SizedBox(width: 8),
                Expanded(child: _charge('With driver', _withDriver(v))),
                const SizedBox(width: 8),
                Expanded(child: _charge('Self drive', _withoutDriver(v))),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: () => _openBooking(v),
                  style: FilledButton.styleFrom(
                      backgroundColor: _lime,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                  child: const Text('Book this vehicle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _charge(String label, double value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 9.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value > 0 ? 'PKR ${value.round()}' : '—',
              style: const TextStyle(color: _lime, fontSize: 12.5, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _PrivateBookingSheet extends StatefulWidget {
  const _PrivateBookingSheet({
    required this.vehicle,
    required this.perDay,
    required this.withDriver,
    required this.withoutDriver,
    required this.pickupLabel,
    required this.pickupPoint,
  });
  final _VehicleType vehicle;
  final double perDay, withDriver, withoutDriver;
  final String pickupLabel;
  final LatLng pickupPoint;

  @override
  State<_PrivateBookingSheet> createState() => _PrivateBookingSheetState();
}

class _PrivateBookingSheetState extends State<_PrivateBookingSheet> {
  bool _withDriver = true;
  int _days = 1;
  bool _submitting = false;

  double get _total => (_withDriver ? widget.withDriver : widget.withoutDriver) * _days;

  Future<void> _confirm() async {
    if (_submitting) return;
    final controller = AppControllerScope.of(context);
    if (!controller.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in again to book this vehicle.')));
      return;
    }
    if (_total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This vehicle has no rate configured yet.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final request = await controller.createLiveRideRequest({
        'pickupLabel': widget.pickupLabel,
        'destinationLabel': 'Private ${widget.vehicle.name} • $_days day${_days > 1 ? 's' : ''}',
        'pickupLatitude': widget.pickupPoint.latitude,
        'pickupLongitude': widget.pickupPoint.longitude,
        'destinationLatitude': widget.pickupPoint.latitude,
        'destinationLongitude': widget.pickupPoint.longitude,
        'pickupAt': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String(),
        'bookingType': 'WholeVehicle',
        'seatsRequested': widget.vehicle.capacity,
        'adults': widget.vehicle.capacity,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': _total,
        'vehicleCategory': widget.vehicle.name,
        'partyType': 'Group',
        'familyOnly': false,
        'womenOnly': false,
        'notes': 'Private Vehicle • ${_withDriver ? 'with driver' : 'self drive'} • $_days day${_days > 1 ? 's' : ''}',
      });
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => DriverOffersScreen(
            rideRequestId: request.id,
            pickup: request.pickupLabel,
            destination: request.destinationLabel,
            customerOffer: request.customerOffer.round(),
            vehicleName: request.vehicleCategory,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.isEmpty ? 'Booking could not be submitted.' : message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(color: _sheet, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Grabber(),
          Row(children: [
            Container(
              width: 84,
              height: 60,
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
              child: Image.asset(widget.vehicle.asset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Book ${widget.vehicle.name}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                Text('${widget.vehicle.capacity} seats • ${widget.vehicle.note}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(13)),
            child: Row(children: [
              Expanded(child: _seg('With driver', _withDriver, () => setState(() => _withDriver = true))),
              Expanded(child: _seg('Self drive', !_withDriver, () => setState(() => _withDriver = false))),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Days', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            _round(Icons.remove, _days > 1 ? () => setState(() => _days--) : null),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('$_days', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900))),
            _round(Icons.add, _days < 30 ? () => setState(() => _days++) : null),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Text('Estimated total', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_total > 0 ? 'PKR ${_total.round()}' : '—',
                  style: const TextStyle(color: _lime, fontSize: 17, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _confirm,
              style: FilledButton.styleFrom(
                  backgroundColor: _lime,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
                  : const Text('Request this vehicle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? _lime : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 12, fontWeight: FontWeight.w900)),
        ),
      );

  Widget _round(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: onTap == null ? .03 : .09), shape: BoxShape.circle),
          child: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white, size: 18),
        ),
      );
}
