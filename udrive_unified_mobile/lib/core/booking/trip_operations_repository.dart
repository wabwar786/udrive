import '../network/api_client.dart';
import '../../models/trip_operations_models.dart';

class TripOperationsRepository {
  const TripOperationsRepository(this.client);final ApiClient client;
  Future<List<DriverTripOffer>> driverOffers() async {final r=await client.getJson('/api/v1/trips/driver/offers');return (r['data'] as List? ?? const []).whereType<Map>().map((x)=>DriverTripOffer.fromJson(Map<String,dynamic>.from(x))).toList();}
  Future<void> respondOffer(String offerId,{required bool accept,String? reason})=>client.putJson('/api/v1/trips/driver/offers/$offerId',{'decision':accept?'Accept':'Reject','rejectionReason':reason});
  Future<List<MobileTrip>> driverTrips()=>_trips('/api/v1/trips/driver/my');
  Future<List<MobileTrip>> customerTrips()=>_trips('/api/v1/trips/customer/my');
  Future<List<MobileTrip>> _trips(String path) async {final r=await client.getJson(path);return (r['data'] as List? ?? const []).whereType<Map>().map((x)=>MobileTrip.fromJson(Map<String,dynamic>.from(x))).toList();}
  Future<void> driverStatus(String bookingId,String status,{String? reason})=>client.putJson('/api/v1/trips/$bookingId/driver-status',{'status':status,'reason':reason});
  Future<void> customerStatus(String bookingId,String status,{String? reason})=>client.putJson('/api/v1/trips/$bookingId/customer-status',{'status':status,'reason':reason});
  Future<TripTracking> tracking(String bookingId) async {final r=await client.getJson('/api/v1/trips/$bookingId/tracking');return TripTracking.fromJson(Map<String,dynamic>.from(r['data'] as Map));}
  Future<Map<String,dynamic>> sendLocation(Map<String,dynamic> point)=>client.postJson('/api/v1/tracking/driver/location',point);
}
