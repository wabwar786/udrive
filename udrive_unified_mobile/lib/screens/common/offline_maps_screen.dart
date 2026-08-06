import 'package:flutter/material.dart';

import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/offline_maps/offline_map_controller.dart';
import '../../core/offline_maps/offline_map_repository.dart';
import '../../models/offline_map_models.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({
    super.key,
    this.activeTripMapId,
  });

  final String? activeTripMapId;

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  late final OfflineMapController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OfflineMapController(
      OfflineMapRepository(ApiClient(SessionStore())),
    )..addListener(_handleControllerChanged);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.downloads.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) {
      return '—';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    final decimals = bytes < 10 * 1024 * 1024 ? 1 : 0;
    return '${(bytes / 1024 / 1024).toStringAsFixed(decimals)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
      ),
      body: _controller.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _controller.load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStorageCard(),
                  if (_controller.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _controller.error!,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  const SizedBox(height: 10),
                  ..._controller.packs.map(_buildPackCard),
                ],
              ),
            ),
    );
  }

  Widget _buildStorageCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Storage',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text('Offline maps: ${_formatSize(_controller.usedBytes)}'),
            Text(
              'Available storage: ${_controller.freeBytes == null ? 'Unavailable' : _formatSize(_controller.freeBytes!)}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Downloaded PMTiles files are separate from bookings, trips and account data.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackCard(OfflineMapPack pack) {
    final local = _controller.recordFor(pack.id);
    final task = _controller.downloads.tasks[pack.id];
    final updateAvailable = _controller.updateAvailable(pack);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        pack.region,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    local != null
                        ? (updateAvailable ? 'Update available' : 'Downloaded')
                        : (pack.canDownload ? 'Available' : 'Coming soon'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Version ${pack.version} · ${_formatSize(pack.fileSize)}',
              style: const TextStyle(fontSize: 12),
            ),
            if (local != null)
              Text(
                'Downloaded ${local.downloadedAt.toLocal()} · ${_formatSize(local.fileSize)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            if (task != null &&
                task.state != OfflineMapDownloadState.notDownloaded) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: task.state == OfflineMapDownloadState.validating
                    ? null
                    : task.progress,
              ),
              const SizedBox(height: 5),
              Text(
                '${task.state.name} · ${_formatSize(task.received)} of ${_formatSize(task.total)}',
                style: const TextStyle(fontSize: 11),
              ),
              if (task.error != null)
                Text(
                  task.error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 11,
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (local == null &&
                    pack.canDownload &&
                    task?.state != OfflineMapDownloadState.downloading)
                  FilledButton.icon(
                    onPressed: () => _controller.downloads.download(pack),
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                if (task?.state == OfflineMapDownloadState.downloading)
                  OutlinedButton(
                    onPressed: () => _controller.downloads.pause(pack.id),
                    child: const Text('Pause'),
                  ),
                if (task?.state == OfflineMapDownloadState.paused)
                  FilledButton(
                    onPressed: () => _controller.downloads.resume(pack),
                    child: const Text('Resume'),
                  ),
                if (task?.state == OfflineMapDownloadState.failed)
                  FilledButton(
                    onPressed: () => _controller.downloads.retry(pack),
                    child: const Text('Retry'),
                  ),
                if (task != null &&
                    {
                      OfflineMapDownloadState.downloading,
                      OfflineMapDownloadState.paused,
                      OfflineMapDownloadState.failed,
                    }.contains(task.state))
                  OutlinedButton(
                    onPressed: () => _controller.downloads.cancel(pack.id),
                    child: const Text('Cancel'),
                  ),
                if (local != null && updateAvailable && pack.canDownload)
                  FilledButton(
                    onPressed: () => _controller.downloads.download(pack),
                    child: const Text('Update'),
                  ),
                if (local != null)
                  OutlinedButton.icon(
                    onPressed: () => _deletePack(pack),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
              ],
            ),
            if (!pack.canDownload && local == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Offline map coming soon. Online OpenStreetMap will continue to work.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePack(OfflineMapPack pack) async {
    final active = widget.activeTripMapId == pack.id;
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete ${pack.name}?'),
            content: Text(
              active
                  ? 'This map is being used for an active trip. Deleting it may remove offline access during your journey. Bookings and trip data will remain safe.'
                  : 'Only the PMTiles file and local map metadata will be deleted. Bookings, trips and account data will remain safe.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(active ? 'Keep Map' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(active ? 'Delete Anyway' : 'Delete Map'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldDelete) {
      await _controller.delete(pack.id);
    }
  }
}
