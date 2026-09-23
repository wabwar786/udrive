import '../../models/offline_map_models.dart';
import '../network/api_client.dart';

class OfflineMapRepository {
  OfflineMapRepository(this.client);
  final ApiClient client;
  Future<List<OfflineMapPack>> manifest() async {
    final response=await client.getJson('/api/v1/offline-maps/manifest',authenticated:false);
    final data=response['data'] as List? ?? const [];
    return data.whereType<Map>().map((x)=>OfflineMapPack.fromJson(Map<String,dynamic>.from(x))).toList();
  }
}
