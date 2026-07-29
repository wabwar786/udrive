import '../network/api_client.dart';
import '../../models/communication_models.dart';
class CommunicationRepository{CommunicationRepository(this.client);final ApiClient client;
 Future<NotificationPage> notifications()async{final r=await client.getJson('/api/v1/notifications');return NotificationPage.fromJson(Map<String,dynamic>.from(r['data'] as Map));}
 Future<void> markRead(String id)=>client.putJson('/api/v1/notifications/$id/read',const {});
 Future<void> markAllRead()=>client.putJson('/api/v1/notifications/read-all',const {});
 Future<List<BookingMessage>> messages(String bookingId)async{final r=await client.getJson('/api/v1/bookings/$bookingId/messages');return (r['data'] as List? ?? const []).map((e)=>BookingMessage.fromJson(Map<String,dynamic>.from(e as Map))).toList();}
 Future<BookingMessage> send(String bookingId,String body)async{final r=await client.postJson('/api/v1/bookings/$bookingId/messages',{'body':body});return BookingMessage.fromJson(Map<String,dynamic>.from(r['data'] as Map));}
}
