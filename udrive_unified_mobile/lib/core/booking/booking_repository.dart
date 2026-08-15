import '../network/api_client.dart';
import '../../models/booking_models.dart';

class BookingRepository {
  BookingRepository(this.client);

  final ApiClient client;

  Future<LiveRideRequest> createRideRequest(Map<String, dynamic> payload) async {
    final response = await client.postJson('/api/v1/bookings/ride-requests', payload);
    return LiveRideRequest.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<List<LiveRideRequest>> getMyRideRequests() async {
    final response = await client.getJson('/api/v1/bookings/ride-requests/my');
    return _list(response, LiveRideRequest.fromJson);
  }

  Future<List<LiveRideRequest>> getDriverRideRequests() async {
    final response = await client.getJson('/api/v1/driver/marketplace/ride-requests');
    return _list(response, LiveRideRequest.fromJson);
  }

  Future<List<LiveDriverRideOfferStatus>> getDriverRideOffers() async {
    final response = await client.getJson('/api/v1/driver/marketplace/ride-offers');
    return _list(response, LiveDriverRideOfferStatus.fromJson);
  }

  Future<List<LiveDriverOffer>> getRideOffers(String rideRequestId) async {
    final response = await client.getJson('/api/v1/bookings/ride-requests/$rideRequestId/offers');
    return _list(response, LiveDriverOffer.fromJson);
  }

  Future<void> rejectDriverRideRequest({
    required String rideRequestId,
    String? reason,
  }) async {
    await client.postJson(
      '/api/v1/driver/marketplace/ride-requests/$rideRequestId/reject',
      {'reason': reason},
    );
  }

  Future<LiveDriverOffer> submitDriverOffer({
    required String rideRequestId,
    required String vehicleId,
    required double amount,
    required int estimatedArrivalMinutes,
    String? message,
  }) async {
    final response = await client.postJson(
      '/api/v1/driver/marketplace/ride-requests/$rideRequestId/offers',
      {
        'vehicleId': vehicleId,
        'amount': amount,
        'estimatedArrivalMinutes': estimatedArrivalMinutes,
        'message': message,
      },
    );
    return LiveDriverOffer.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<void> declineDriverOffer({
    required String rideRequestId,
    required String offerId,
  }) async {
    await client.postJson(
      '/api/v1/bookings/ride-requests/$rideRequestId/offers/$offerId/decline',
      const {},
    );
  }

  Future<LiveBooking> selectDriverOffer({
    required String rideRequestId,
    required String offerId,
    double advanceAmount = 0,
  }) async {
    final response = await client.postJson(
      '/api/v1/bookings/ride-requests/$rideRequestId/offers/$offerId/select',
      {'advanceAmount': advanceAmount},
    );
    return LiveBooking.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<List<LiveBooking>> getDriverPackageBookings({String? packageId}) async {
    final suffix = packageId == null ? '' : '?packageId=$packageId';
    final response = await client.getJson('/api/v1/driver/marketplace/packages/bookings$suffix');
    return _list(response, LiveBooking.fromJson);
  }

  Future<List<LiveBooking>> getMyBookings() async {
    final response = await client.getJson('/api/v1/bookings/my');
    return _list(response, LiveBooking.fromJson);
  }

  Future<LiveBooking> cancelBooking(String bookingId, String reason) async {
    final response = await client.postJson(
      '/api/v1/bookings/$bookingId/cancel',
      {'reason': reason},
    );
    return LiveBooking.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LiveBooking> rescheduleBooking({
    required String bookingId,
    required DateTime pickupAt,
    DateTime? returnAt,
    String? reason,
  }) async {
    final response = await client.putJson(
      '/api/v1/bookings/$bookingId/reschedule',
      {
        'pickupAt': pickupAt.toUtc().toIso8601String(),
        'returnAt': returnAt?.toUtc().toIso8601String(),
        'reason': reason,
      },
    );
    return LiveBooking.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<List<LiveTourPackage>> getPublicPackages({int? minimumSeats}) async {
    final suffix = minimumSeats == null ? '' : '?minimumSeats=$minimumSeats';
    final response = await client.getJson('/api/v1/packages$suffix', authenticated: false);
    return _list(response, LiveTourPackage.fromJson);
  }

  Future<LivePackageVehicleLocation> getPackageVehicleLocation(
    String packageId,
  ) async {
    final response = await client.getJson(
      '/api/v1/packages/$packageId/vehicle-location',
    );
    return LivePackageVehicleLocation.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  Future<List<LiveTourPackage>> getDriverPackages() async {
    final response = await client.getJson('/api/v1/driver/marketplace/packages');
    return _list(response, LiveTourPackage.fromJson);
  }

  Future<LiveTourPackage> createDriverPackage(Map<String, dynamic> payload) async {
    final response = await client.postJson('/api/v1/driver/marketplace/packages', payload);
    return LiveTourPackage.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LiveTourPackage> submitDriverPackage(String packageId) async {
    final response = await client.postJson('/api/v1/driver/marketplace/packages/$packageId/submit', const {});
    return LiveTourPackage.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LiveTourPackage> toggleDriverPackage(String packageId, bool active) async {
    final action = active ? 'activate' : 'pause';
    final response = await client.postJson('/api/v1/driver/marketplace/packages/$packageId/$action', const {});
    return LiveTourPackage.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LivePackageHold> acquirePackageHold({
    required String packageId,
    required String bookingType,
    required int seats,
  }) async {
    final response = await client.postJson(
      '/api/v1/packages/$packageId/holds',
      {'bookingType': bookingType, 'seats': seats},
    );
    return LivePackageHold.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LiveBooking> confirmPackageBooking({
    required String packageId,
    required String holdId,
    required double advanceAmount,
    List<Map<String, dynamic>> passengers = const [],
  }) async {
    final response = await client.postJson(
      '/api/v1/packages/$packageId/bookings',
      {
        'holdId': holdId,
        'advanceAmount': advanceAmount,
        'passengers': passengers,
      },
    );
    return LiveBooking.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LivePackageWaitlist> joinPackageWaitlist({
    required String packageId,
    required String bookingType,
    required int seats,
    String? notes,
  }) async {
    final response = await client.postJson(
      '/api/v1/packages/$packageId/waitlist',
      {
        'bookingType': bookingType,
        'seats': seats,
        'notes': notes,
      },
    );
    return LivePackageWaitlist.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  Future<List<LivePackageWaitlist>> getCustomerPackageWaitlist() async {
    final response = await client.getJson('/api/v1/packages/waitlist/my');
    return _list(response, LivePackageWaitlist.fromJson);
  }

  Future<List<LivePackageWaitlist>> getDriverPackageWaitlist() async {
    final response = await client.getJson(
      '/api/v1/driver/marketplace/packages/waitlist',
    );
    return _list(response, LivePackageWaitlist.fromJson);
  }

  Future<LivePassengerManifest> getPassengerManifest(
    String bookingId,
  ) async {
    final response = await client.getJson(
      '/api/v1/driver/marketplace/bookings/$bookingId/passengers',
    );
    return LivePassengerManifest.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  Future<LivePackageOffer> createPackageOffer({
    required String packageId,
    required String bookingType,
    required int seats,
    required double amount,
    String? message,
  }) async {
    final response = await client.postJson(
      '/api/v1/packages/$packageId/offers',
      {
        'bookingType': bookingType,
        'seats': seats,
        'offeredAmount': amount,
        'message': message,
      },
    );
    return LivePackageOffer.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<List<LivePackageOffer>> getCustomerPackageOffers() async {
    final response = await client.getJson('/api/v1/packages/offers/my');
    return _list(response, LivePackageOffer.fromJson);
  }

  Future<List<LivePackageOffer>> getDriverPackageOffers() async {
    final response = await client.getJson('/api/v1/driver/marketplace/packages/offers');
    return _list(response, LivePackageOffer.fromJson);
  }

  Future<LivePackageOffer> reviewPackageOffer({
    required String offerId,
    required String decision,
    double? counterAmount,
    String? message,
  }) async {
    final response = await client.putJson(
      '/api/v1/driver/marketplace/packages/offers/$offerId',
      {
        'decision': decision,
        'counterAmount': counterAmount,
        'message': message,
      },
    );
    return LivePackageOffer.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LiveBooking> confirmPackageOffer({
    required String offerId,
    double advanceAmount = 0,
    List<Map<String, dynamic>> passengers = const [],
  }) async {
    final response = await client.postJson(
      '/api/v1/packages/offers/$offerId/confirm',
      {
        'advanceAmount': advanceAmount,
        'passengers': passengers,
      },
    );
    return LiveBooking.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<LiveTourInterest> createTourInterest(Map<String, dynamic> payload) async {
    final response = await client.postJson('/api/v1/tour-interests', payload);
    return LiveTourInterest.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<List<LiveTourInterest>> getTourInterests() async {
    final response = await client.getJson('/api/v1/tour-interests/my');
    return _list(response, LiveTourInterest.fromJson);
  }

  Future<List<LiveTourMatch>> getTourMatches({String? interestId}) async {
    final suffix = interestId == null ? '' : '?interestId=$interestId';
    final response = await client.getJson('/api/v1/tour-interests/matches$suffix');
    return _list(response, LiveTourMatch.fromJson);
  }

  List<T> _list<T>(
    Map<String, dynamic> response,
    T Function(Map<String, dynamic>) factory,
  ) =>
      (response['data'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => factory(Map<String, dynamic>.from(item)))
          .toList();
}
