import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/auth_models.dart';
import '../../models/tour_operation_models.dart';
import 'live_driver_package_bookings_screen.dart';

class TourOperationsScreen extends StatefulWidget {
  const TourOperationsScreen({super.key});

  @override
  State<TourOperationsScreen> createState() => _TourOperationsScreenState();
}

class _TourOperationsScreenState extends State<TourOperationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<TourOperationLive> _operations = const [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await AppControllerScope.of(context)
          .apiClient
          .getJson('/api/v1/tour-marketplace/driver/operations');
      final raw = response['data'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _operations = raw
            .map((e) => TourOperationLive.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Tour operations could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: PremiumCard(
            color: const Color(0xFF0D4337),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tour operations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Manage boarding, departure, live tour progress and passenger manifests.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TabBar(
                  controller: _tabs,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  tabs: const [
                    Tab(text: 'Operations'),
                    Tab(text: 'Bookings & manifest'),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              RefreshIndicator(
                onRefresh: _load,
                child: _operationsBody(),
              ),
              const LiveDriverPackageBookingsScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _operationsBody() {
    if (_busy) {
      return ListView(
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          PremiumCard(
            child: Column(
              children: [
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      );
    }
    if (_operations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          PremiumCard(
            child: Text(
              'No active package departures yet. Approved packages will appear here.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
      itemCount: _operations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _OperationCard(
        operation: _operations[index],
        onStatus: (status) => _changeStatus(_operations[index], status),
      ),
    );
  }

  Future<void> _changeStatus(TourOperationLive operation, String status) async {
    try {
      await AppControllerScope.of(context).apiClient.putJson(
        '/api/v1/tour-marketplace/driver/operations/${operation.id}/status',
        {
          'status': status,
          'notes': status == 'Cancelled' ? 'Cancelled by Driver.' : null,
          'expectedVersion': operation.version,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tour status changed to $status.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation, required this.onStatus});

  final TourOperationLive operation;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final next = switch (operation.status) {
      'Scheduled' => 'Boarding',
      'Boarding' => 'Departed',
      'Departed' => 'InProgress',
      'InProgress' => 'Completed',
      _ => null,
    };
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  operation.packageTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              StatusPill(label: operation.status, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            DateFormat('dd MMM yyyy · hh:mm a')
                .format(operation.departureAt),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            '${operation.vehicle} · ${operation.registrationNumber}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('${operation.confirmedBookings}', 'Bookings'),
              _metric('${operation.seatsBooked}', 'Seats'),
              _metric('${operation.checkedInPassengers}', 'Checked in'),
              _metric('${operation.boardedPassengers}', 'Boarded'),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onStatus(next),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(_label(next)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F7F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('$value $label',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );

  String _label(String status) => switch (status) {
        'Boarding' => 'Open boarding',
        'Departed' => 'Confirm departure',
        'InProgress' => 'Start tour progress',
        'Completed' => 'Complete tour',
        _ => status,
      };
}
