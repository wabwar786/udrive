class TourOperationLive {
  const TourOperationLive({
    required this.id,
    required this.tourPackageId,
    required this.packageTitle,
    required this.departureAt,
    required this.status,
    required this.confirmedBookings,
    required this.seatsBooked,
    required this.checkedInPassengers,
    required this.boardedPassengers,
    required this.vehicle,
    required this.registrationNumber,
    required this.version,
    this.returnAt,
  });

  final String id;
  final String tourPackageId;
  final String packageTitle;
  final DateTime departureAt;
  final DateTime? returnAt;
  final String status;
  final int confirmedBookings;
  final int seatsBooked;
  final int checkedInPassengers;
  final int boardedPassengers;
  final String vehicle;
  final String registrationNumber;
  final int version;

  factory TourOperationLive.fromJson(Map<String, dynamic> json) =>
      TourOperationLive(
        id: json['id']?.toString() ?? '',
        tourPackageId: json['tourPackageId']?.toString() ?? '',
        packageTitle: json['packageTitle']?.toString() ?? 'Tour package',
        departureAt: DateTime.parse(json['departureAt'].toString()).toLocal(),
        returnAt: json['returnAt'] == null
            ? null
            : DateTime.parse(json['returnAt'].toString()).toLocal(),
        status: json['status']?.toString() ?? 'Scheduled',
        confirmedBookings: (json['confirmedBookings'] as num?)?.toInt() ?? 0,
        seatsBooked: (json['seatsBooked'] as num?)?.toInt() ?? 0,
        checkedInPassengers:
            (json['checkedInPassengers'] as num?)?.toInt() ?? 0,
        boardedPassengers: (json['boardedPassengers'] as num?)?.toInt() ?? 0,
        vehicle: json['vehicle']?.toString() ?? '',
        registrationNumber: json['registrationNumber']?.toString() ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
      );
}
