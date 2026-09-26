import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../../models/tour_operation_models.dart';
import 'live_driver_package_bookings_screen.dart';

/// D-32 — boarding, departure and live tour progress, with D-33's bookings
/// and manifests behind the second segment.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class TourOperationsScreen extends StatefulWidget {
  const TourOperationsScreen({super.key});

  @override
  State<TourOperationsScreen> createState() => _TourOperationsScreenState();
}

class _TourOperationsScreenState extends State<TourOperationsScreen> {
  /// Was a `TabController` driving a `TabBar` on a navy card — Material's own
  /// underline indicator, in Material's own type. The design has a segmented
  /// control, which is a plain index, so the ticker went with it.
  int _tab = 0;

  List<TourOperationLive> _operations = const [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tour operations',
                style: AppType.h1.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage boarding, departure, live tour progress and passenger '
                'manifests.',
                style:
                    AppType.body.copyWith(height: 1.45, color: AppText.secondary),
              ),
              const SizedBox(height: 16),
              UdSegmented(
                options: const ['Operations', 'Bookings & manifest'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
        Expanded(
          // IndexedStack, not a TabBarView: both halves poll their own
          // endpoint on first build, and keeping them alive means switching
          // back does not re-fetch what is already on screen.
          child: IndexedStack(
            index: _tab,
            children: [
              RefreshIndicator(
                onRefresh: _load,
                color: AppColors.navy,
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
          Center(
            child: CircularProgressIndicator(color: AppColors.navy),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 8, AppSizes.sidePadding, 40),
        children: [
          UdEmptyState(
            icon: Icons.cloud_off_rounded,
            tone: UdTone.err,
            title: 'Could not load operations',
            text: _error,
            action: UdButton.outline(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              expand: false,
              onPressed: _load,
            ),
          ),
        ],
      );
    }
    if (_operations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 8, AppSizes.sidePadding, 40),
        children: const [
          UdEmptyState(
            icon: Icons.tour_outlined,
            title: 'No departures yet',
            text: 'Approved packages appear here once they have a departure.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 0, AppSizes.sidePadding, 40),
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

/// One departure, and the one thing to do to it next.
class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation, required this.onStatus});

  final TourOperationLive operation;
  final ValueChanged<String> onStatus;

  /// Every status was the same blue pill. Where a tour is in its day is the
  /// whole point of this card, so the four states differ.
  static UdTone _tone(String status) => switch (status) {
        'Completed' => UdTone.ok,
        'InProgress' || 'Departed' => UdTone.lime,
        'Boarding' => UdTone.warn,
        'Cancelled' => UdTone.err,
        _ => UdTone.info,
      };

  static String _spaced(String status) => switch (status) {
        'InProgress' => 'In Progress',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final next = switch (operation.status) {
      'Scheduled' => 'Boarding',
      'Boarding' => 'Departed',
      'Departed' => 'InProgress',
      'InProgress' => 'Completed',
      _ => null,
    };

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  operation.packageTitle,
                  style: AppType.h3.copyWith(color: AppText.primary),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(
                label: _spaced(operation.status),
                tone: _tone(operation.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('d MMM yyyy · hh:mm a').format(operation.departureAt),
            style: AppType.listTitle
                .copyWith(fontSize: 15, color: AppText.primary),
          ),
          const SizedBox(height: 3),
          Text(
            '${operation.vehicle} · ${operation.registrationNumber}',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 16),

          // Four numbers, each over its label — the design's stat row. They
          // used to be four grey pills reading "5 Bookings", where the number
          // and the word carried the same weight.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: UdStat(
                  value: '${operation.confirmedBookings}',
                  label: 'Bookings',
                ),
              ),
              Expanded(
                child: UdStat(
                  value: '${operation.seatsBooked}',
                  label: 'Seats',
                ),
              ),
              Expanded(
                child: UdStat(
                  value: '${operation.checkedInPassengers}',
                  label: 'Checked in',
                ),
              ),
              Expanded(
                child: UdStat(
                  value: '${operation.boardedPassengers}',
                  label: 'Boarded',
                ),
              ),
            ],
          ),

          if (next != null) ...[
            const SizedBox(height: 18),
            UdButton.primary(
              label: _label(next),
              trailingIcon: Icons.arrow_forward_rounded,
              size: UdButtonSize.small,
              onPressed: () => onStatus(next),
            ),
          ],
        ],
      ),
    );
  }

  String _label(String status) => switch (status) {
        'Boarding' => 'Open boarding',
        'Departed' => 'Confirm departure',
        'InProgress' => 'Start tour progress',
        'Completed' => 'Complete tour',
        _ => status,
      };
}
