import 'package:flutter/material.dart';

import '../../data/models.dart';

/// The vehicle categories the platform actually runs, with the seat counts the
/// server prices them at.
///
/// This replaced a list in `data/dummy_data.dart` that invented six categories
/// — Economy, Comfort, SUV, 4×4 Jeep, Hiace, Coaster — each with a made-up
/// `baseFare` between 2,600 and 22,000. Two things were wrong with it, and the
/// second was not cosmetic:
///
///   * The fares were fiction, and the tour booking screen quoted them to the
///     customer as a "Suggested fare" and pre-filled the offer box with one.
///   * Four of the six names do not exist on the server at all, and the fifth
///     was spelled **Coaster** where every rate card says **Coster**. A tour
///     request naming any of them reached an API that had no such category —
///     the same spelling bug that made route-flow quotes fail.
///
/// The names below are the vocabulary in `service_vehicle_rates.vehicle_category`
/// and the seat counts are the ones migration 049 sets. Change them here and
/// nowhere else; a name that drifts from the server silently breaks booking.
///
/// There is deliberately no fare on this type. What a trip costs is decided by
/// the server's quote endpoint for rides, and by the driver for tours. Nothing
/// in the app is entitled to invent a price.
const List<VehicleCategory> vehicleCatalogue = [
  VehicleCategory(
    name: 'Bike',
    icon: Icons.two_wheeler_rounded,
    seats: 1,
    luggage: 1,
    description: 'One rider, light luggage. Quickest through town traffic.',
  ),
  VehicleCategory(
    name: 'Rickshaw',
    icon: Icons.electric_rickshaw_rounded,
    seats: 3,
    luggage: 2,
    description: 'Short local trips at the lowest fare.',
  ),
  VehicleCategory(
    name: 'Car',
    icon: Icons.directions_car_rounded,
    seats: 4,
    luggage: 3,
    description: 'A family or a small group, on sealed and hill roads.',
  ),
  VehicleCategory(
    name: 'Hiace',
    icon: Icons.airport_shuttle_rounded,
    seats: 12,
    luggage: 10,
    description: 'Larger families and tour groups, with room for luggage.',
  ),
  VehicleCategory(
    name: 'Coster',
    icon: Icons.directions_bus_rounded,
    seats: 22,
    luggage: 20,
    description: 'Big groups and per-seat routes across the valleys.',
  ),
];

/// The smallest vehicle that seats everybody, or the largest if nobody fits.
VehicleCategory recommendedVehicleFor(int travellers) {
  for (final vehicle in vehicleCatalogue) {
    if (vehicle.seats >= travellers) return vehicle;
  }
  return vehicleCatalogue.last;
}
