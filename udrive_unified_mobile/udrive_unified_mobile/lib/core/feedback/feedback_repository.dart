import '../network/api_client.dart';
import '../../models/feedback_models.dart';

class FeedbackRepository{
  FeedbackRepository(this.client);final ApiClient client;
  Future<List<EligibleRatingBooking>> eligible() async{final r=await client.getJson('/api/v1/feedback/eligible-bookings');return (r['data'] as List? ?? const []).map((e)=>EligibleRatingBooking.fromJson(Map<String,dynamic>.from(e as Map))).toList();}
  Future<void> rate({required String bookingId,required int overall,int? driving,int? behaviour,int? cleanliness,int? punctuality,int? communication,String? review})=>client.postJson('/api/v1/feedback/ratings',{'bookingId':bookingId,'overallRating':overall,'drivingRating':driving,'behaviourRating':behaviour,'cleanlinessRating':cleanliness,'punctualityRating':punctuality,'communicationRating':communication,'reviewText':review});
  Future<List<DisputeCaseItem>> cases() async{final r=await client.getJson('/api/v1/feedback/cases/my');return (r['data'] as List? ?? const []).map((e)=>DisputeCaseItem.fromJson(Map<String,dynamic>.from(e as Map))).toList();}
  Future<DisputeCaseItem> createCase({String? bookingId,required String category,required String priority,required String subject,required String description,String? resolution,double? amount}) async{final r=await client.postJson('/api/v1/feedback/cases',{'bookingId':bookingId,'category':category,'priority':priority,'subject':subject,'description':description,'requestedResolution':resolution,'disputedAmount':amount});return DisputeCaseItem.fromJson(Map<String,dynamic>.from(r['data'] as Map));}
}
