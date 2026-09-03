import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/booking/driver_finance_repository.dart';
import '../../core/booking/trip_chat_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  late final DriverFinanceRepository _repository;
  Map<String, dynamic>? _data;

  /// Rating, trip count, month total and what passengers wrote.
  ///
  /// This lives here rather than on the dashboard. It is worth reading, but not
  /// while a ride request is coming in — the dashboard's job is the next ride.
  DriverDashboard? _dashboard;

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = DriverFinanceRepository(ApiClient(SessionStore()));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboard());
  }

  Future<void> _loadDashboard() async {
    final controller = AppControllerScope.of(context);
    final dashboard =
        await TripChatRepository(controller.apiClient).driverDashboard();
    if (!mounted || dashboard == null) return;
    setState(() => _dashboard = dashboard);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      final result = await _repository.load();
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _pkr(dynamic value) => 'PKR ${_number(value).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final rawWallet = _data?['wallet'];
    final wallet = rawWallet is Map
        ? Map<String, dynamic>.from(rawWallet)
        : <String, dynamic>{};
    final rawEntries = _data?['entries'];
    final entries = rawEntries is List
        ? rawEntries
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
        : <Map<String, dynamic>>[];

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Earnings & wallet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (_dashboard != null) ...[
              _DriverRecord(dashboard: _dashboard!),
              const SizedBox(height: 16),
            ],
            if (_busy && _data == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            if (_data != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available balance'),
                      const SizedBox(height: 6),
                      Text(
                        _pkr(wallet['availableBalance']),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pending\n${_pkr(wallet['pendingBalance'])}',
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Paid\n${_pkr(wallet['paidBalance'])}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : () => _requestPayout(wallet),
                icon: const Icon(Icons.account_balance),
                label: const Text('Request payout'),
              ),
              const SizedBox(height: 18),
              const Text(
                'Wallet activity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if (entries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No wallet activity is available yet.'),
                  ),
                )
              else
                ...entries.map(
                  (entry) => Card(
                    child: ListTile(
                      leading: Icon(
                        _number(entry['amount']) >= 0
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                      title: Text(entry['description']?.toString() ?? 'Wallet entry'),
                      subtitle: Text(
                        '${entry['entryType'] ?? ''} • ${entry['createdAt'] ?? ''}',
                      ),
                      trailing: Text(
                        _pkr(entry['amount']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestPayout(Map<String, dynamic> wallet) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request payout'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (PKR)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (amount == null || amount <= 0) return;
    setState(() => _busy = true);
    try {
      final rawVersion = wallet['version'];
      final version = rawVersion is int
          ? rawVersion
          : int.tryParse('$rawVersion') ?? 1;
      await _repository.requestPayout(
        amount: amount,
        method: 'BankTransfer',
        version: version,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payout request submitted')),
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}


/// The Driver's own record: month, lifetime, rating, and recent reviews.
///
/// Moved off the dashboard, where it pushed the next ride below the fold. A
/// Driver comes here to study; on the home screen they are working.
class _DriverRecord extends StatelessWidget {
  const _DriverRecord({required this.dashboard});

  final DriverDashboard dashboard;

  static String _money(num value) =>
      NumberFormat('#,###').format(value.round());

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This month',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'PKR ${_money(dashboard.earnedThisMonth)}',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.7,
                        color: Color(0xFF148A5A),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Rides completed',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${dashboard.completedTrips}',
                    style: const TextStyle(fontSize: 17, color: AppColors.navy),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 11),

          Row(
            children: [
              // Never a default score. A driver nobody has rated is shown as
              // such, because "5.0" that nobody gave is worse than a blank.
              if (dashboard.rating != null) ...[
                const Icon(Icons.star_rounded,
                    size: 17, color: Color(0xFFF5A524)),
                const SizedBox(width: 4),
                Text(
                  dashboard.rating!.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 14, color: AppColors.navy),
                ),
                const SizedBox(width: 5),
                Text(
                  'from ${dashboard.ratingCount} passengers',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ] else
                const Text(
                  'No ratings yet',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
            ],
          ),

          if (dashboard.recentReviews.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final review in dashboard.recentReviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 1; i <= 5; i++)
                            Icon(
                              i <= review.rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 12,
                              color: const Color(0xFFF5A524),
                            ),
                          const SizedBox(width: 7),
                          Text(
                            review.reviewerFirstName,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                      if (review.text != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          review.text!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
