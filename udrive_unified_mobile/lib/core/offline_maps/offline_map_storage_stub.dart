import 'package:latlong2/latlong.dart';
import '../../models/offline_map_models.dart';
class OfflineMapStorage {
  Future<void> initialize()=>Future.value();
  Future<List<OfflineMapLocalRecord>> records()=>Future.value(const []);
  Future<int> usedBytes()=>Future.value(0);
  Future<int?> freeBytes()=>Future.value(null);
  Future<OfflineMapResolution> resolve(List<OfflineMapPack> packs,LatLng origin,LatLng destination)=>Future.value(const OfflineMapResolution(source:MapSourceKind.onlineOsm,pack:null,localRecord:null,reason:'Offline maps are unavailable on web.'));
  Future<void> delete(String packId)=>Future.value();
  Future<void> cleanupTemporaryFiles()=>Future.value();
}
