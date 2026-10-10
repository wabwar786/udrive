import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/maps/ud_map.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// Drag the map until the pin sits on the hotel's gate. Pops with the point.
///
/// Replaces the latitude / longitude boxes the old hotel form had: nobody
/// knows their hotel's coordinates, and a wrong pin sends every UDrive pickup
/// to the wrong place.
class HotelPinScreen extends StatefulWidget {
  const HotelPinScreen({this.initial, super.key});

  final LatLng? initial;

  /// Muzaffarabad, when the hotel has no pin yet.
  static const LatLng fallback = LatLng(34.3700, 73.4700);

  @override
  State<HotelPinScreen> createState() => _HotelPinScreenState();
}

class _HotelPinScreenState extends State<HotelPinScreen> {
  final _controller = UdMapController();
  late LatLng _point = widget.initial ?? HotelPinScreen.fallback;
  bool _locating = false;
  String? _problem;

  Future<void> _myLocation() async {
    setState(() {
      _locating = true;
      _problem = null;
    });
    String? problem;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        problem = 'Location band hai. On karein, ya map khench kar pin lagayein.';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          problem = 'Location ki ijazat nahi. Map khench kar pin lagayein.';
        } else {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
          final here = LatLng(position.latitude, position.longitude);
          await _controller.moveTo(here, zoom: AppConfig.pickupZoom);
          _point = here;
        }
      }
    } catch (_) {
      problem = 'Location nahi mili. Map khench kar pin lagayein.';
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(title: 'Hotel ki location', onBack: () => Navigator.pop(context)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: UdMap(
                    controller: _controller,
                    initialCenter: _point,
                    zoom: AppConfig.pickupZoom,
                    minZoom: 5,
                    onCameraIdle: (center) => _point = center,
                  ),
                ),
                // The pin is fixed in the middle; the map moves under it.
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 44),
                      child: Icon(Icons.location_on_rounded, size: 48, color: AppColors.navy),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: UdButton.soft(
                    label: 'Meri location',
                    icon: Icons.my_location_rounded,
                    size: UdButtonSize.small,
                    expand: false,
                    busy: _locating,
                    onPressed: _locating ? null : _myLocation,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.sidePadding, 12, AppSizes.sidePadding, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Map khench kar pin hotel ke gate par rakhein.',
                      style: AppType.small.copyWith(color: AppText.secondary)),
                  if (_problem != null) ...[
                    const SizedBox(height: 8),
                    UdBanner(tone: UdTone.warn, icon: Icons.location_off_outlined, text: _problem),
                  ],
                  const SizedBox(height: 10),
                  UdButton.primary(
                    label: 'Yahi location hai',
                    icon: Icons.check_rounded,
                    onPressed: () => Navigator.pop(context, _point),
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
