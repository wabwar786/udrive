import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../booking/trip_operations_repository.dart';

class TripLocationService {
  TripLocationService(this.repository);
  final TripOperationsRepository repository;
  final Battery _battery=Battery();
  Timer? _timer;String? _bookingId;String? _status;
  static const _queueKey='phase12_location_queue_v1';

  Future<bool> ensurePermission() async {if(!await Geolocator.isLocationServiceEnabled())return false;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();return p==LocationPermission.always||p==LocationPermission.whileInUse;}
  Future<void> start(String bookingId,String status) async {_bookingId=bookingId;_status=status;_timer?.cancel();await flushQueue();const seconds=60;_timer=Timer.periodic(const Duration(seconds:seconds),(_)=>capture());await capture();}
  void updateStatus(String status){if(_bookingId!=null&&_status!=status)start(_bookingId!,status);}
  void stop(){_timer?.cancel();_timer=null;_bookingId=null;_status=null;}

  Future<void> capture() async {final booking=_bookingId;if(booking==null)return;try{if(!await ensurePermission())return;final position=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:12)));final battery=await _battery.batteryLevel;final point=<String,dynamic>{'clientEventId':_eventId(),'tripId':booking,'latitude':position.latitude,'longitude':position.longitude,'accuracy':position.accuracy,'heading':position.heading.isFinite?position.heading:null,'speedKph':position.speed.isFinite?max(0,position.speed*3.6):null,'deviceTimestamp':DateTime.now().toUtc().toIso8601String(),'batteryLevel':battery,'permissionStatus':'granted','source':'flutter-mobile'};await _sendOrQueue(point);}catch(_){}}
  Future<void> _sendOrQueue(Map<String,dynamic> point) async {final connectivity=await Connectivity().checkConnectivity();if(connectivity.every((x)=>x==ConnectivityResult.none)){await _enqueue(point);return;}try{await repository.sendLocation(point);await flushQueue();}catch(_){await _enqueue(point);}}
  Future<void> _enqueue(Map<String,dynamic> point) async {final prefs=await SharedPreferences.getInstance();final current=(prefs.getStringList(_queueKey)??<String>[]);current.add(jsonEncode(point));while(current.length>150)current.removeAt(0);await prefs.setStringList(_queueKey,current);}
  Future<void> flushQueue() async {final prefs=await SharedPreferences.getInstance();final queue=List<String>.from(prefs.getStringList(_queueKey)??const[]);if(queue.isEmpty)return;final remaining=<String>[];for(final raw in queue){try{final point=Map<String,dynamic>.from(jsonDecode(raw) as Map);await repository.sendLocation(point);}catch(_){remaining.add(raw);}}await prefs.setStringList(_queueKey,remaining);}
  String _eventId(){final r=Random.secure();String h(int n)=>List.generate(n,(_)=>r.nextInt(16).toRadixString(16)).join();return '${h(8)}-${h(4)}-4${h(3)}-${(8+r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';}
}
