import 'dart:async';
import '../../models/offline_map_models.dart';
import 'offline_map_storage.dart';

class OfflineMapDownloadTask {
  OfflineMapDownloadTask(this.pack);
  final OfflineMapPack pack;
  OfflineMapDownloadState state = OfflineMapDownloadState.failed;
  int received = 0;
  int total = 0;
  String? error = 'Offline map downloads are available in the Android and iOS apps.';
  double get progress => 0;
}

class OfflineMapDownloadManager {
  OfflineMapDownloadManager(this.storage);
  final OfflineMapStorage storage;
  final tasks = <String, OfflineMapDownloadTask>{};
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  bool wifiOnly = true;
  Future<void> initialize() async {}
  Future<void> download(OfflineMapPack pack) async { tasks[pack.id] = OfflineMapDownloadTask(pack); _changes.add(null); }
  Future<void> pause(String packId) async {}
  Future<void> resume(OfflineMapPack pack) => download(pack);
  Future<void> cancel(String packId) async { tasks.remove(packId); _changes.add(null); }
  Future<void> retry(OfflineMapPack pack) => download(pack);
  Future<void> dispose() => _changes.close();
}
