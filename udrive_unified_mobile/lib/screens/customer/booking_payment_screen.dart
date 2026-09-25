import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/session_store.dart';
import '../../core/booking/payment_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// What a booking still owes, and what has been paid against it — screen C-08.
class BookingPaymentScreen extends StatefulWidget {
  const BookingPaymentScreen({
    super.key,
    required this.bookingId,
    required this.bookingReference,
  });

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
    setState(() {
      _busy = true;
      _error = null;
    });
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
        ? (s['payments'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final remaining = _num(s['remainingAmount']);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UdTopBar(
            title: 'Payment · ${widget.bookingReference}',
            divider: true,
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 18, AppSizes.sidePadding, 28),
                children: [
                  if (_busy && _summary == null)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),

                  if (_error != null) ...[
                    UdBanner(
                      tone: UdTone.err,
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      trailing: UdButton(
                        label: 'Retry',
                        variant: UdButtonVariant.ghost,
                        size: UdButtonSize.xs,
                        expand: false,
                        busy: _busy,
                        onPressed: _load,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  if (_summary != null) ...[
                    // The one navy hero this screen spends, and the one place
                    // lime is used as ink rather than as a surface — 13.5:1 on
                    // navy, which is the pairing the palette is built around.
                    UdCard(
                      tone: UdCardTone.navy,
                      radius: AppRadii.largeCard,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Remaining balance',
                            style: AppType.body2
                                .copyWith(color: AppText.onInkMuted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _money(remaining),
                            style: AppType.price
                                .copyWith(color: AppColors.brand),
                          ),
                          const SizedBox(height: 18),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.navyLine,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: UdStat(
                                  value: _money(s['totalAmount']),
                                  label: 'Total',
                                  onDark: true,
                                ),
                              ),
                              Expanded(
                                child: UdStat(
                                  value: _money(s['paidAmount']),
                                  label: 'Paid',
                                  onDark: true,
                                ),
                              ),
                              Expanded(
                                child: UdStat(
                                  value: _money(s['refundedAmount']),
                                  label: 'Refunded',
                                  onDark: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    UdButton.primary(
                      label: 'Make payment',
                      icon: Icons.payments_rounded,
                      // Nothing owed, nothing to pay. Unchanged from before —
                      // the button simply looks like what it already was.
                      onPressed: remaining <= 0 || _busy ? null : _pay,
                    ),
                    const SizedBox(height: 14),
                    const UdBanner(
                      icon: Icons.info_outline_rounded,
                      text: 'Cash is confirmed by the driver. Bank transfer, '
                          'Easypaisa and JazzCash are marked confirmed once '
                          'the transfer has been checked.',
                    ),
                    const SizedBox(height: 26),

                    const UdSectionHeader(title: 'Payment history'),
                    const SizedBox(height: 12),

                    if (payments.isEmpty)
                      const UdBanner(
                        icon: Icons.receipt_long_outlined,
                        text: 'No payments recorded yet.',
                      )
                    else
                      UdListGroup(
                        children: [
                          for (final p in payments)
                            UdListRow(
                              leading: const UdIconTile(
                                icon: Icons.receipt_long_outlined,
                                size: UdIconTileSize.sm,
                              ),
                              title: '${p['method']}  ·  ${_money(p['amount'])}',
                              subtitle:
                                  '${p['paymentType']} · ${p['createdAt'] ?? ''}',
                              trailing: _Status(value: '${p['status']}'),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pay() async {
    final remaining = _num(_summary?['remainingAmount']);
    final amountController =
        TextEditingController(text: remaining.toStringAsFixed(0));
    String method = 'Cash';
    String type =
        remaining >= _num(_summary?['totalAmount']) ? 'Full' : 'Balance';

    final result = await showUdDialog<Map<String, dynamic>>(
      context: context,
      title: 'Make payment',
      content: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UdTextField(
              controller: amountController,
              label: 'Amount (PKR)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 14),
            // 'Card' was in this list. There is no card gateway anywhere in
            // the platform, so choosing it recorded a payment that nothing
            // could ever confirm — and the store listing says no card is
            // needed. The remaining methods are all ones the customer
            // genuinely completes outside the app and the office reconciles.
            _DialogDropdown(
              label: 'Payment method',
              value: method,
              options: const ['Cash', 'BankTransfer', 'Easypaisa', 'JazzCash'],
              onChanged: (v) => setLocal(() => method = v),
            ),
            const SizedBox(height: 14),
            _DialogDropdown(
              label: 'Payment type',
              value: type,
              options: const ['Advance', 'Partial', 'Balance', 'Full'],
              onChanged: (v) => setLocal(() => type = v),
            ),
            if (method != 'Cash') ...[
              const SizedBox(height: 14),
              const UdBanner(
                icon: Icons.schedule_rounded,
                text: 'Send the amount using this method, then record it '
                    'here. UDrive marks it confirmed once the transfer is '
                    'checked.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        Builder(
          builder: (ctx) => UdButton.primary(
            label: 'Continue',
            onPressed: () => Navigator.pop(ctx, {
              'amount': double.tryParse(amountController.text),
              'method': method,
              'type': type,
            }),
          ),
        ),
        Builder(
          builder: (ctx) => UdButton.ghost(
            label: 'Cancel',
            size: UdButtonSize.small,
            onPressed: () => Navigator.pop(ctx),
          ),
        ),
      ],
    );

    amountController.dispose();
    final amount = result?['amount'] as double?;
    if (amount == null || amount <= 0 || amount > remaining) return;
    setState(() => _busy = true);
    try {
      await _repo.create(
        bookingId: widget.bookingId,
        method: result!['method'] as String,
        paymentType: result['type'] as String,
        amount: amount,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment initiated successfully.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A labelled dropdown inside the payment dialog, shaped like a [UdTextField]
/// so the three controls read as one form rather than as two styles.
class _DialogDropdown extends StatelessWidget {
  const _DialogDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        UdLabel(label),
        const SizedBox(height: 8),
        Container(
          height: AppSizes.field,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadii.all(AppRadii.field),
            border: Border.all(color: AppColors.borderStrong, width: 1.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              borderRadius: AppRadii.all(AppRadii.field),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppText.secondary),
              style: AppType.listTitle.copyWith(
                fontSize: 16.5,
                color: AppText.primary,
              ),
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (v) => onChanged(v ?? value),
            ),
          ),
        ),
      ],
    );
  }
}

/// The status pill on a payment row.
class _Status extends StatelessWidget {
  const _Status({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final tone = switch (value) {
      'Paid' || 'Verified' => UdTone.ok,
      'Failed' || 'Cancelled' => UdTone.err,
      _ => UdTone.warn,
    };
    return UdBadge(label: value, tone: tone);
  }
}
