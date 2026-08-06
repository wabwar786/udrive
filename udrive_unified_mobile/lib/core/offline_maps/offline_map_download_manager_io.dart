import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../../models/offline_map_models.dart';
import 'offline_map_storage.dart';

class OfflineMapDownloadTask {
  OfflineMapDownloadTask(this.pack);
  final OfflineMapPack pack;
  OfflineMapDownloadState state=OfflineMapDownloadState.notDownloaded;
  int received=0,total=0;
  String? error;
  double get progress=>total<=0?0:(received/total).clamp(0,1);
}

class OfflineMapDownloadManager {
  OfflineMapDownloadManager(this.storage,{http.Client? client}):_client=client??http.Client();
  final OfflineMapStorage storage;final http.Client _client;
  final tasks=<String,OfflineMapDownloadTask>{};
  final _changes=StreamController<void>.broadcast();
  Stream<void> get changes=>_changes.stream;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool wifiOnly=true;bool _cancelRequested=false;bool _pauseRequested=false;
  Future<void> initialize() async {await storage.initialize();_connectivity=Connectivity().onConnectivityChanged.listen((_){for(final t in tasks.values.where((x)=>x.state==OfflineMapDownloadState.failed&&x.error=='Connection lost')){resume(t.pack);}});}
  Future<void> download(OfflineMapPack pack) async {if(!pack.canDownload)return;final task=tasks.putIfAbsent(pack.id,()=>OfflineMapDownloadTask(pack));_cancelRequested=false;_pauseRequested=false;task..state=OfflineMapDownloadState.queued..error=null;_emit();final free=await storage.freeBytes();const buffer=100*1024*1024;if(free!=null&&free<pack.fileSize+buffer){task..state=OfflineMapDownloadState.failed..error='Not enough storage. Keep at least 100 MB free after download.';_emit();return;}if(wifiOnly){final c=await Connectivity().checkConnectivity();if(!c.contains(ConnectivityResult.wifi)){task..state=OfflineMapDownloadState.failed..error='Wi-Fi is required by your download preference.';_emit();return;}}await _run(task);}
  Future<void> _run(OfflineMapDownloadTask task) async {final part=await storage.partialPath(task.pack);final file=File(part);final existing=await file.exists()?await file.length():0;task..received=existing..total=task.pack.fileSize..state=OfflineMapDownloadState.downloading;_emit();final request=http.Request('GET',Uri.parse(task.pack.fileUrl));if(existing>0)request.headers['Range']='bytes=$existing-';http.StreamedResponse response;try{response=await _client.send(request).timeout(const Duration(seconds:30));}catch(_){task..state=OfflineMapDownloadState.failed..error='Connection lost';_emit();return;}if(response.statusCode!=200&&response.statusCode!=206){task..state=OfflineMapDownloadState.failed..error='Download server returned ${response.statusCode}.';_emit();return;}final sink=file.openWrite(mode:existing>0?FileMode.append:FileMode.write);try{await for(final chunk in response.stream){if(_cancelRequested||_pauseRequested)break;sink.add(chunk);task.received+=chunk.length;_emit();}await sink.flush();await sink.close();if(_cancelRequested){if(await file.exists())await file.delete();task..state=OfflineMapDownloadState.notDownloaded..received=0;_emit();return;}if(_pauseRequested){task.state=OfflineMapDownloadState.paused;_emit();return;}task.state=OfflineMapDownloadState.validating;_emit();await storage.activate(task.pack,part);task..state=OfflineMapDownloadState.downloaded..received=task.pack.fileSize;_emit();}catch(e){await sink.close();task..state=OfflineMapDownloadState.failed..error=e is FormatException?'Downloaded file is incomplete or corrupted.':e.toString();_emit();}}
  Future<void> pause(String packId)async{final t=tasks[packId];if(t?.state==OfflineMapDownloadState.downloading)_pauseRequested=true;}
  Future<void> resume(OfflineMapPack pack)async{_pauseRequested=false;_cancelRequested=false;final t=tasks.putIfAbsent(pack.id,()=>OfflineMapDownloadTask(pack));await _run(t);}
  Future<void> cancel(String packId)async{_cancelRequested=true;final t=tasks[packId];if(t!=null&&t.state!=OfflineMapDownloadState.downloading){final p=await storage.partialPath(t.pack);final f=File(p);if(await f.exists())await f.delete();t..state=OfflineMapDownloadState.notDownloaded..received=0;_emit();}}
  Future<void> retry(OfflineMapPack p)=>download(p);
  void _emit()=>_changes.add(null);
  Future<void> dispose()async{await _connectivity?.cancel();await _changes.close();_client.close();}
}
