import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../widgets/home_service.dart';

/// One bookable vehicle type, with what it is likely to cost for this trip.
class VehicleOption {
  const VehicleOption({
    required this.category,
    required this.label,
    required this.description,
    required this.seats,
    required this.icon,
    required this.asset,
    required this.wholeVehicleFare,
    required this.perSeatFare,
    required this.wholeVehicleMinimum,
    required this.perSeatMinimum,
    required this.service,
    this.etaMinutes,
    this.availableCount = 0,
  });

  /// Category as the API knows it — sent with the ride request.
  final String category;

  final String label;
  final String description;
  final int seats;
  final IconData icon;

  /// Photograph shown in the picker. The icon is the fallback for anywhere the
  /// image cannot be loaded.
  final String asset;

  /// Suggested price for taking the whole vehicle.
  ///
  /// The customer can go above or below it — the whole point of the model is
  /// that they name a price and drivers answer.
  final int wholeVehicleFare;

  /// Suggested price per seat. Only meaningful when [allowsPerSeat].
  final int perSeatFare;

  /// The lowest whole-vehicle offer this vehicle will accept.
  ///
  /// This is the admin's own `wholeVehicleRate` — a flat floor, not a rate per
  /// kilometre. A trip long enough to price above it is priced on distance;
  /// anything shorter still costs the floor, because a driver does not start
  /// the engine for less.
  final int wholeVehicleMinimum;

  /// The same floor expressed per seat, from `perSeatRate`.
  final int perSeatMinimum;

  /// Whether this vehicle can be sold by the seat.
  ///
  /// Five seats or fewer is a private car: there is nothing spare to share, so
  /// per-seat is not offered and the customer is never shown a choice that
  /// would be refused at booking. The same rule is enforced server-side.
  bool get allowsPerSeat => seats > 5;

  int fareFor({required bool perSeat, required int seats}) =>
      perSeat ? perSeatFare * seats : wholeVehicleFare;

  /// The floor for the fare stepper.
  ///
  /// The customer names the price, but not below what the admin has set: an
  /// offer under this is never answered, and letting it be made only wastes
  /// the customer's time waiting for silence.
  int minimumFor({required bool perSeat, required int seats}) =>
      perSeat ? perSeatMinimum * seats : wholeVehicleMinimum;

  final HomeService service;

  /// From the nearest available vehicle of this type, when one is known.
  final int? etaMinutes;

  final int availableCount;

  VehicleOption copyWith({int? etaMinutes, int? availableCount}) =>
      VehicleOption(
        category: category,
        label: label,
        description: description,
        seats: seats,
        icon: icon,
        asset: asset,
        wholeVehicleFare: wholeVehicleFare,
        perSeatFare: perSeatFare,
        wholeVehicleMinimum: wholeVehicleMinimum,
        perSeatMinimum: perSeatMinimum,
        service: service,
        etaMinutes: etaMinutes ?? this.etaMinutes,
        availableCount: availableCount ?? this.availableCount,
      );
}

/// Builds the vehicle choices for a trip, priced from the admin's own rates.
class VehicleOptionsRepository {
  VehicleOptionsRepository(this.api);

  final ApiClient api;

  /// Rounds to the nearest 5 rupees.
  ///
  /// A recommended fare of "PKR 1,217" implies a precision the estimate does
  /// not have, and nobody negotiates in single rupees.
  static int _round(double value) => (value / 5).round() * 5;

  /// Fetches the admin-configured rates and turns them into priced options.
  ///
  /// Falls back to built-in rates if the endpoint is unavailable, because a
  /// customer with no prices cannot book at all — and a rough number they can
  /// adjust is far better than an empty screen.
  /// Every vehicle, priced both ways.
  ///
  /// Both figures are computed up front so switching between per seat and whole
  /// vehicle is instant and costs no request — the customer is comparing, and
  /// a spinner between the two would make comparison feel expensive.
  /// [pickupLatitude] and [pickupLongitude] decide which of the admin's pricing
  /// rules applies. A rate set for one town on particular days only reaches the
  /// customer if the server knows where they are standing, so the pickup is
  /// sent with the request. Both null still returns the flat rates.
  Future<List<VehicleOption>> optionsFor({
    required double distanceKm,
    required int durationMinutes,
    double? pickupLatitude,
    double? pickupLongitude,
  }) async {
    List<Map<String, dynamic>> rates = const [];
    try {
      final location = pickupLatitude != null && pickupLongitude != null
          ? '&lat=$pickupLatitude&lng=$pickupLongitude'
          : '';
      final response = await api.getJson(
        '/api/v1/catalog/service-rates?serviceType=City$location',
        authenticated: false,
      );
      final data = response['data'];
      if (data is List) {
        rates = data
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {
      // Fall through to the built-in table.
    }

    return _catalogue
        .map((entry) {
          // The API serialises `ServiceVehicleRateDto` with camelCase names, so
          // the category arrives as `vehicleCategory`. The older keys are still
          // read first for safety, but `vehicleCategory` is the one that
          // actually matches — reading only the old names silently fell through
          // to the built-in table on every single request, which is why the
          // admin's rates never appeared to take effect.
          final rate = rates.firstWhere(
            (row) => _categoryOf(row) == entry.category.toLowerCase(),
            orElse: () => const <String, dynamic>{},
          );

          // Per kilometre is the rate that scales with the trip. `perKmRate`
          // came with the ambulance migration and is what the admin edits;
          // `wholeVehicleRate` and `perSeatRate` are flat floors, not rates,
          // and multiplying either by the distance produced fares in the tens
          // of thousands for an ordinary town trip.
          final perKm = _toDouble(rate['perKmRate']) ?? entry.fallbackPerKm;

          // Floors. The admin's figure wins; the built-in one is only a
          // fallback for a database that has not been migrated.
          final wholeFloor =
              (_toDouble(rate['wholeVehicleRate']) ?? entry.minimumFare.toDouble())
                  .clamp(1.0, 500000.0);
          final seatFloor = (_toDouble(rate['perSeatRate']) ??
                  (entry.minimumFare / entry.seats * 1.35))
              .clamp(1.0, 500000.0);

          // Distance is the bulk of it; the time component keeps a short trip
          // through heavy traffic from being priced as though it were quick.
          final metered = perKm * distanceKm + durationMinutes * 2.0;

          // Never below the floor, and never absurd.
          final whole = metered.clamp(wholeFloor, 500000.0);

          // Per seat is the whole-vehicle price shared across the seats with a
          // small margin — what a driver needs to break even on a full load —
          // and never below the admin's own per-seat floor.
          final perSeatPrice =
              (whole / entry.seats * 1.35).clamp(seatFloor, 500000.0);

          return VehicleOption(
            category: entry.category,
            label: entry.label,
            description: entry.description,
            seats: entry.seats,
            icon: entry.icon,
            asset: entry.asset,
            wholeVehicleFare: _round(whole),
            perSeatFare: _round(perSeatPrice),
            wholeVehicleMinimum: _round(wholeFloor),
            perSeatMinimum: _round(seatFloor),
            service: entry.service,
          );
        })
        .toList(growable: false);
  }

  /// The vehicle category on a rates row, lowercased.
  ///
  /// Checked in the order the API is most likely to send: the current
  /// camelCase serialisation first, then the two names earlier builds looked
  /// for, so a rates payload from an older API still matches.
  static String _categoryOf(Map<String, dynamic> row) {
    for (final key in const ['vehicleCategory', 'vehicleType', 'category']) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value.toLowerCase();
    }
    return '';
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// The vehicle types offered, with fallback pricing.
  ///
  /// Fallback rates are per kilometre in rupees, set to be plausible for Azad
  /// Kashmir rather than precise. They only apply when the rates endpoint
  /// cannot be reached; the admin's own figures win whenever they are
  /// available.
  /// The vehicle types offered, in the order they appear in the picker.
  ///
  /// Order is deliberate and follows demand: Car first because it is most of
  /// the traffic, then Bike, then the two group vehicles.
  ///
  /// Fallback rates are per kilometre in rupees, plausible for Azad Kashmir
  /// rather than precise. They apply only when the rates endpoint cannot be
  /// reached; the admin's own figures win whenever they are available.
  static const List<_CatalogueEntry> _catalogue = [
    _CatalogueEntry(
      category: 'Car',
      label: 'Car',
      description: 'Up to 4 passengers',
      seats: 4,
      icon: Icons.directions_car_rounded,
      asset: 'assets/vehicles_photo/car_clean.png',
      fallbackPerKm: 65,
      minimumFare: 1600,
      service: HomeService.car,
    ),
    _CatalogueEntry(
      category: 'Bike',
      label: 'Bike',
      description: 'One passenger, quickest through traffic',
      seats: 1,
      icon: Icons.two_wheeler_rounded,
      asset: 'assets/vehicles_photo/bike_clean.png',
      fallbackPerKm: 32,
      minimumFare: 250,
      service: HomeService.bike,
    ),
    // Named 'Coster' rather than 'Coaster' because that is the spelling in
    // `udrive.service_vehicle_rates`. The two did not match, so the admin's
    // coaster rate was never found. Driver eligibility does not filter on
    // category, so the rename changes pricing only.
    _CatalogueEntry(
      category: 'Coster',
      label: 'Coster',
      description: 'Up to 22 passengers, groups and tours',
      seats: 22,
      icon: Icons.directions_bus_rounded,
      asset: 'assets/vehicles_photo/coaster_clean.png',
      fallbackPerKm: 160,
      minimumFare: 7500,
      service: HomeService.bus,
    ),
    _CatalogueEntry(
      category: 'Hiace',
      label: 'Hiace',
      description: 'Up to 12 passengers, luggage space',
      seats: 12,
      icon: Icons.airport_shuttle_rounded,
      // Deliberately empty: there is no bundled Hiace photograph, and the
      // coaster one would be a picture of the wrong vehicle on the largest
      // element of the screen. The icon is honest; an admin upload against
      // `vehicle.image.hiace` replaces it.
      asset: '',
      fallbackPerKm: 110,
      minimumFare: 4500,
      service: HomeService.bus,
    ),
  ];
}

class _CatalogueEntry {
  const _CatalogueEntry({
    required this.category,
    required this.label,
    required this.description,
    required this.seats,
    required this.icon,
    required this.asset,
    required this.fallbackPerKm,
    required this.minimumFare,
    required this.service,
  });

  final String category;
  final String label;
  final String description;
  final int seats;
  final IconData icon;
  final String asset;
  final double fallbackPerKm;
  final int minimumFare;
  final HomeService service;
}
