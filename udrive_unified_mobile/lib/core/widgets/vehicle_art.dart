import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// Maps free-text vehicle descriptions to bundled, on-brand vehicle
/// illustrations so every ride card shows a real vehicle picture instead of a
/// bare icon. Used across the customer home, packages and booking screens.
enum VehicleArt {
  sedan('assets/vehicles/sedan.png', 'Car', Icons.directions_car_filled_rounded),
  suv('assets/vehicles/suv.png', '4x4 / Jeep', Icons.terrain_rounded),
  van('assets/vehicles/van.png', 'Van', Icons.airport_shuttle_rounded),
  coaster('assets/vehicles/coaster.png', 'Coaster', Icons.directions_bus_filled_rounded),
  bike('assets/vehicles/bike.png', 'Bike', Icons.two_wheeler_rounded),
  rickshaw('assets/vehicles/rickshaw.png', 'Rickshaw', Icons.electric_rickshaw_rounded);

  const VehicleArt(this.asset, this.label, this.icon);

  final String asset;
  final String label;
  final IconData icon;

  /// Best-effort classification from any combination of vehicle name /
  /// title / registration text.
  static VehicleArt from(String text) {
    final t = text.toLowerCase();

    bool has(List<String> keys) => keys.any(t.contains);

    if (has(['rickshaw', 'qingqi', 'qinqi', 'auto', 'three wheel', '3 wheel'])) {
      return VehicleArt.rickshaw;
    }
    if (has(['motorbike', 'motorcycle', 'motor bike', 'scooter', 'bike', 'two wheel', '2 wheel'])) {
      return VehicleArt.bike;
    }
    if (has(['coaster', 'minibus', 'mini bus', 'bus', 'hiace ', 'toyota hiace', 'grand cabin'])) {
      return VehicleArt.coaster;
    }
    if (has(['hiace', 'van', 'carry', 'bolan', 'shuttle'])) {
      return VehicleArt.van;
    }
    if (has([
      'jeep', 'suv', '4x4', '4wd', 'prado', 'land cruiser', 'landcruiser',
      'fortuner', 'vigo', 'revo', 'surf', 'pajero', 'terrain', 'sportage',
      'tucson', 'hilux', 'jimny', 'x-noh', 'kia', 'defender'
    ])) {
      return VehicleArt.suv;
    }
    return VehicleArt.sedan;
  }
}

/// A framed vehicle thumbnail. Prefers a live [imageUrl] (driver-uploaded photo)
/// and falls back to the bundled illustration for the detected category.
class VehicleThumb extends StatelessWidget {
  const VehicleThumb({
    required this.vehicleText,
    this.imageUrl,
    this.size = 64,
    this.radius = 16,
    this.tinted = true,
    super.key,
  });

  final String vehicleText;
  final String? imageUrl;
  final double size;
  final double radius;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final art = VehicleArt.from(vehicleText);
    final url = imageUrl?.trim();
    final Widget fallback = Image.asset(art.asset, fit: BoxFit.contain);

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        gradient: tinted
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF0FAF5), Color(0xFFE7F3FA)],
              )
            : null,
        color: tinted ? null : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }
}

/// A banner-style cover fallback: brand gradient with the detected vehicle
/// illustration centred. Used where a large cover image is expected but the
/// driver hasn't uploaded a photo yet (package cards, detail headers).
class VehicleBanner extends StatelessWidget {
  const VehicleBanner({required this.vehicleText, this.imageUrl, super.key});

  final String vehicleText;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _illustration(),
      );
    }
    return _illustration();
  }

  Widget _illustration() {
    final art = VehicleArt.from(vehicleText);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E6C52), Color(0xFF17B978)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
          child: Image.asset(art.asset, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// Popular Azad Kashmir tourist points shown as pins on the map-first home.
/// Tapping one pre-fills the destination in the booking flow.
class KashmirPlace {
  const KashmirPlace(this.name, this.urdu, this.point, {this.image});
  final String name;
  final String urdu;
  final LatLng point;
  final String? image;
}

class KashmirPlaces {
  KashmirPlaces._();

  /// Map hub – Muzaffarabad, gateway to Azad Kashmir tourism.
  /// `static final` (not const) so it works regardless of whether the
  /// underlying [LatLng] constructor is const in the pinned latlong2 version.
  static final LatLng hub = LatLng(34.3700, 73.4711);

  static final List<KashmirPlace> all = [
    KashmirPlace('Muzaffarabad', 'مظفرآباد', LatLng(34.3700, 73.4711)),
    KashmirPlace('Pir Chinasi', 'پیر چناسی', LatLng(34.3906, 73.5719),
        image: 'assets/images/pir_chinasi.png'),
    KashmirPlace('Neelum Valley', 'وادیِ نیلم', LatLng(34.5880, 73.9080),
        image: 'assets/images/neelum.png'),
    KashmirPlace('Sharda', 'شاردہ', LatLng(34.7908, 74.1800),
        image: 'assets/images/neelum.png'),
    KashmirPlace('Arang Kel', 'اڑنگ کیل', LatLng(34.7960, 74.3540),
        image: 'assets/images/arang_kel.png'),
    KashmirPlace('Rawalakot', 'راولاکوٹ', LatLng(33.8578, 73.7604)),
    KashmirPlace('Banjosa Lake', 'بنجوسہ جھیل', LatLng(33.7680, 73.8520),
        image: 'assets/images/banjosa.png'),
  ];

  /// Deterministic scatter of "live" vehicles around the hub so the map feels
  /// active (mirrors inDrive's nearby-cars view) without a live feed.
  static final List<LatLng> nearbyVehicles = [
    LatLng(34.3792, 73.4620),
    LatLng(34.3641, 73.4805),
    LatLng(34.3755, 73.4890),
    LatLng(34.3588, 73.4600),
    LatLng(34.3830, 73.4740),
    LatLng(34.3660, 73.4520),
    LatLng(34.3720, 73.4970),
  ];
}
