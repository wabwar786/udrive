import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/session_store.dart';
import '../../core/booking/payment_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

class BookingPaymentScreen extends StatefulWidget {
  const BookingPaymentScreen({super.key, required this.bookingId, required this.bookingReference});
  final String bookingId;
  final String bookingReference;
  @override
  State<BookingPaymentScreen> createState() => _BookingPaymentScreenState();
}

class _BookingPaymentScreenState extends State<BookingPaymentScreen> {
  late final PaymentRepository _repo;
  Map<String, dynamic>? _summary;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = PaymentRepository(ApiClient(SessionStore()));
    _load();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final value = await _repo.summary(widget.bookingId);
      if (mounted) setState(() => _summary = value);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _num(dynamic v) => double.tryParse('$v') ?? 0;
  String _money(dynamic v) => 'PKR ${NumberFormat('#,##0').format(_num(v))}';

  @override
  Widget build(BuildContext context) {
    final s = _summary ?? const <String, dynamic>{};
    final payments = (s['payments'] is List)
        ? (s['payments'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(title: Text('Payment · ${widget.bookingReference}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_busy && _summary == null) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
            if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('Retry'))]))),
            if (_summary != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Remaining balance', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 5),
                    Text(_money(s['remainingAmount']), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                    const Divider(height: 28),
                    Row(children: [Expanded(child: Text('Total\n${_money(s['totalAmount'])}')), Expanded(child: Text('Paid\n${_money(s['paidAmount'])}')), Expanded(child: Text('Refunded\n${_money(s['refundedAmount'])}'))]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _num(s['remainingAmount']) <= 0 || _busy ? null : _pay, icon: const Icon(Icons.payments_rounded), label: const Text('Make payment')),
              const SizedBox(height: 20),
              const Text('Payment history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (payments.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No payments recorded yet.'))),
              ...payments.map((p) => Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
                title: Text('${p['method']} · ${_money(p['amount'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${p['paymentType']} · ${p['createdAt'] ?? ''}'),
                trailing: _Status(value: '${p['status']}'),
              ))),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pay() async {
    final remaining = _num(_summary?['remainingAmount']);
    final amountController = TextEditingController(text: remaining.toStringAsFixed(0));
    String method = 'Cash';
    String type = remaining >= _num(_summary?['totalAmount']) ? 'Full' : 'Balance';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Make payment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (PKR)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'Payment method'), items: const ['Cash','BankTransfer','Card','Easypaisa','JazzCash'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setLocal(() => method = v ?? method)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: type, decoration: const InputDecoration(labelText: 'Payment type'), items: const ['Advance','Partial','Balance','Full'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setLocal(() => type = v ?? type)),
          if (method != 'Cash') const Padding(padding: EdgeInsets.only(top: 12), child: Text('Online provider confirmation will complete this payment after gateway credentials are configured.', style: TextStyle(fontSize: 12, color: AppColors.muted))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, {'amount': double.tryParse(amountController.text), 'method': method, 'type': type}), child: const Text('Continue'))],
      )),
    );
    amountController.dispose();
    final amount = result?['amount'] as double?;
    if (amount == null || amount <= 0 || amount > remaining) return;
    setState(() => _busy = true);
    try {
      await _repo.create(bookingId: widget.bookingId, method: result!['method'] as String, paymentType: result['type'] as String, amount: amount);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment initiated successfully.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.value});
  final String value;
  @override
  Widget build(BuildContext context) {
    final good = value == 'Paid' || value == 'Verified';
    final bad = value == 'Failed' || value == 'Cancelled';
    final color = good ? Colors.green : bad ? Colors.red : Colors.orange;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)));
  }
}
