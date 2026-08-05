import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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
        UDriveServiceType.city => 'Travel within city',
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
    super.key,
  });

  final UDriveServiceType serviceType;
  final String pickupLabel;
  final LatLng pickupPoint;

  @override
  State<UDriveRouteFlowScreen> createState() => _UDriveRouteFlowScreenState();
}

class _UDriveRouteFlowScreenState extends State<UDriveRouteFlowScreen> {
  final _to = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _searching = false;
  List<_PlaceResult> _results = const [];

  static const _suggested = [
    _PlaceResult('D-17/2 Markaz', 'D-17, Islamabad', 33.6945, 72.8257),
    _PlaceResult('F-10 Markaz', 'F-10, Islamabad', 33.6998, 73.0127),
    _PlaceResult('Blue Area', 'Jinnah Avenue, Islamabad', 33.7105, 73.0551),
    _PlaceResult('Saddar Rawalpindi', 'Saddar, Rawalpindi', 33.5964, 73.0537),
  ];

  @override
  void initState() {
    super.initState();
    _results = _suggested;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _to.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searching = false;
        _results = _suggested;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '8',
        'countrycodes': 'pk',
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'UDrive-Mobile/1.0',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final raw = jsonDecode(response.body);
      if (raw is! List) return;
      final items = raw.whereType<Map>().map((entry) {
        final map = Map<String, dynamic>.from(entry);
        final display = '${map['display_name'] ?? ''}'.trim();
        final parts = display.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        return _PlaceResult(
          parts.isEmpty ? query : parts.first,
          parts.skip(1).take(3).join(', '),
          double.tryParse('${map['lat']}') ?? 0,
          double.tryParse('${map['lon']}') ?? 0,
        );
      }).where((item) => item.latitude != 0 && item.longitude != 0).toList();
      if (mounted) setState(() => _results = items);
    } catch (_) {
      // Keep previous suggestions when the public search service is unavailable.
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _select(_PlaceResult place) {
    FocusScope.of(context).unfocus();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => UDriveVehicleSelectionScreen(
          serviceType: widget.serviceType,
          pickupLabel: widget.pickupLabel,
          pickupPoint: widget.pickupPoint,
          destination: place,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _to.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                .48, 0, 0, 0, 0,
                0, .55, 0, 0, 0,
                0, 0, .72, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: FlutterMap(
                options: MapOptions(initialCenter: widget.pickupPoint, initialZoom: 14.8),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.udrive.mobile',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: widget.pickupPoint,
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.location_pin, color: _lime, size: 46),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .22))),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                height: MediaQuery.sizeOf(context).height * .92,
                decoration: const BoxDecoration(
                  color: Color(0xFA181A18),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 26, offset: Offset(0, -8))],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 9),
                    Container(width: 46, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
                      child: Row(
                        children: [
                          const Spacer(),
                          const Text('Enter your route', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                          const Spacer(),
                          IconButton.filledTonal(
                            onPressed: () => Navigator.pop(context),
                            style: IconButton.styleFrom(backgroundColor: Colors.white10),
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _RouteField(
                            label: 'From',
                            value: widget.pickupLabel,
                            icon: Icons.airline_seat_recline_normal_rounded,
                            readOnly: true,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _to,
                            focusNode: _focus,
                            onChanged: (value) {
                              setState(() {});
                              _onChanged(value);
                            },
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                            decoration: InputDecoration(
                              labelText: 'To',
                              labelStyle: const TextStyle(color: _muted),
                              hintText: widget.serviceType == UDriveServiceType.tours ? 'Search destination or city' : 'Type destination or address',
                              hintStyle: const TextStyle(color: Colors.white38),
                              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white, size: 30),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (typed)
                                    IconButton(
                                      onPressed: () {
                                        _to.clear();
                                        _onChanged('');
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.cancel_rounded, color: Colors.white54),
                                    ),
                                  const Padding(
                                    padding: EdgeInsets.only(right: 10),
                                    child: Icon(Icons.map_rounded, color: Color(0xFF75B8FF)),
                                  ),
                                ],
                              ),
                              filled: true,
                              fillColor: _tile,
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white70, width: 1.4)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white, width: 2)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Row(
                        children: [
                          _FilterChip(label: typed ? 'Search Results' : 'Suggested', selected: true),
                          const SizedBox(width: 9),
                          const _FilterChip(label: 'Saved', selected: false),
                          if (_searching) ...[
                            const Spacer(),
                            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _lime)),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 50),
                        itemBuilder: (context, index) {
                          final place = _results[index];
                          final distance = const Distance().as(LengthUnit.Kilometer, widget.pickupPoint, LatLng(place.latitude, place.longitude));
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 7),
                            leading: Icon(typed ? Icons.location_on_outlined : Icons.history_rounded, color: Colors.white54, size: 29),
                            title: Text(place.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                            subtitle: Text(place.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, height: 1.3)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (typed) Text('${distance.toStringAsFixed(1)} km', style: const TextStyle(color: _muted, fontSize: 12)),
                                const SizedBox(width: 8),
                                const Icon(Icons.bookmark_border_rounded, color: Colors.white54),
                              ],
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
          ),
        ],
      ),
    );
  }
}

class UDriveVehicleSelectionScreen extends StatefulWidget {
  const UDriveVehicleSelectionScreen({
    required this.serviceType,
    required this.pickupLabel,
    required this.pickupPoint,
    required this.destination,
    super.key,
  });

  final UDriveServiceType serviceType;
  final String pickupLabel;
  final LatLng pickupPoint;
  final _PlaceResult destination;

  @override
  State<UDriveVehicleSelectionScreen> createState() => _UDriveVehicleSelectionScreenState();
}

class _UDriveVehicleSelectionScreenState extends State<UDriveVehicleSelectionScreen> {
  int _selected = 1;
  bool _submitting = false;
  bool _autoAccept = false;
  DateTime _tourDate = DateTime.now().add(const Duration(days: 1));

  List<_VehicleChoiceData> get _choices => switch (widget.serviceType) {
        UDriveServiceType.city => const [
            _VehicleChoiceData('Bike', '1 seat • 2 min', 'Fast and affordable', 350, Icons.two_wheeler_rounded),
            _VehicleChoiceData('Car', '4 seats • 3 min', 'Comfort ride', 900, Icons.directions_car_rounded),
            _VehicleChoiceData('Rickshaw', '3 seats • 4 min', 'Budget city ride', 450, Icons.electric_rickshaw_rounded),
            _VehicleChoiceData('Private Car', '4 seats • 5 min', 'Book full vehicle', 1450, Icons.local_taxi_rounded),
          ],
        UDriveServiceType.tours => const [
            _VehicleChoiceData('Car', '4 seats • scheduled', 'Comfortable tour', 6500, Icons.directions_car_rounded),
            _VehicleChoiceData('Coster', '22 seats • scheduled', 'Shared group trip', 2500, Icons.airport_shuttle_rounded),
            _VehicleChoiceData('Private Coster', '22 seats • private', 'Complete vehicle', 28000, Icons.directions_bus_filled_rounded),
          ],
        UDriveServiceType.privateVehicle => const [
            _VehicleChoiceData('Private Car', '4 seats • 5 min', 'Comfort & privacy', 1800, Icons.local_taxi_rounded),
            _VehicleChoiceData('Private Coster', '22 seats • arranged', 'Large groups', 12000, Icons.directions_bus_filled_rounded),
            _VehicleChoiceData('Bike', '1 seat • 2 min', 'Quick private ride', 500, Icons.two_wheeler_rounded),
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

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final choice = _choices[_selected];
    try {
      final controller = AppControllerScope.of(context);
      final pickupAt = widget.serviceType == UDriveServiceType.city
          ? DateTime.now().add(const Duration(minutes: 10))
          : DateTime(_tourDate.year, _tourDate.month, _tourDate.day, 8);
      final wholeVehicle = widget.serviceType == UDriveServiceType.privateVehicle || choice.name.startsWith('Private');
      final request = await controller.createLiveRideRequest({
        'pickupLabel': widget.pickupLabel,
        'destinationLabel': widget.destination.title,
        'pickupLatitude': widget.pickupPoint.latitude,
        'pickupLongitude': widget.pickupPoint.longitude,
        'destinationLatitude': widget.destination.latitude,
        'destinationLongitude': widget.destination.longitude,
        'pickupAt': pickupAt.toUtc().toIso8601String(),
        'bookingType': wholeVehicle ? 'WholeVehicle' : 'PerSeat',
        'seatsRequested': choice.name.contains('Coster') ? (wholeVehicle ? 22 : 1) : (wholeVehicle ? 4 : 1),
        'adults': 1,
        'children': 0,
        'luggageCount': 0,
        'customerOffer': choice.price,
        'vehicleCategory': choice.name,
        'partyType': 'Individual',
        'familyOnly': false,
        'womenOnly': false,
        'notes': '${widget.serviceType.title}${_autoAccept ? ' • Auto-accept enabled' : ''}',
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinationPoint = LatLng(widget.destination.latitude, widget.destination.longitude);
    final selected = _choices[_selected];
    final center = LatLng(
      (widget.pickupPoint.latitude + destinationPoint.latitude) / 2,
      (widget.pickupPoint.longitude + destinationPoint.longitude) / 2,
    );
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                .48, 0, 0, 0, 0,
                0, .55, 0, 0, 0,
                0, 0, .72, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 11.4),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.udrive.mobile'),
                  PolylineLayer(polylines: [
                    Polyline(points: [widget.pickupPoint, destinationPoint], strokeWidth: 5, color: Colors.white),
                  ]),
                  MarkerLayer(markers: [
                    Marker(point: widget.pickupPoint, width: 46, height: 46, child: const Icon(Icons.location_pin, color: _lime, size: 44)),
                    Marker(point: destinationPoint, width: 46, height: 46, child: const Icon(Icons.flag_rounded, color: Colors.white, size: 38)),
                  ]),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton.filled(onPressed: () => Navigator.pop(context), style: IconButton.styleFrom(backgroundColor: const Color(0xE8181A18)), icon: const Icon(Icons.arrow_back_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: _RouteSummary(pickup: widget.pickupLabel, destination: widget.destination.title)),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: .57,
            minChildSize: .48,
            maxChildSize: .88,
            builder: (context, controller) => Container(
              decoration: const BoxDecoration(color: Color(0xFA181A18), borderRadius: BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 26, offset: Offset(0, -8))]),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 9, 18, 28),
                children: [
                  Center(child: Container(width: 46, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)))),
                  const SizedBox(height: 14),
                  Text(widget.serviceType.title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                  Text(widget.serviceType.subtitle, style: const TextStyle(color: _muted)),
                  if (widget.serviceType == UDriveServiceType.tours) ...[
                    const SizedBox(height: 10),
                    ListTile(
                      onTap: _pickDate,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      tileColor: _tile,
                      leading: const Icon(Icons.calendar_month_rounded, color: _lime),
                      title: const Text('Travel date', style: TextStyle(color: _muted, fontSize: 12)),
                      subtitle: Text('${_tourDate.day}/${_tourDate.month}/${_tourDate.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ...List.generate(_choices.length, (index) {
                    final item = _choices[index];
                    final active = _selected == index;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: active ? const Color(0xFF343734) : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          onTap: () => setState(() => _selected = index),
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 13, 14, 13),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: active ? Colors.white24 : Colors.transparent)),
                            child: Row(
                              children: [
                                SizedBox(width: 70, child: Icon(item.icon, color: active ? _lime : Colors.white70, size: 48)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                                    Text(item.meta, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                    Text(item.note, style: const TextStyle(color: _muted, fontSize: 13)),
                                  ]),
                                ),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text('PKR ${item.price}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 9),
                                  Icon(active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: active ? _lime : Colors.white54, size: 29),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(16)),
                    child: const Row(children: [Icon(Icons.info_outline_rounded, color: Colors.white), SizedBox(width: 10), Expanded(child: Text('Fare may vary by route, tolls, or parking fees.', style: TextStyle(color: Colors.white70)))]),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    value: _autoAccept,
                    activeThumbColor: _lime,
                    onChanged: (value) => setState(() => _autoAccept = value),
                    secondary: const Icon(Icons.send_rounded, color: Colors.white),
                    title: Text('Auto-accept offer of PKR ${selected.price}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(
                    height: 58,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: _submitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                          : Text(widget.serviceType == UDriveServiceType.tours ? 'Find available trip' : 'Find a driver', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    ),
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
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
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

class _PlaceResult {
  const _PlaceResult(this.title, this.subtitle, this.latitude, this.longitude);
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
}

class _VehicleChoiceData {
  const _VehicleChoiceData(this.name, this.meta, this.note, this.price, this.icon);
  final String name;
  final String meta;
  final String note;
  final int price;
  final IconData icon;
}
