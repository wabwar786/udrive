import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/offline_map_models.dart';
import 'offline_map_download_manager.dart';
import 'offline_map_repository.dart';
import 'offline_map_storage.dart';

class OfflineMapController extends ChangeNotifier {
  OfflineMapController(this.repository):storage=OfflineMapStorage(){downloads=OfflineMapDownloadManager(storage);}
  final OfflineMapRepository repository;final OfflineMapStorage storage;late final OfflineMapDownloadManager downloads;
  List<OfflineMapPack> packs=[];List<OfflineMapLocalRecord> local=[];bool loading=true;String? error;int usedBytes=0;int? freeBytes;
  static const _manifestKey='offline_map_manifest_cache_v1';
  Future<void> initialize()async{await storage.initialize();await downloads.initialize();downloads.changes.listen((_)async{await refreshLocal();notifyListeners();});await load();}
  Future<void> load()async{loading=true;notifyListeners();try{packs=await repository.manifest();final prefs=await SharedPreferences.getInstance();await prefs.setString(_manifestKey,jsonEncode(packs.map((x)=>x.toJson()).toList()));error=null;}catch(e){error='Latest map manifest could not be loaded.';final prefs=await SharedPreferences.getInstance();final raw=prefs.getString(_manifestKey);if(raw!=null){try{packs=(jsonDecode(raw) as List).whereType<Map>().map((x)=>OfflineMapPack.fromJson(Map<String,dynamic>.from(x))).toList();}catch(_){}}}await refreshLocal();loading=false;notifyListeners();}
  Future<void> refreshLocal()async{local=await storage.records();usedBytes=await storage.usedBytes();freeBytes=await storage.freeBytes();}
  OfflineMapLocalRecord? recordFor(String id)=>local.where((x)=>x.packId==id).firstOrNull;
  bool updateAvailable(OfflineMapPack p){final r=recordFor(p.id);return r!=null&&(r.version!=p.version||r.checksum.toLowerCase()!=p.checksum.toLowerCase());}
  Future<void> delete(String id)async{await storage.delete(id);await refreshLocal();notifyListeners();}
}
