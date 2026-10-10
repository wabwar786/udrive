import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/maps/ud_map.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/hotel_models.dart';
import '../../core/routing/route_repository.dart';
import '../../core/widgets/home_service.dart';
import '../../data/models.dart';
import '../customer/vehicle_choice_screen.dart';
import 'hotel_bits.dart';

/// How far the hotel is, from where the guest is standing.
///
/// Costs nothing: the map is the app's own, the distance is worked out on the
/// phone, and "Start navigation" hands the drive to the phone's Google Maps
/// app. No Routes API call is made, so no credit is used.
///
/// The figures are an estimate and say so. A straight line is stretched by a
/// mountain-road factor, and the time assumes an average hill speed.
class HotelDirectionsScreen extends StatefulWidget {
  const HotelDirectionsScreen({required this.stay, super.key});

  final HotelStay stay;

  @override
  State<HotelDirectionsScreen> createState() => _HotelDirectionsScreenState();
}

class _HotelDirectionsScreenState extends State<HotelDirectionsScreen> {
  final UdMapController _map = UdMapController();
  LatLng? _me;
  bool _locating = true;
  String? _locationProblem;

  /// Roads here wind; a straight line under-states the drive by about this.
  static const double _roadFactor = 1.35;

  /// Average speed on AJK roads, mixing town and mountain stretches.
  static const double _averageKmh = 35;

  LatLng get _hotel => LatLng(widget.stay.latitude, widget.stay.longitude);

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationProblem = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on location to see how far the hotel is.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is off.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      final me = LatLng(position.latitude, position.longitude);
      setState(() {
        _me = me;
        _locating = false;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _map.fitBounds([me, _hotel], padding: 80),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationProblem = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  double? get _roadKm {
    final me = _me;
    if (me == null) return null;
    final metres = Geolocator.distanceBetween(
        me.latitude, me.longitude, _hotel.latitude, _hotel.longitude);
    return metres / 1000 * _roadFactor;
  }

  Duration? get _drive {
    final km = _roadKm;
    if (km == null) return null;
    return Duration(minutes: math.max(1, (km / _averageKmh * 60).round()));
  }

  String _driveLabel(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (hours == 0) return '~$minutes min';
    return minutes == 0 ? '~$hours h' : '~$hours h $minutes';
  }

  /// "Leave by 10:50 AM" — only when the arrival is still ahead.
  String? get _leaveBy {
    final drive = _drive;
    final time = widget.stay.arrivalTime;
    if (drive == null || time == null) return null;
    final parts = time.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (hour == null || minute == null) return null;
    final d = widget.stay.checkIn;
    final arrive = DateTime(d.year, d.month, d.day, hour, minute);
    final leave = arrive.subtract(drive);
    if (leave.isBefore(DateTime.now())) return null;
    final sameDay = DateUtils.isSameDay(leave, DateTime.now());
    final when = sameDay
        ? DateFormat('h:mm a').format(leave)
        : DateFormat('EEE d MMM, h:mm a').format(leave);
    return 'Leave by $when to reach on time.';
  }

  bool _openingRide = false;

  /// The same ride flow as Home: the customer picks the vehicle, drivers send
  /// their fares, and the customer confirms the one they like.
  ///
  /// This used to open the old all-in-one route screen ("Choose your ride"),
  /// which had its own fare table and did not match the ride Home books.
  Future<void> _bookRide() async {
    if (_openingRide) return;
    final me = _me;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pehle aap ki location chahiye — location on kar ke dobara try karein.'),
      ));
      return;
    }
    setState(() => _openingRide = true);
    // The road route, so the fares are priced on the road and not on the
    // straight line. Without one, the next screen falls back to its own
    // straight-line estimate.
    final result = await RouteRepository().route(origin: me, destination: _hotel);
    if (!mounted) return;
    setState(() => _openingRide = false);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VehicleChoiceScreen(
          pickupLabel: 'Current location',
          destinationLabel: widget.stay.hotelName,
          pickupPoint: me,
          destinationPoint: _hotel,
          route: result.best,
          routes: result.routes,
          service: HomeService.car,
          bookingType: BookingType.wholeVehicle,
          seats: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final km = _roadKm;
    final drive = _drive;
    final leaveBy = _leaveBy;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: UdMap(
              controller: _map,
              initialCenter: _hotel,
              zoom: 11,
              myLocation: me,
              padding: const EdgeInsets.only(bottom: 300, top: 80),
              markers: [
                UdMarker(
                  id: 'hotel',
                  position: _hotel,
                  label: widget.stay.hotelName,
                  hue: UdMarkerHue.navy,
                ),
              ],
              polylines: [
                if (me != null)
                  UdPolyline(
                    id: 'as-the-crow-flies',
                    points: [me, _hotel],
                    color: AppColors.navy,
                    width: 3,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const HotelBackButton(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: AppRadii.all(14),
                          boxShadow: AppShadows.card,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.apartment_rounded,
                                size: 18, color: AppColors.navy),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.stay.hotelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.small.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.primary,
                                ),
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
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: AppShadows.floating,
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.borderStrong,
                          borderRadius: AppRadii.all(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_locating)
                      const SizedBox(
                        height: 64,
                        child: Center(
                          child:
                              CircularProgressIndicator(color: AppColors.navy),
                        ),
                      )
                    else if (km == null || drive == null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: AppRadii.all(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _locationProblem ??
                                    'Your location is not available.',
                                style: AppType.small.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppText.primary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _locate,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              label: 'DISTANCE',
                              value: km < 10
                                  ? '${km.toStringAsFixed(1)} km'
                                  : '${km.round()} km',
                              dark: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Stat(
                              label: 'DRIVE',
                              value: _driveLabel(drive),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Stat(
                              label: 'ARRIVE BY',
                              value: hotelTimeLabel(widget.stay.arrivalTime)
                                  .replaceAll(':00', ''),
                            ),
                          ),
                        ],
                      ),
                    if (!_locating && km != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${leaveBy ?? ''}${leaveBy == null ? '' : ' '}'
                        'Approximate — mountain roads vary.',
                        style: AppType.caption.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: HotelOutlineButton(
                            label: 'Call hotel',
                            icon: Icons.call_rounded,
                            onPressed: () =>
                                callHotel(context, widget.stay.contactPhone),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: HotelOutlineButton(
                            label: _openingRide ? 'Khul raha hai…' : 'Book a UDrive ride',
                            onPressed: _bookRide,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    HotelPrimaryButton(
                      label: 'Start navigation',
                      icon: Icons.navigation_rounded,
                      onPressed: () => navigateToHotel(
                        context,
                        widget.stay.latitude,
                        widget.stay.longitude,
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.dark = false});

  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? AppColors.navy : AppColors.surface,
        borderRadius: AppRadii.all(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.brand : AppText.secondary,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppType.h3.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: dark ? AppText.onInk : AppText.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
