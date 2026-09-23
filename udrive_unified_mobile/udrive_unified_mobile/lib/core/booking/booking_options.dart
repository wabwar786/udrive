import 'package:flutter/material.dart';

import '../../data/models.dart';

export '../../data/models.dart' show BookingType;

/// Presentation helpers for the existing [BookingType] in `data/models.dart`.
///
/// Tour used to be a third value here. It moved to the service row, because a
/// tour is a different *service* — you pick a tour and then still decide
/// whether you are buying seats or the whole vehicle.
extension BookingTypeInfo on BookingType {
  String get label => switch (this) {
        BookingType.perSeat => 'Per seat',
        BookingType.wholeVehicle => 'Whole vehicle',
      };

  IconData get icon => switch (this) {
        BookingType.perSeat => Icons.groups_rounded,
        BookingType.wholeVehicle => Icons.directions_car_rounded,
      };

  /// Value sent to the ride-request API.
  String get apiValue => switch (this) {
        BookingType.perSeat => 'PerSeat',
        BookingType.wholeVehicle => 'WholeVehicle',
      };
}

/// Seat rules that decide which booking types a vehicle can offer.
class SeatRules {
  const SeatRules._();

  /// A vehicle must seat more than this to be sold by the seat.
  ///
  /// Five or fewer is a private car: splitting it between strangers is not a
  /// product UDrive offers. Enforced again server-side in `BookingService`,
  /// because a client can be out of date or bypassed entirely.
  static const int perSeatMinimumCapacity = 5;

  static bool allowsPerSeat(int passengerCapacity) =>
      passengerCapacity > perSeatMinimumCapacity;

  /// The booking types a vehicle of this size can offer.
  static List<BookingType> availableFor(int passengerCapacity) =>
      allowsPerSeat(passengerCapacity)
          ? BookingType.values
          : const [BookingType.wholeVehicle];
}

/// Popular Kashmir destinations offered as one-tap chips in tour mode.
///
/// A starting set, not a catalogue — the destination field stays free text, so
/// anywhere reachable can still be typed.
class TourDestinations {
  const TourDestinations._();

  static const List<({String name, double latitude, double longitude})> popular =
      [
    (name: 'Neelum Valley', latitude: 34.5900, longitude: 73.9100),
    (name: 'Arang Kel', latitude: 34.7900, longitude: 74.3400),
    (name: 'Banjosa Lake', latitude: 33.7833, longitude: 73.8000),
    (name: 'Sharda', latitude: 34.7900, longitude: 74.1800),
    (name: 'Pir Chinasi', latitude: 34.3667, longitude: 73.5833),
    (name: 'Rawalakot', latitude: 33.8578, longitude: 73.7604),
    (name: 'Toli Peer', latitude: 33.8167, longitude: 73.8833),
  ];

  /// Longest tour a customer can request in one booking.
  static const int maxDays = 7;
}
