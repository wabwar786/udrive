class EligibleRatingBooking {
  const EligibleRatingBooking({required this.bookingId,required this.bookingReference,required this.otherPartyName,required this.role,required this.pickupAt,required this.totalAmount,required this.alreadyRated});
  final String bookingId,bookingReference,otherPartyName,role;final DateTime pickupAt;final double totalAmount;final bool alreadyRated;
  factory EligibleRatingBooking.fromJson(Map<String,dynamic> j)=>EligibleRatingBooking(bookingId:j['bookingId'].toString(),bookingReference:j['bookingReference'].toString(),otherPartyName:j['otherPartyName']?.toString()??'Udrive user',role:j['role']?.toString()??'',pickupAt:DateTime.parse(j['pickupAt'].toString()).toLocal(),totalAmount:(j['totalAmount'] as num?)?.toDouble()??0,alreadyRated:j['alreadyRated']==true);
}
class DisputeCaseItem {
  const DisputeCaseItem({required this.id,required this.caseReference,required this.category,required this.priority,required this.subject,required this.description,required this.status,required this.version,required this.createdAt,this.bookingId,this.bookingReference,this.resolutionSummary});
  final String id,caseReference,category,priority,subject,description,status;final int version;final DateTime createdAt;final String? bookingId,bookingReference,resolutionSummary;
  factory DisputeCaseItem.fromJson(Map<String,dynamic> j)=>DisputeCaseItem(id:j['id'].toString(),caseReference:j['caseReference'].toString(),category:j['category'].toString(),priority:j['priority'].toString(),subject:j['subject'].toString(),description:j['description'].toString(),status:j['status'].toString(),version:(j['version'] as num?)?.toInt()??1,createdAt:DateTime.parse(j['createdAt'].toString()).toLocal(),bookingId:j['bookingId']?.toString(),bookingReference:j['bookingReference']?.toString(),resolutionSummary:j['resolutionSummary']?.toString());
}
