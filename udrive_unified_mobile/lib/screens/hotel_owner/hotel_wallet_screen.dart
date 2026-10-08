import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/hotels/hotel_wallet_repository.dart';
import '../../core/media/image_compressor.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

final _money = NumberFormat('#,##0', 'en_US');
final _day = DateFormat('d MMM');

/// The hotel owner's prepaid wallet: balance, how to top up, and history.
///
/// Commission on each confirmed booking is taken from here. When the balance
/// falls below the Admin's minimum, the owner's hotels are hidden from new
/// customers until a top-up is approved.
class HotelWalletScreen extends StatefulWidget {
  const HotelWalletScreen({super.key});

  @override
  State<HotelWalletScreen> createState() => _HotelWalletScreenState();
}

class _HotelWalletScreenState extends State<HotelWalletScreen> {
  HotelWallet? _wallet;
  String? _error;

  HotelWalletRepository get _repo =>
      HotelWalletRepository(AppControllerScope.of(context).apiClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final wallet = await _repo.load();
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _openTopup() async {
    final wallet = _wallet;
    if (wallet == null) return;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TopupSheet(repo: _repo, wallet: wallet),
    );
    if (sent == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    return Scaffold(
      appBar: AppBar(title: const Text('Hotel wallet')),
      body: wallet == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: AppColors.navy)
                  : Padding(
                      padding: const EdgeInsets.all(AppSizes.sidePadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _load, child: const Text('Dobara koshish')),
                        ],
                      ),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 12, AppSizes.sidePadding, 40),
                children: [
                  if (!wallet.visible) ...[
                    _Banner(
                      wash: AppTint.danger,
                      border: AppTint.dangerBorder,
                      ink: AppTint.dangerDeep,
                      text: 'Wallet khatam — naye customers ko aap ka hotel nazar '
                          'nahi aa raha. Top-up karein; approve hote hi hotel phir dikhega.',
                    ),
                    const SizedBox(height: 12),
                  ] else if (wallet.low) ...[
                    _Banner(
                      wash: AppTint.warning,
                      border: AppTint.warningBorder,
                      ink: AppTint.warningText,
                      text: 'Wallet kam hai (Rs ${_money.format(wallet.lowBalanceAlert)} se kam). '
                          'Waqt par top-up karein.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: AppRadii.all(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Balance',
                            style: AppType.caption.copyWith(color: AppColors.onInkMuted)),
                        const SizedBox(height: 4),
                        Text('Rs ${_money.format(wallet.balance)}',
                            style: AppType.h1.copyWith(color: AppText.onInk)),
                        const SizedBox(height: 4),
                        Text(
                          wallet.commissionPercentage > 0
                              ? 'Har booking par ${_pct(wallet.commissionPercentage)}% commission is se katti hai'
                              : 'Abhi booking par commission nahi',
                          style: AppType.caption.copyWith(color: AppColors.brand),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            foregroundColor: AppColors.navy,
                          ),
                          onPressed: _openTopup,
                          child: const Text('+ Top-up karein'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top-up ka tareeqa',
                            style: AppType.listTitle.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          wallet.easypaisaNumber == null
                              ? 'EasyPaisa number abhi set nahi — support se poochein.'
                              : 'EasyPaisa ${wallet.easypaisaNumber}'
                                  '${wallet.easypaisaName == null ? '' : ' (${wallet.easypaisaName})'} '
                                  'par bhejein, phir "Top-up karein" mein amount, transaction id '
                                  'aur screenshot dein. Admin approve kare to balance mein aa jata hai.',
                          style: AppType.small,
                        ),
                        if (wallet.easypaisaNumber != null)
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: wallet.easypaisaNumber!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Number copy ho gaya.')));
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Number copy'),
                          ),
                      ],
                    ),
                  ),
                  if (wallet.topups.any((t) => t.status != 'Approved')) ...[
                    const SizedBox(height: 16),
                    Text('Top-ups',
                        style: AppType.section.copyWith(color: AppText.primary)),
                    const SizedBox(height: 8),
                    for (final t in wallet.topups.where((t) => t.status != 'Approved'))
                      _Row(
                        title: 'Top-up Rs ${_money.format(t.amount)}',
                        sub: t.status == 'Pending'
                            ? '${_day.format(t.createdAt)} · admin dekh raha hai'
                            : '${_day.format(t.createdAt)} · reject${t.adminNotes == null ? '' : ' — ${t.adminNotes}'}',
                        amount: t.status == 'Pending' ? 'INTEZAR' : 'REJECT',
                        ink: t.status == 'Pending' ? AppTint.warningText : AppTint.dangerText,
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text('History', style: AppType.section.copyWith(color: AppText.primary)),
                  const SizedBox(height: 8),
                  if (wallet.entries.isEmpty)
                    Text('Abhi kuch nahi.', style: AppType.small)
                  else
                    for (final e in wallet.entries)
                      _Row(
                        title: e.description,
                        sub: _day.format(e.createdAt),
                        amount: '${e.amount < 0 ? '−' : '+'} ${_money.format(e.amount.abs())}',
                        ink: e.amount < 0 ? AppTint.dangerText : AppTint.successText,
                      ),
                ],
              ),
            ),
    );
  }
}

String _pct(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

class _TopupSheet extends StatefulWidget {
  const _TopupSheet({required this.repo, required this.wallet});

  final HotelWalletRepository repo;
  final HotelWallet wallet;

  @override
  State<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<_TopupSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  PlatformFile? _screenshot;
  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final file = await ImageCompressor.shrink(files.first);
    if (mounted) setState(() => _screenshot = file);
  }

  Future<void> _send() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    if (amount <= 0) {
      _say('Jitni raqam bheji woh likhein.');
      return;
    }
    setState(() => _sending = true);
    try {
      final message = await widget.repo.topup(
          amount: amount, reference: _reference.text, screenshot: _screenshot);
      if (!mounted) return;
      _say(message);
      Navigator.of(context).pop(true);
    } catch (error) {
      _say('$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSizes.sidePadding, 16, AppSizes.sidePadding,
          16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Top-up karein', style: AppType.h3.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            widget.wallet.easypaisaNumber == null
                ? 'Paisa bhejne ke baad yahan tafseel dein.'
                : 'EasyPaisa ${widget.wallet.easypaisaNumber} par bhejne ke baad yahan tafseel dein.',
            style: AppType.small,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Raqam (PKR)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reference,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Transaction ID', counterText: ''),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _sending ? null : _pick,
            icon: Icon(_screenshot == null ? Icons.add_photo_alternate_outlined : Icons.check_rounded, size: 18),
            label: Text(_screenshot == null ? 'Screenshot lagayein' : 'Screenshot laga diya — badlein'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Bhejein'),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.wash, required this.border, required this.ink, required this.text});

  final Color wash;
  final Color border;
  final Color ink;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: AppRadii.all(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Text(text, style: AppType.small.copyWith(color: ink)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.sub, required this.amount, required this.ink});

  final String title;
  final String sub;
  final String amount;
  final Color ink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _Card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.small.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(sub, style: AppType.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(amount, style: AppType.small.copyWith(fontWeight: FontWeight.w800, color: ink)),
            ],
          ),
        ),
      );
}

/// The wallet line on the hotel dashboard: balance, opens the wallet.
class HotelWalletLink extends StatefulWidget {
  const HotelWalletLink({super.key});

  @override
  State<HotelWalletLink> createState() => _HotelWalletLinkState();
}

class _HotelWalletLinkState extends State<HotelWalletLink> {
  HotelWallet? _wallet;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final wallet =
          await HotelWalletRepository(AppControllerScope.of(context).apiClient).load();
      if (mounted) setState(() => _wallet = wallet);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    if (wallet == null) return const SizedBox.shrink();
    final bad = !wallet.visible;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: AppRadii.all(14),
        onTap: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const HotelWalletScreen()));
          await _load();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: bad ? AppTint.danger : AppColors.background,
            borderRadius: AppRadii.all(14),
            border: Border.all(color: bad ? AppTint.dangerBorder : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: bad ? AppTint.dangerText : AppColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bad
                      ? 'Wallet khatam — hotel nazar nahi aa raha. Top-up karein'
                      : 'Wallet · Rs ${_money.format(wallet.balance)}',
                  style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800,
                      color: bad ? AppTint.dangerDeep : AppText.primary),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
