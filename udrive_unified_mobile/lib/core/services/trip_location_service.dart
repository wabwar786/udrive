import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../booking/trip_operations_repository.dart';
import 'service_availability_repository.dart';

class TripLocationService {
  TripLocationService(this.repository);
  final TripOperationsRepository repository;
  final Battery _battery=Battery();
  Timer? _timer;String? _bookingId;String? _status;
  static const _queueKey='phase12_location_queue_v1';

  Future<bool> ensurePermission() async {if(!await Geolocator.isLocationServiceEnabled())return false;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();return p==LocationPermission.always||p==LocationPermission.whileInUse;}
  /// Starts publishing this Driver's position.
  ///
  /// The interval comes from the server, so an admin can turn it without a
  /// release. It was a hard-coded ten seconds, which is far too slow for the
  /// screen it feeds: at 40 km/h a car covers over a hundred metres between
  /// fixes, so the customer watched it jump a block at a time and the arrival
  /// estimate was stale before it finished drawing.
  ///
  /// Fast costs battery and data; slow makes the map jump. Which trade is right
  /// depends on how many drivers are online and what a megabyte costs them —
  /// things that change without a release, so the dial lives where it can be
  /// turned without one. It stops the moment the trip ends.
  Future<void> start(String bookingId,String status) async {_bookingId=bookingId;_status=status;_timer?.cancel();await flushQueue();final seconds=await ServiceAvailabilityRepository(repository.client).trackingPingSeconds();_timer=Timer.periodic(Duration(seconds:seconds),(_)=>capture());await capture();}
  void updateStatus(String status){if(_bookingId!=null&&_status!=status)start(_bookingId!,status);}
  void stop(){_timer?.cancel();_timer=null;_bookingId=null;_status=null;}

  /// Takes one fix and publishes it.
  ///
  /// `bestForNavigation` rather than `high`: `high` is roughly ten metres and
  /// lets the platform smooth and batch readings, which on a moving vehicle
  /// produces a position a second or two behind the car and a heading that lags
  /// corners. That is exactly the wobble that makes a live map look broken.
  ///
  /// The time limit is short because a fix arriving after the next one was due
  /// is worse than no fix at all — it publishes a stale position as current.
  Future<void> capture() async {final booking=_bookingId;if(booking==null)return;try{if(!await ensurePermission())return;final position=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.bestForNavigation,distanceFilter:0,timeLimit:Duration(seconds:6)));final battery=await _battery.batteryLevel;final point=<String,dynamic>{'clientEventId':_eventId(),'tripId':booking,'latitude':position.latitude,'longitude':position.longitude,'accuracy':position.accuracy,'heading':position.heading.isFinite?position.heading:null,'speedKph':position.speed.isFinite?max(0,position.speed*3.6):null,'deviceTimestamp':DateTime.now().toUtc().toIso8601String(),'batteryLevel':battery,'permissionStatus':'granted','source':'flutter-mobile'};await _sendOrQueue(point);}catch(_){}}
  Future<void> _sendOrQueue(Map<String,dynamic> point) async {final connectivity=await Connectivity().checkConnectivity();if(connectivity.every((x)=>x==ConnectivityResult.none)){await _enqueue(point);return;}try{await repository.sendLocation(point);await flushQueue();}catch(_){await _enqueue(point);}}
  Future<void> _enqueue(Map<String,dynamic> point) async {final prefs=await SharedPreferences.getInstance();final current=(prefs.getStringList(_queueKey)??<String>[]);current.add(jsonEncode(point));while(current.length>150)current.removeAt(0);await prefs.setStringList(_queueKey,current);}
  Future<void> flushQueue() async {final prefs=await SharedPreferences.getInstance();final queue=List<String>.from(prefs.getStringList(_queueKey)??const[]);if(queue.isEmpty)return;final remaining=<String>[];for(final raw in queue){try{final point=Map<String,dynamic>.from(jsonDecode(raw) as Map);await repository.sendLocation(point);}catch(_){remaining.add(raw);}}await prefs.setStringList(_queueKey,remaining);}
  String _eventId(){final r=Random.secure();String h(int n)=>List.generate(n,(_)=>r.nextInt(16).toRadixString(16)).join();return '${h(8)}-${h(4)}-4${h(3)}-${(8+r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';}
}
