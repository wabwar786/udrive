class RideRequest {
  const RideRequest({
    required this.customer,
    required this.route,
    required this.offer,
    required this.distance,
    required this.passengers,
    required this.time,
    required this.type,
  });

  final String customer;
  final String route;
  final String distance;
  final String time;
  final String type;
  final int offer;
  final int passengers;
}

class DriverPackage {
  const DriverPackage({
    required this.title,
    required this.route,
    required this.price,
    required this.status,
    required this.days,
    required this.bookings,
  });

  final String title;
  final String route;
  final String status;
  final int price;
  final int days;
  final int bookings;
}
