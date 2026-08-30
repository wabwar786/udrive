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
    required this.recommendedFare,
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

  /// What UDrive suggests paying. The customer can go above or below it: the
  /// whole point of the model is that they name a price and drivers answer.
  final int recommendedFare;

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
        recommendedFare: recommendedFare,
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
  Future<List<VehicleOption>> optionsFor({
    required double distanceKm,
    required int durationMinutes,
    required bool perSeat,
    required int seats,
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

          final perKm = _toDouble(
                perSeat ? rate['perSeatRate'] : rate['wholeVehicleRate'],
              ) ??
              entry.fallbackPerKm;

          // Distance is the bulk of it; the time component keeps a short trip
          // through heavy traffic from being priced as though it were quick.
          var fare = perKm * distanceKm + durationMinutes * 2.0;
          if (perSeat) fare *= seats;
          fare = fare.clamp(entry.minimumFare.toDouble(), 500000.0);

          return VehicleOption(
            category: entry.category,
            label: entry.label,
            description: entry.description,
            seats: entry.seats,
            icon: entry.icon,
            recommendedFare: _round(fare),
            service: entry.service,
          );
        })
        .where((option) => !perSeat || option.seats > 5)
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
  static const List<_CatalogueEntry> _catalogue = [
    _CatalogueEntry(
      category: 'Bike',
      label: 'Bike',
      description: 'One passenger, quickest through traffic',
      seats: 1,
      icon: Icons.two_wheeler_rounded,
      fallbackPerKm: 22,
      minimumFare: 120,
      service: HomeService.bike,
    ),
    _CatalogueEntry(
      category: 'Car',
      label: 'Car',
      description: 'Up to 4 passengers',
      seats: 4,
      icon: Icons.directions_car_rounded,
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
      fallbackPerKm: 62,
      minimumFare: 400,
      service: HomeService.car,
    ),
    _CatalogueEntry(
      category: 'Hiace',
      label: 'Hiace',
      description: 'Up to 12 passengers, luggage space',
      seats: 12,
      icon: Icons.airport_shuttle_rounded,
      fallbackPerKm: 95,
      minimumFare: 1500,
      service: HomeService.bus,
    ),
    _CatalogueEntry(
      category: 'Coaster',
      label: 'Coaster',
      description: 'Up to 22 passengers, groups and tours',
      seats: 22,
      icon: Icons.directions_bus_rounded,
      fallbackPerKm: 135,
      minimumFare: 2500,
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
    required this.fallbackPerKm,
    required this.minimumFare,
    required this.service,
  });

  final String category;
  final String label;
  final String description;
  final int seats;
  final IconData icon;
  final double fallbackPerKm;
  final int minimumFare;
  final HomeService service;
}
