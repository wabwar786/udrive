/// What the driver offer card is allowed to show.
///
/// Ratings and ride counts are off by default, and that is the whole reason
/// these are settings rather than code. A new platform has no ratings — so
/// "★ 0.00" and "0 rides" sit beside every driver, and a zero next to a name
/// reads as *a bad driver* rather than a new one. Worse than showing nothing.
///
/// They go on when the numbers start meaning something, without a release.
class OfferCardFields {
  const OfferCardFields({
    this.vehiclePhoto = true,
    this.driverPhoto = true,
    this.rating = false,
    this.rides = false,
    this.plate = true,
  });

  final bool vehiclePhoto;
  final bool driverPhoto;
  final bool rating;
  final bool rides;
  final bool plate;

  /// The last answer from the server, or the defaults above.
  ///
  /// Static because the card is built inside a list during `build`, where an
  /// async read is not available — and because the answer is the same for every
  /// card on the screen.
  static OfferCardFields current = const OfferCardFields();

  static OfferCardFields fromJson(Map<String, dynamic> json) => OfferCardFields(
        vehiclePhoto: json['vehiclePhoto'] != false,
        driverPhoto: json['driverPhoto'] != false,
        // These two default to *false* when absent, the opposite of the
        // others: a missing answer should leave a rating hidden rather than
        // showing a zero nobody asked for.
        rating: json['rating'] == true,
        rides: json['rides'] == true,
        plate: json['plate'] != false,
      );
}
