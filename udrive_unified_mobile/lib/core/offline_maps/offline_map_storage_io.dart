import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/offline_map_models.dart';

class OfflineMapStorage {
  static const _recordsKey='offline_map_records_v1';
  Directory? _root;
  Future<void> initialize() async {final base=await getApplicationSupportDirectory();_root=Directory('${base.path}${Platform.pathSeparator}offline_maps');if(!await _root!.exists())await _root!.create(recursive:true);await cleanupTemporaryFiles();}
  Future<Directory> get root async {if(_root==null)await initialize();return _root!;}
  Future<List<OfflineMapLocalRecord>> records() async {final prefs=await SharedPreferences.getInstance();final raw=prefs.getString(_recordsKey);if(raw==null||raw.isEmpty)return const[];try{return (jsonDecode(raw) as List).whereType<Map>().map((x)=>OfflineMapLocalRecord.fromJson(Map<String,dynamic>.from(x))).toList();}catch(_){return const[];}}
  Future<void> saveRecords(List<OfflineMapLocalRecord> items) async {final prefs=await SharedPreferences.getInstance();await prefs.setString(_recordsKey,jsonEncode(items.map((x)=>x.toJson()).toList()));}
  Future<int> usedBytes() async => (await records()).fold(0,(a,b)=>a+b.fileSize);
  Future<int?> freeBytes() async {try{final mb=await DiskSpacePlus().getFreeDiskSpace;return mb==null?null:(mb*1024*1024).floor();}catch(_){return null;}}
  Future<String> finalPath(OfflineMapPack p) async=>'${(await root).path}${Platform.pathSeparator}${safe(p.id)}-${safe(p.version)}.pmtiles';
  Future<String> partialPath(OfflineMapPack p) async=>'${await finalPath(p)}.part';
  String safe(String x)=>x.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
  Future<String> sha256File(String path) async => (await sha256.bind(File(path).openRead()).first).toString();
  Future<bool> validateFile(OfflineMapPack pack,String path) async {final f=File(path);if(!await f.exists())return false;if(await f.length()!=pack.fileSize)return false;if(pack.checksum.trim().isEmpty)return false;return (await sha256File(path)).toLowerCase()==pack.checksum.toLowerCase();}
  Future<void> activate(OfflineMapPack pack,String partPath) async {if(!await validateFile(pack,partPath))throw const FormatException('Checksum or file-size validation failed.');final destination=File(await finalPath(pack));if(await destination.exists())await destination.delete();await File(partPath).rename(destination.path);final all=(await records()).where((x)=>x.packId!=pack.id).toList();final now=DateTime.now().toUtc();all.add(OfflineMapLocalRecord(packId:pack.id,version:pack.version,checksum:pack.checksum,filePath:destination.path,fileSize:pack.fileSize,downloadedAt:now,lastUsedAt:now,valid:true));await saveRecords(all);}
  Future<OfflineMapResolution> resolve(List<OfflineMapPack> packs,LatLng origin,LatLng destination) async {final locals=await records();for(final pack in packs){if(!pack.bounds.contains(origin)||!pack.bounds.contains(destination))continue;final matching=locals.where((x)=>x.packId==pack.id&&x.version==pack.version&&x.checksum.toLowerCase()==pack.checksum.toLowerCase()&&x.valid).firstOrNull;if(matching==null)continue;if(await validateFile(pack,matching.filePath)){final updated=locals.map((x)=>x.packId==matching.packId?OfflineMapLocalRecord(packId:x.packId,version:x.version,checksum:x.checksum,filePath:x.filePath,fileSize:x.fileSize,downloadedAt:x.downloadedAt,lastUsedAt:DateTime.now().toUtc(),valid:true):x).toList();await saveRecords(updated);return OfflineMapResolution(source:MapSourceKind.offlineMap,pack:pack,localRecord:matching,reason:'Matching validated offline PMTiles map found.');}await markInvalid(pack.id);}return const OfflineMapResolution(source:MapSourceKind.onlineOsm,pack:null,localRecord:null,reason:'No valid matching offline map is available.');}
  Future<void> markInvalid(String packId) async {final all=await records();await saveRecords(all.map((x)=>x.packId==packId?OfflineMapLocalRecord(packId:x.packId,version:x.version,checksum:x.checksum,filePath:x.filePath,fileSize:x.fileSize,downloadedAt:x.downloadedAt,lastUsedAt:x.lastUsedAt,valid:false):x).toList());}
  Future<void> delete(String packId) async {final all=await records();for(final x in all.where((e)=>e.packId==packId)){final f=File(x.filePath);if(await f.exists())await f.delete();}await saveRecords(all.where((x)=>x.packId!=packId).toList());final dir=await root;await for(final e in dir.list()){if(e is File&&e.path.contains(safe(packId))&&e.path.endsWith('.part'))await e.delete();}}
  Future<void> cleanupTemporaryFiles() async {final dir=await root;final cutoff=DateTime.now().subtract(const Duration(days:7));await for(final e in dir.list()){if(e is File&&e.path.endsWith('.part')){final stat=await e.stat();if(stat.modified.isBefore(cutoff))await e.delete();}}}
}
