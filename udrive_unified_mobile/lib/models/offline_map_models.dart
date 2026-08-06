import 'package:latlong2/latlong.dart';

enum OfflineMapPackStatus { active, inactive }
enum OfflineMapDownloadState { notDownloaded, queued, downloading, paused, validating, downloaded, failed, corrupted, updateAvailable }
enum MapSourceKind { offlineMap, onlineOsm }

class OfflineMapBounds {
  const OfflineMapBounds({required this.southWest, required this.northEast});
  final LatLng southWest;
  final LatLng northEast;
  factory OfflineMapBounds.fromJson(Map<String,dynamic> j) => OfflineMapBounds(
    southWest: _point(Map<String,dynamic>.from(j['southWest'] as Map)),
    northEast: _point(Map<String,dynamic>.from(j['northEast'] as Map)),
  );
  bool contains(LatLng p) => p.latitude >= southWest.latitude && p.latitude <= northEast.latitude && p.longitude >= southWest.longitude && p.longitude <= northEast.longitude;
  Map<String,dynamic> toJson()=>{'southWest':_pointJson(southWest),'northEast':_pointJson(northEast)};
  static LatLng _point(Map<String,dynamic> j)=>LatLng((j['latitude'] as num).toDouble(),(j['longitude'] as num).toDouble());
  static Map<String,dynamic> _pointJson(LatLng p)=>{'latitude':p.latitude,'longitude':p.longitude};
}

class OfflineMapPack {
  const OfflineMapPack({required this.id,required this.name,required this.region,required this.bounds,required this.fileUrl,required this.fileSize,required this.version,required this.checksum,required this.status,this.updatedAt,this.publishedAt,this.minimumAppVersion});
  final String id,name,region,fileUrl,version,checksum;
  final int fileSize;
  final OfflineMapBounds bounds;
  final OfflineMapPackStatus status;
  final DateTime? updatedAt,publishedAt;
  final String? minimumAppVersion;
  bool get canDownload=>status==OfflineMapPackStatus.active&&fileUrl.trim().isNotEmpty&&fileSize>0&&checksum.trim().isNotEmpty;
  factory OfflineMapPack.fromJson(Map<String,dynamic> j)=>OfflineMapPack(
    id:j['id'].toString(),name:j['name'].toString(),region:j['region'].toString(),bounds:OfflineMapBounds.fromJson(Map<String,dynamic>.from(j['bounds'] as Map)),
    fileUrl:j['fileUrl']?.toString()??'',fileSize:(j['fileSize'] as num?)?.toInt()??0,version:j['version']?.toString()??'1.0.0',checksum:j['checksum']?.toString()??'',
    status:j['status']?.toString().toLowerCase()=='active'?OfflineMapPackStatus.active:OfflineMapPackStatus.inactive,
    updatedAt:DateTime.tryParse(j['updatedAt']?.toString()??''),publishedAt:DateTime.tryParse(j['publishedAt']?.toString()??''),minimumAppVersion:j['minimumAppVersion']?.toString());
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'region':region,'bounds':bounds.toJson(),'fileUrl':fileUrl,'fileSize':fileSize,'version':version,'checksum':checksum,'status':status.name,'updatedAt':updatedAt?.toIso8601String(),'publishedAt':publishedAt?.toIso8601String(),'minimumAppVersion':minimumAppVersion};
}

class OfflineMapLocalRecord {
  const OfflineMapLocalRecord({required this.packId,required this.version,required this.checksum,required this.filePath,required this.fileSize,required this.downloadedAt,required this.lastUsedAt,required this.valid});
  final String packId,version,checksum,filePath;
  final int fileSize;
  final DateTime downloadedAt,lastUsedAt;
  final bool valid;
  factory OfflineMapLocalRecord.fromJson(Map<String,dynamic> j)=>OfflineMapLocalRecord(packId:j['packId'].toString(),version:j['version'].toString(),checksum:j['checksum'].toString(),filePath:j['filePath'].toString(),fileSize:(j['fileSize'] as num).toInt(),downloadedAt:DateTime.parse(j['downloadedAt'].toString()),lastUsedAt:DateTime.parse(j['lastUsedAt'].toString()),valid:j['valid']==true);
  Map<String,dynamic> toJson()=>{'packId':packId,'version':version,'checksum':checksum,'filePath':filePath,'fileSize':fileSize,'downloadedAt':downloadedAt.toIso8601String(),'lastUsedAt':lastUsedAt.toIso8601String(),'valid':valid};
}

class OfflineMapResolution {
  const OfflineMapResolution({required this.source,this.pack,this.localRecord,this.reason});
  final MapSourceKind source;
  final OfflineMapPack? pack;
  final OfflineMapLocalRecord? localRecord;
  final String reason;
}
