import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// PKR with thousands separators — used by this screen and its rows.
String _money(num value) => NumberFormat('#,###').format(value.round());

/// The Driver's prepaid commission balance.
///
/// The arrangement: the Driver sends money to the company, an Admin confirms it
/// arrived, and the balance is credited. Ten percent of every completed booking
/// comes out of it. When it runs out, new requests stop arriving.
///
/// The balance is the largest thing on the screen because it is the only thing
/// a Driver opens this screen to find out.
///
/// Rendered by `main_shell`, so no `Scaffold` here. It used to carry one,
/// which meant this screen drew two bars every single time — there was no
/// route that reached it any other way.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  Map<String, dynamic>? _wallet;

  /// Where a top-up should be sent, from settings.
  ///
  /// Null until the call returns; the block is simply not drawn until then,
  /// rather than showing an empty box shaped like an answer.
  String? _topupNumber;
  String? _topupName;

  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadTopupAccount();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await AppControllerScope.of(context)
          .apiClient
          .getJson('/api/v1/driver/wallet');
      if (!mounted) return;
      setState(() {
        _wallet = Map<String, dynamic>.from(response['data'] as Map);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _addFunds() async {
    final amount = TextEditingController();
    final reference = TextEditingController();
    PlatformFile? screenshot;

    final submitted = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                'Add funds',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 16),

              // Where to send it, before how to record it.
              //
              // The sheet used to explain the process and then ask for a
              // transaction ID — without ever saying which account to pay.
              // The number lived in a WhatsApp message somewhere, and every
              // driver had to ask for it.
              //
              // It comes from settings rather than the app, because accounts
              // get closed and ownership moves; a number baked into a release
              // means money sent somewhere nobody is watching.
              if (_topupNumber != null && _topupNumber!.isNotEmpty) ...[
                UdCard(
                  tone: UdCardTone.lime,
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded,
                          size: 26, color: AppText.onBrand),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Send EasyPaisa to',
                              style: AppType.caption
                                  .copyWith(color: AppText.onBrand),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _topupNumber!,
                              style: AppType.h2.copyWith(
                                letterSpacing: 0.5,
                                color: AppText.onBrand,
                              ),
                            ),
                            if ((_topupName ?? '').isNotEmpty)
                              Text(
                                _topupName!,
                                style: AppType.small
                                    .copyWith(color: AppText.onBrand),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      UdIconButton(
                        icon: Icons.copy_rounded,
                        tooltip: 'Copy number',
                        iconColor: AppText.onBrand,
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _topupNumber!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Number copied.')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Text(
                'Send the amount to that number, then enter it here with '
                'the transaction ID and a screenshot. Your balance is '
                'credited once the office confirms the money arrived.',
                style: AppType.small
                    .copyWith(height: 1.5, color: AppText.secondary),
              ),
              const SizedBox(height: 20),
              UdTextField(
                controller: amount,
                label: 'Amount sent',
                labelSuffix: 'PKR',
                icon: Icons.payments_rounded,
                hint: '0',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: reference,
                label: 'EasyPaisa transaction ID',
                icon: Icons.tag_rounded,
                // This is what the office matches against the company
                // statement. Asked for as its own field rather than left
                // to be read off a screenshot.
                helper: 'From your EasyPaisa receipt',
              ),
              const SizedBox(height: 16),
              UdButton.outline(
                label: screenshot == null
                    ? 'Attach the screenshot'
                    : screenshot!.name,
                icon: Icons.image_outlined,
                size: UdButtonSize.small,
                onPressed: () async {
                  final picked = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['jpg', 'jpeg', 'png'],
                    withData: true,
                  );
                  if (picked == null || picked.files.isEmpty) return;
                  setSheet(() => screenshot = picked.files.single);
                },
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: 'Submit for confirmation',
                icon: Icons.send_rounded,
                onPressed: () {
                  final value = double.tryParse(amount.text.trim());
                  if (value == null || value <= 0) return;
                  Navigator.pop(sheetContext, true);
                },
              ),
            ],
          ),
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim());
    final ref = reference.text.trim();
    final file = screenshot;
    amount.dispose();
    reference.dispose();

    if (submitted != true || value == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final controller = AppControllerScope.of(context);
      if (file != null) {
        await controller.apiClient.uploadFile(
          '/api/v1/driver/wallet/topups',
          fieldName: 'file',
          file: file,
          fields: {
            'amount': '$value',
            if (ref.isNotEmpty) 'senderReference': ref,
          },
        );
      } else {
        // A top-up with no screenshot is still recorded. Refusing it would
        // strand a Driver who paid at a shop and has only a paper receipt; the
        // office can still match the transaction ID.
        await controller.apiClient.postJson(
          '/api/v1/driver/wallet/topups',
          {'amount': value, 'senderReference': ref.isEmpty ? null : ref},
        );
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sent. Your balance updates once it is confirmed.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Reads the EasyPaisa account drivers pay into.
  Future<void> _loadTopupAccount() async {
    try {
      final controller = AppControllerScope.of(context);
      final response = await controller.apiClient
          .getJson('/api/v1/driver/wallet/topup-account');
      final data = response['data'];
      if (!mounted || data is! Map) return;
      setState(() {
        _topupNumber = '${data['easypaisaNumber'] ?? ''}'.trim();
        _topupName = '${data['accountName'] ?? ''}'.trim();
      });
    } catch (_) {
      // No account on screen is better than a wrong one. The driver can still
      // record a payment they made to a number they already had.
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    final balance = (wallet?['balance'] as num?)?.toDouble() ?? 0;
    final canDrive = wallet?['canReceiveRides'] == true;
    final percentage =
        (wallet?['commissionPercentage'] as num?)?.toDouble() ?? 10;
    final topups = (wallet?['topups'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final charges = (wallet?['recentCharges'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          Text('Wallet', style: AppType.h1.copyWith(color: AppText.primary)),
          const SizedBox(height: 18),

          // The balance, and what it means for whether you are working.
          UdCard(
            tone: canDrive ? UdCardTone.navy : UdCardTone.plain,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance',
                  style: AppType.small.copyWith(
                    color: canDrive ? AppText.onInkMuted : AppText.secondary,
                  ),
                ),
                const SizedBox(height: 6),
                // The only large number on the screen. It is the one
                // thing a Driver opens this screen to find out.
                Text(
                  'PKR ${_money(balance)}',
                  style: AppType.display.copyWith(
                    fontSize: 44,
                    height: 1,
                    letterSpacing: -1.6,
                    color: canDrive ? AppColors.brand : AppTint.dangerText,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  canDrive
                      ? 'You are receiving ride requests. '
                          '${percentage.round()}% of each completed trip '
                          'comes out of this balance.'
                      : 'Requests have stopped. Add funds to start '
                          'receiving rides again — any trip you are on '
                          'now will finish normally.',
                  style: AppType.small.copyWith(
                    height: 1.5,
                    color: canDrive ? AppText.onInkMuted : AppTint.dangerText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // What the wallet actually is, said once. The artboard says it and
          // the screen never did — a driver seeing "Balance PKR 3,450" has no
          // way to know it is money they owe against, not money they are owed.
          UdBanner(
            tone: UdTone.info,
            icon: Icons.info_outline_rounded,
            text: 'Your wallet is a prepaid commission balance — send a '
                'top-up, the office confirms it, and your balance is '
                'credited.',
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.cloud_off_rounded,
              text: _error,
            ),
          ],

          const SizedBox(height: 26),
          UdSectionHeader(
            title: 'Your payments',
            caption: topups.isEmpty ? null : '${topups.length}',
          ),
          const SizedBox(height: 12),
          if (topups.isEmpty)
            const UdEmptyState(
              icon: Icons.receipt_outlined,
              title: 'No top-up yet',
              text: 'Send a payment and record it here; the office confirms '
                  'it and your balance goes up.',
            )
          else
            for (final topup in topups)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PaymentRow(topup: topup),
              ),

          if (charges.isNotEmpty) ...[
            const SizedBox(height: 26),
            UdSectionHeader(
              title: 'Commission taken',
              caption: '${charges.length}',
            ),
            const SizedBox(height: 12),
            UdListGroup(
              children: [
                for (final charge in charges)
                  UdListRow(
                    title: 'PKR '
                        '${_money(((charge['amount'] as num?) ?? 0).abs())}',
                    subtitle: '${charge['description'] ?? ''}',
                    leading: const UdIconTile(
                      icon: Icons.percent_rounded,
                      tone: UdIconTone.neutral,
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 26),
          // Was a floating action button, which v2 does not have — a screen's
          // main action belongs at the end of its content where a thumb
          // reaches it, not floating over the last row.
          UdButton.primary(
            label: 'Add funds',
            icon: Icons.add_rounded,
            busy: _sending,
            onPressed: _sending ? null : _addFunds,
          ),
        ],
      ),
    );
  }
}

/// One top-up the driver has recorded, and what the office said about it.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.topup});

  final Map<String, dynamic> topup;

  @override
  Widget build(BuildContext context) {
    final status = '${topup['status'] ?? ''}';
    final note = '${topup['adminNotes'] ?? ''}'.trim();
    final tone = switch (status) {
      'Approved' => UdTone.ok,
      'Rejected' => UdTone.err,
      _ => UdTone.warn,
    };
    final subtitle = [
      '${topup['method'] ?? ''}',
      if ('${topup['senderReference'] ?? ''}'.isNotEmpty)
        '${topup['senderReference']}',
    ].where((part) => part.trim().isNotEmpty).join('  ·  ');

    return UdCard(
      tone: UdCardTone.flat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PKR ${_money((topup['amount'] as num?) ?? 0)}',
                      style: AppType.listTitle
                          .copyWith(fontSize: 16, color: AppText.primary),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style:
                            AppType.small.copyWith(color: AppText.secondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(label: status, tone: tone),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 12),
            // The reviewer's own words. A rejected payment with no reason
            // leaves a Driver who has genuinely sent money with nowhere to go.
            UdBanner(
              tone: UdTone.err,
              icon: Icons.assignment_late_outlined,
              text: note,
            ),
          ],
        ],
      ),
    );
  }
}
