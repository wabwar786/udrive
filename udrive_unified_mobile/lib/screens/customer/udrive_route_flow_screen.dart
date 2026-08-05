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
                          const Text('Enter your route', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
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
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
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
                            title: Text(place.title, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
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

enum _FareBookingMode { perSeat, wholeVehicle }

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
  int _selected = 0;
  bool _submitting = false;
  bool _autoAccept = false;
  DateTime _tourDate = DateTime.now().add(const Duration(days: 1));
  _FareBookingMode _bookingMode = _FareBookingMode.perSeat;
  int _seats = 1;
  final _perSeatOffer = TextEditingController();
  final _wholeVehicleOffer = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.serviceType == UDriveServiceType.privateVehicle) {
      _bookingMode = _FareBookingMode.wholeVehicle;
    }
  }

  @override
  void dispose() {
    _perSeatOffer.dispose();
    _wholeVehicleOffer.dispose();
    super.dispose();
  }

  List<_VehicleChoiceData> get _choices => switch (widget.serviceType) {
        UDriveServiceType.city => const [
            _VehicleChoiceData('Bike', '1 seat', 'Fast city travel', 1, Icons.two_wheeler_rounded),
            _VehicleChoiceData('Car', '4 seats', 'Comfortable city ride', 4, Icons.directions_car_rounded),
            _VehicleChoiceData('Rickshaw', '3 seats', 'Economical local ride', 3, Icons.electric_rickshaw_rounded),
          ],
        UDriveServiceType.tours => const [
            _VehicleChoiceData('Car', '4 seats', 'Tour car or shared seat', 4, Icons.directions_car_rounded),
            _VehicleChoiceData('Coster', '22 seats', 'Group tour and per-seat travel', 22, Icons.airport_shuttle_rounded),
          ],
        UDriveServiceType.privateVehicle => const [
            _VehicleChoiceData('Car', '4 seats', 'Book the complete car', 4, Icons.local_taxi_rounded),
            _VehicleChoiceData('Coster', '22 seats', 'Private vehicle for groups', 22, Icons.directions_bus_filled_rounded),
            _VehicleChoiceData('Bike', '1 seat', 'Private bike ride', 1, Icons.two_wheeler_rounded),
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
    if (v.contains('coster') || v.contains('coaster') || v.contains('bus') || v.contains('van')) return 'coster';
    if (v.contains('bike') || v.contains('motor')) return 'bike';
    if (v.contains('rickshaw')) return 'rickshaw';
    return 'car';
  }

  LiveTourPackage? _matchingPackage(AppController controller, _VehicleChoiceData choice) {
    if (widget.serviceType != UDriveServiceType.tours) return null;
    final destination = widget.destination.title.toLowerCase();
    final candidates = controller.liveMarketplacePackages.where((package) {
      final matchesDestination = package.destination.toLowerCase().contains(destination) ||
          package.title.toLowerCase().contains(destination) ||
          destination.contains(package.destination.toLowerCase());
      final matchesVehicle = _normaliseVehicle(package.vehicle) == _normaliseVehicle(choice.name);
      final withinThirtyDays = package.departureAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1))) &&
          package.departureAt.isBefore(DateTime.now().add(const Duration(days: 30)));
      return matchesDestination && matchesVehicle && withinThirtyDays;
    }).toList()..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return candidates.isEmpty ? null : candidates.first;
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
    final amount = package == null
        ? _typedAmount(wholeVehicle ? _wholeVehicleOffer : _perSeatOffer)
        : (wholeVehicle ? package.wholeVehiclePrice : package.pricePerSeat * _seats);

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
      final pickupAt = widget.serviceType == UDriveServiceType.city
          ? DateTime.now().add(const Duration(minutes: 10))
          : DateTime(_tourDate.year, _tourDate.month, _tourDate.day, 8);
      final requestedSeats = wholeVehicle ? choice.capacity : _seats.clamp(1, choice.capacity).toInt();
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
        'notes': '${widget.serviceType.title} • ${wholeVehicle ? 'whole vehicle' : 'per seat'}${package == null ? ' • customer fare offer' : ' • published tour rate'}${_autoAccept ? ' • auto-accept enabled' : ''}',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? 'Booking request could not be submitted.' : message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _money(double value) => value <= 0 ? 'Not set' : 'PKR ${value.round()}';

  @override
  Widget build(BuildContext context) {
    final app = AppControllerScope.of(context);
    final destinationPoint = LatLng(widget.destination.latitude, widget.destination.longitude);
    final selected = _choices[_selected];
    final selectedPackage = _matchingPackage(app, selected);
    final center = LatLng(
      (widget.pickupPoint.latitude + destinationPoint.latitude) / 2,
      (widget.pickupPoint.longitude + destinationPoint.longitude) / 2,
    );
    final perSeatAmount = selectedPackage?.pricePerSeat ?? _typedAmount(_perSeatOffer) ?? 0;
    final wholeAmount = selectedPackage?.wholeVehiclePrice ?? _typedAmount(_wholeVehicleOffer) ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E0D),
      body: Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                .34, 0, 0, 0, 0,
                0, .40, 0, 0, 0,
                0, 0, .54, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 11.4),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.udrive.mobile'),
                  PolylineLayer(polylines: [Polyline(points: [widget.pickupPoint, destinationPoint], strokeWidth: 5, color: Colors.white)]),
                  MarkerLayer(markers: [
                    Marker(point: widget.pickupPoint, width: 42, height: 42, child: const Icon(Icons.location_pin, color: _lime, size: 40)),
                    Marker(point: destinationPoint, width: 42, height: 42, child: const Icon(Icons.flag_rounded, color: Colors.white, size: 34)),
                  ]),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(backgroundColor: const Color(0xF0121413)),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _RouteSummary(pickup: widget.pickupLabel, destination: widget.destination.title)),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: .66,
            minChildSize: .56,
            maxChildSize: .94,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFC111312),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 30, offset: Offset(0, -8))],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.serviceType.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(widget.serviceType == UDriveServiceType.tours ? 'Published tour rates are shown when available' : 'Choose a vehicle and enter your fare offer', style: const TextStyle(color: _muted, fontSize: 10.5)),
                      ])),
                      if (widget.serviceType == UDriveServiceType.tours)
                        TextButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded, size: 17), label: Text('${_tourDate.day}/${_tourDate.month}', style: const TextStyle(fontSize: 11))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFF252826), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(child: _ModeButton(label: 'Per seat', selected: _bookingMode == _FareBookingMode.perSeat, onTap: () => setState(() => _bookingMode = _FareBookingMode.perSeat))),
                      Expanded(child: _ModeButton(label: 'Whole vehicle', selected: _bookingMode == _FareBookingMode.wholeVehicle, onTap: () => setState(() => _bookingMode = _FareBookingMode.wholeVehicle))),
                    ]),
                  ),
                  if (_bookingMode == _FareBookingMode.perSeat) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Seats', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      _RoundMiniButton(icon: Icons.remove, onTap: _seats > 1 ? () => setState(() => _seats--) : null),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 13), child: Text('$_seats', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
                      _RoundMiniButton(icon: Icons.add, onTap: _seats < selected.capacity ? () => setState(() => _seats++) : null),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  ...List.generate(_choices.length, (index) {
                    final item = _choices[index];
                    final active = _selected == index;
                    final package = _matchingPackage(app, item);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                        color: active ? const Color(0xFF292C2A) : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: () => setState(() { _selected = index; _seats = _seats.clamp(1, item.capacity).toInt(); }),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: active ? Colors.white24 : Colors.white.withValues(alpha: .04))),
                            child: Row(children: [
                              Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .055), borderRadius: BorderRadius.circular(14)), child: Icon(item.icon, color: active ? _lime : Colors.white70, size: 29)),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                                Text('${item.meta}  •  ${item.note}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 10.5)),
                                const SizedBox(height: 5),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  _RatePill(label: 'Seat', value: package == null ? 'Your offer' : _money(package.pricePerSeat)),
                                  _RatePill(label: 'Full', value: package == null ? 'Your offer' : _money(package.wholeVehiclePrice)),
                                ]),
                              ])),
                              Icon(active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: active ? _lime : Colors.white38, size: 24),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }),
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
                            ? 'No fixed local tariff is invented. Your offer is sent to verified drivers, who can accept or send a counter-offer.'
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
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
                          : Text(widget.serviceType == UDriveServiceType.tours ? 'Find tour vehicle' : 'Find a driver', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
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

class _PlaceResult {
  const _PlaceResult(this.title, this.subtitle, this.latitude, this.longitude);
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
}

class _VehicleChoiceData {
  const _VehicleChoiceData(this.name, this.meta, this.note, this.capacity, this.icon);
  final String name;
  final String meta;
  final String note;
  final int capacity;
  final IconData icon;
}
