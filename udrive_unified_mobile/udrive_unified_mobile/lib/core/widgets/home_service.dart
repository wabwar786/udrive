import 'package:flutter/material.dart';

/// The four services offered on the redesigned Home screen.
///
/// Bus/Car/Bike are vehicle categories; Hotel branches to the hotel search.
/// Tour booking is a separate flag rather than a service — a customer can book
/// a tour with any of the three vehicle types.
enum HomeService { bus, car, bike, hotel, tour }

extension HomeServiceInfo on HomeService {
  String get label => switch (this) {
        HomeService.bus => 'Coster/Hiace',
        HomeService.car => 'Car',
        HomeService.bike => 'Bike',
        HomeService.hotel => 'Hotel',
        HomeService.tour => 'Tour',
      };

  IconData get icon => switch (this) {
        HomeService.bus => Icons.directions_bus_rounded,
        HomeService.car => Icons.directions_car_rounded,
        HomeService.bike => Icons.two_wheeler_rounded,
        HomeService.hotel => Icons.apartment_rounded,
        HomeService.tour => Icons.terrain_rounded,
      };

  /// Caption under the illustration.
  String get heroTitle => switch (this) {
        HomeService.bus => 'Coster / Hiace',
        HomeService.car => 'Car',
        HomeService.bike => 'Bike',
        HomeService.hotel => 'Hotel',
        HomeService.tour => 'Tour',
      };

  String get heroSubtitle => switch (this) {
        HomeService.bus => 'Group travel across Kashmir',
        HomeService.car => 'Comfortable door-to-door rides',
        HomeService.bike => 'Quick and affordable',
        HomeService.hotel => 'Stay near your destination',
        HomeService.tour => 'Multi-day Kashmir trips',
      };

  /// Key the booking flow filters on, matching `_normaliseVehicle` in the
  /// route flow screen. Null for Hotel, which does not list vehicles.
  String? get vehicleFilterKey => switch (this) {
        HomeService.bus => 'coster',
        HomeService.car => 'car',
        HomeService.bike => 'bike',
        HomeService.hotel => null,
        // Tour is not one vehicle category — any tour-enabled vehicle qualifies,
        // so the search filters on availableForTour instead of a category.
        HomeService.tour => null,
      };

  /// Vehicle category sent to the ride-request API. Null for Hotel.
  String? get vehicleCategory => switch (this) {
        HomeService.bus => 'Coster',
        HomeService.car => 'Car',
        HomeService.bike => 'Bike',
        HomeService.hotel => null,
        HomeService.tour => null,
      };

  /// Whether this service puts vehicles on the map.
  bool get isVehicle => this != HomeService.hotel;

  /// Tour searches only vehicles the driver opted into tours.
  bool get isTour => this == HomeService.tour;
}
