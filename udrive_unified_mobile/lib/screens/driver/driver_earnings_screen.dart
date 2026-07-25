import 'package:flutter/material.dart';

import '../../core/auth/session_store.dart';
import '../../core/booking/driver_finance_repository.dart';
import '../../core/network/api_client.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  late final DriverFinanceRepository _repository;
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = DriverFinanceRepository(ApiClient(SessionStore()));
    _load();
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
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
