class RideRequest {
  const RideRequest({required this.customer, required this.route, required this.offer, required this.distance, required this.passengers, required this.time, required this.type});
  final String customer, route, distance, time, type; final int offer, passengers;
}
class DriverPackage {
  const DriverPackage({required this.title, required this.route, required this.price, required this.status, required this.days, required this.bookings});
  final String title, route, status; final int price, days, bookings;
}
