/// How a driver allows their vehicle to be booked.
///
/// The driver sets this on the vehicle. The customer app then offers only what
/// the vehicle actually supports: a seat-only vehicle can never be booked
/// whole, and a whole-vehicle-only one can never be booked by the seat.
///
/// [wholeVehicle] is the default for a new vehicle, matching the API's
/// `booking_mode` column default.
enum VehicleBookingMode { wholeVehicle, perSeat, both }

extension VehicleBookingModeInfo on VehicleBookingMode {
  /// Value exchanged with the API.
  String get apiValue => switch (this) {
        VehicleBookingMode.wholeVehicle => 'WholeVehicle',
        VehicleBookingMode.perSeat => 'PerSeat',
        VehicleBookingMode.both => 'Both',
      };

  String get label => switch (this) {
        VehicleBookingMode.wholeVehicle => 'Whole vehicle booking',
        VehicleBookingMode.perSeat => 'Per-seat booking',
        VehicleBookingMode.both => 'Both',
      };

  String get description => switch (this) {
        VehicleBookingMode.wholeVehicle =>
          'Customers book your entire vehicle for the trip. This is the default.',
        VehicleBookingMode.perSeat =>
          'Customers book individual seats and travel with others.',
        VehicleBookingMode.both =>
          'Customers choose either the whole vehicle or a single seat.',
      };

  bool get allowsWholeVehicle => this != VehicleBookingMode.perSeat;
  bool get allowsPerSeat => this != VehicleBookingMode.wholeVehicle;

  /// Parses whatever the API sends, defaulting to whole-vehicle so an unknown
  /// or missing value never accidentally opens per-seat booking.
  static VehicleBookingMode fromApi(String? value) {
    final needle = (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return switch (needle) {
      'perseat' || 'seat' || 'seats' => VehicleBookingMode.perSeat,
      'both' || 'either' || 'any' => VehicleBookingMode.both,
      _ => VehicleBookingMode.wholeVehicle,
    };
  }
}
