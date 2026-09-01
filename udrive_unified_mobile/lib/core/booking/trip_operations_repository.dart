import '../network/api_client.dart';
import '../../models/trip_operations_models.dart';

class TripOperationsRepository {
  const TripOperationsRepository(this.client);final ApiClient client;
  Future<List<DriverTripOffer>> driverOffers() async {final r=await client.getJson('/api/v1/trips/driver/offers');return (r['data'] as List? ?? const []).whereType<Map>().map((x)=>DriverTripOffer.fromJson(Map<String,dynamic>.from(x))).toList();}
  Future<void> respondOffer(String offerId,{required bool accept,String? reason})=>client.putJson('/api/v1/trips/driver/offers/$offerId',{'decision':accept?'Accept':'Reject','rejectionReason':reason});
  Future<List<MobileTrip>> driverTrips()=>_trips('/api/v1/trips/driver/my');
  Future<List<MobileTrip>> customerTrips()=>_trips('/api/v1/trips/customer/my');
  Future<List<MobileTrip>> _trips(String path) async {final r=await client.getJson(path);return (r['data'] as List? ?? const []).whereType<Map>().map((x)=>MobileTrip.fromJson(Map<String,dynamic>.from(x))).toList();}
  Future<void> driverStatus(String bookingId,String status,{String? reason,String? tripOtp})=>client.putJson('/api/v1/trips/$bookingId/driver-status',{'status':status,'reason':reason,'tripOtp':tripOtp});
  Future<void> customerStatus(String bookingId,String status,{String? reason})=>client.putJson('/api/v1/trips/$bookingId/customer-status',{'status':status,'reason':reason});
  Future<TripTracking> tracking(String bookingId) async {final r=await client.getJson('/api/v1/trips/$bookingId/tracking');return TripTracking.fromJson(Map<String,dynamic>.from(r['data'] as Map));}
  Future<Map<String,dynamic>> sendLocation(Map<String,dynamic> point)=>client.postJson('/api/v1/tracking/driver/location',point);

  /// Creates a link that lets someone follow this trip without an account.
  ///
  /// Returns the token only. The server keeps a hash, so a link cannot be
  /// recovered later and re-sent by anyone who reads the database — and it
  /// stops working the moment the trip ends, which is what makes it safe to
  /// put in a family group chat.
  Future<String> createTrackingLink(String bookingId,{int expiresInMinutes=180}) async {
    final r = await client.postJson(
      '/api/v1/tracking/$bookingId/link',
      {'expiresInMinutes': expiresInMinutes},
    );
    final data = r['data'];
    return data is Map ? '${data['token'] ?? ''}' : '';
  }
}
