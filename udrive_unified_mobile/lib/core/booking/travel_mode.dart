import 'package:flutter/material.dart';

/// The three ways a customer can travel with UDrive.
///
/// These are the product's differentiators, so they sit on one row on Home
/// rather than being buried behind a toggle: sharing a vehicle by the seat,
/// taking the whole vehicle, and booking a multi-day Kashmir tour.
enum TravelMode { perSeat, wholeVehicle, tour }

extension TravelModeInfo on TravelMode {
  String get label => switch (this) {
        TravelMode.perSeat => 'Per seat',
        TravelMode.wholeVehicle => 'Whole vehicle',
        TravelMode.tour => 'Tour',
      };

  IconData get icon => switch (this) {
        TravelMode.perSeat => Icons.groups_rounded,
        TravelMode.wholeVehicle => Icons.directions_car_rounded,
        TravelMode.tour => Icons.terrain_rounded,
      };

  /// Value sent to the ride-request API as `bookingType`.
  ///
  /// A tour is booked as a whole vehicle — the difference is the advance
  /// payment and the multi-day schedule, not how the seats are sold.
  String get apiBookingType => switch (this) {
        TravelMode.perSeat => 'PerSeat',
        TravelMode.wholeVehicle => 'WholeVehicle',
        TravelMode.tour => 'WholeVehicle',
      };

  bool get isTour => this == TravelMode.tour;

  String get ctaVerb => switch (this) {
        TravelMode.perSeat => 'Find seats',
        TravelMode.wholeVehicle => 'Find',
        TravelMode.tour => 'Find tour vehicle',
      };
}

/// Popular Kashmir destinations offered as one-tap chips in tour mode.
///
/// A starting set, not a catalogue — the tour destination field stays free
/// text, so anywhere reachable can still be typed.
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
