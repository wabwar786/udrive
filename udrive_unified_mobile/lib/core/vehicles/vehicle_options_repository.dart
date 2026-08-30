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

  /// Whether this vehicle can be sold by the seat.
  ///
  /// Five seats or fewer is a private car: there is nothing spare to share, so
  /// per-seat is not offered and the customer is never shown a choice that
  /// would be refused at booking. The same rule is enforced server-side.
  bool get allowsPerSeat => seats > 5;

  int fareFor({required bool perSeat, required int seats}) =>
      perSeat ? perSeatFare * seats : wholeVehicleFare;

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
  Future<List<VehicleOption>> optionsFor({
    required double distanceKm,
    required int durationMinutes,
  }) async {
    List<Map<String, dynamic>> rates = const [];
    try {
      final response = await api.getJson(
        '/api/v1/catalog/service-rates?serviceType=City',
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
          final rate = rates.firstWhere(
            (row) =>
                '${row['vehicleType'] ?? row['category'] ?? ''}'
                    .toLowerCase()
                    .trim() ==
                entry.category.toLowerCase(),
            orElse: () => const <String, dynamic>{},
          );

          // Distance is the bulk of it; the time component keeps a short trip
          // through heavy traffic from being priced as though it were quick.
          double priced(double perKm, double minimum) =>
              (perKm * distanceKm + durationMinutes * 2.0)
                  .clamp(minimum, 500000.0);

          final wholeKm = _toDouble(rate['wholeVehicleRate']) ??
              entry.fallbackPerKm;
          final whole = priced(wholeKm, entry.minimumFare.toDouble());

          // Per seat falls back to the whole-vehicle price divided by the
          // seats, which is what a driver would charge to break even on a full
          // load — a sensible default when the admin has not set a seat rate.
          final seatKm = _toDouble(rate['perSeatRate']) ??
              (entry.fallbackPerKm / entry.seats * 1.35);
          final perSeatPrice = priced(seatKm, entry.minimumFare / entry.seats);

          return VehicleOption(
            category: entry.category,
            label: entry.label,
            description: entry.description,
            seats: entry.seats,
            icon: entry.icon,
            asset: entry.asset,
            wholeVehicleFare: _round(whole),
            perSeatFare: _round(perSeatPrice),
            service: entry.service,
          );
        })
        .toList(growable: false);
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
      fallbackPerKm: 48,
      minimumFare: 300,
      service: HomeService.car,
    ),
    _CatalogueEntry(
      category: 'AC Car',
      label: 'Car with AC',
      description: 'Up to 4 passengers, air conditioned',
      seats: 4,
      icon: Icons.ac_unit_rounded,
      asset: 'assets/vehicles_photo/private_car_clean.png',
      fallbackPerKm: 62,
      minimumFare: 400,
      service: HomeService.car,
    ),
    _CatalogueEntry(
      category: 'Bike',
      label: 'Bike',
      description: 'One passenger, quickest through traffic',
      seats: 1,
      icon: Icons.two_wheeler_rounded,
      asset: 'assets/vehicles_photo/bike_clean.png',
      fallbackPerKm: 22,
      minimumFare: 120,
      service: HomeService.bike,
    ),
    _CatalogueEntry(
      category: 'Coaster',
      label: 'Coaster',
      description: 'Up to 22 passengers, groups and tours',
      seats: 22,
      icon: Icons.directions_bus_rounded,
      asset: 'assets/vehicles_photo/coaster_clean.png',
      fallbackPerKm: 135,
      minimumFare: 2500,
      service: HomeService.bus,
    ),
    _CatalogueEntry(
      category: 'Hiace',
      label: 'Hiace',
      description: 'Up to 12 passengers, luggage space',
      seats: 12,
      icon: Icons.airport_shuttle_rounded,
      asset: 'assets/vehicles_photo/coaster_clean.png',
      fallbackPerKm: 95,
      minimumFare: 1500,
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
