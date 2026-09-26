class UserNotification {
  const UserNotification({required this.id,required this.type,required this.title,required this.body,required this.isRead,required this.createdAt,this.actionPath});
  final String id,type,title,body;final bool isRead;final DateTime createdAt;final String? actionPath;
  factory UserNotification.fromJson(Map<String,dynamic> j)=>UserNotification(id:'${j['id']}',type:'${j['type']}',title:'${j['title']}',body:'${j['body']}',isRead:j['isRead']==true,createdAt:DateTime.tryParse('${j['createdAt']}')??DateTime.now(),actionPath:j['actionPath']?.toString());
}
class NotificationPage {const NotificationPage(this.items,this.unreadCount);final List<UserNotification> items;final int unreadCount;factory NotificationPage.fromJson(Map<String,dynamic> j)=>NotificationPage((j['items'] as List? ?? const []).map((e)=>UserNotification.fromJson(Map<String,dynamic>.from(e as Map))).toList(),(j['unreadCount'] as num?)?.toInt()??0);}

// `BookingMessage` used to live here, for the second chat system that
// `BookingChatScreen` talked to. Both are gone — one chat per trip now, and it
// uses TripMessage from the trip chat repository.
