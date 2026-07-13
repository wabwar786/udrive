class DriverOffer {
  const DriverOffer({
    required this.name,
    required this.vehicle,
    required this.rating,
    required this.trips,
    required this.price,
    required this.etaMinutes,
    required this.verified,
  });

  final String name;
  final String vehicle;
  final double rating;
  final int trips;
  final int price;
  final int etaMinutes;
  final bool verified;
}

class TourPackage {
  const TourPackage({
    required this.title,
    required this.route,
    required this.driver,
    required this.days,
    required this.price,
    required this.rating,
    required this.vehicle,
    required this.imageColor,
  });

  final String title;
  final String route;
  final String driver;
  final int days;
  final int price;
  final double rating;
  final String vehicle;
  final int imageColor;
}

class TripRecord {
  const TripRecord({
    required this.route,
    required this.date,
    required this.driver,
    required this.price,
    required this.status,
  });

  final String route;
  final String date;
  final String driver;
  final int price;
  final String status;
}
