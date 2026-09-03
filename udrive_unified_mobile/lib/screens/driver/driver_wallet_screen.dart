import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

/// The Driver's prepaid commission balance.
///
/// The arrangement: the Driver sends money to the company, an Admin confirms it
/// arrived, and the balance is credited. Ten percent of every completed booking
/// comes out of it. When it runs out, new requests stop arriving.
///
/// The balance is the largest thing on the screen because it is the only thing
/// a Driver opens this screen to find out.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  Map<String, dynamic>? _wallet;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static String _money(num value) =>
      NumberFormat('#,###').format(value.round());

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

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add funds',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Send the amount by EasyPaisa, then enter it here with the '
                  'transaction ID and a screenshot. Your balance is credited '
                  'once the office confirms the money arrived.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppText.secondary,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppText.primary),
                  decoration: const InputDecoration(
                    labelText: 'Amount sent',
                    prefixText: 'PKR ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  style: const TextStyle(color: AppText.primary),
                  decoration: const InputDecoration(
                    labelText: 'EasyPaisa transaction ID',
                    // This is what the office matches against the company
                    // statement. Asked for as its own field rather than left
                    // to be read off a screenshot.
                    helperText: 'From your EasyPaisa receipt',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['jpg', 'jpeg', 'png'],
                      withData: true,
                    );
                    if (picked == null || picked.files.isEmpty) return;
                    setSheet(() => screenshot = picked.files.single);
                  },
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(
                    screenshot == null
                        ? 'Attach the screenshot'
                        : screenshot!.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final value = double.tryParse(amount.text.trim());
                    if (value == null || value <= 0) return;
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('Submit for confirmation'),
                ),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    final balance = (wallet?['balance'] as num?)?.toDouble() ?? 0;
    final canDrive = wallet?['canReceiveRides'] == true;
    final percentage = (wallet?['commissionPercentage'] as num?)?.toDouble() ?? 10;
    final topups = (wallet?['topups'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final charges = (wallet?['recentCharges'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Wallet')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sending ? null : _addFunds,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add funds'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.all(AppRadii.panel),
                      border: Border.all(
                        color: canDrive ? AppColors.border : AppColors.danger,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Balance',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppText.secondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // The only large number on the screen. It is the one
                        // thing a Driver opens this screen to find out.
                        Text(
                          'PKR ${_money(balance)}',
                          style: TextStyle(
                            fontSize: 44,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.6,
                            color: canDrive
                                ? AppColors.secondary
                                : AppColors.danger,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          canDrive
                              ? 'You are receiving ride requests. '
                                  '${percentage.round()}% of each completed trip '
                                  'comes out of this balance.'
                              : 'Requests have stopped. Add funds to start '
                                  'receiving rides again — any trip you are on '
                                  'now will finish normally.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: canDrive
                                ? AppText.secondary
                                : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12.5),
                    ),
                  ],

                  if (topups.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _SectionLabel('Your payments'),
                    for (final topup in topups)
                      _Row(
                        title: 'PKR ${_money((topup['amount'] as num?) ?? 0)}',
                        subtitle: [
                          '${topup['method'] ?? ''}',
                          if ('${topup['senderReference'] ?? ''}'.isNotEmpty)
                            '${topup['senderReference']}',
                        ].join('  ·  '),
                        trailing: '${topup['status'] ?? ''}',
                        trailingColour: switch ('${topup['status']}') {
                          'Approved' => AppColors.success,
                          'Rejected' => AppColors.danger,
                          _ => AppColors.warning,
                        },
                        note: '${topup['adminNotes'] ?? ''}',
                      ),
                  ],

                  if (charges.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _SectionLabel('Commission taken'),
                    for (final charge in charges)
                      _Row(
                        title:
                            'PKR ${_money(((charge['amount'] as num?) ?? 0).abs())}',
                        subtitle: '${charge['description'] ?? ''}',
                        trailing: '',
                        trailingColour: AppText.disabled,
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: AppText.disabled,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.trailingColour,
    this.note,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color trailingColour;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final hasNote = (note ?? '').trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.row),
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing.isNotEmpty)
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: trailingColour,
                  ),
                ),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 7),
            // The reviewer's own words. A rejected payment with no reason
            // leaves a Driver who has genuinely sent money with nowhere to go.
            Text(
              note!.trim(),
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
