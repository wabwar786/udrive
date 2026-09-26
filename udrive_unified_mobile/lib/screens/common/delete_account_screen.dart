import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import 'legal_screen.dart';

/// Self-service account deletion (Google Play "account deletion" policy).
///
/// The person must type DELETE, so the action cannot happen by a stray tap.
/// The server refuses while a ride is live and returns a message we show as-is.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _confirmed => _confirm.text.trim() == 'DELETE';

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_confirmed || _busy) return;
    final controller = AppControllerScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await controller.deleteAccount(reason: _reason.text);
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(content: Text('Your UDrive account has been deleted.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not delete the account. Check your internet and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // A pushed page, so it keeps its own Scaffold and draws its own bar.
      appBar: UdTopBar(
        title: 'Delete account',
        onBack: () => Navigator.maybePop(context),
        divider: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 18, AppSizes.sidePadding, 30),
        children: [
          const UdIconTile(
            icon: Icons.warning_amber_rounded,
            tone: UdIconTone.red,
            size: UdIconTileSize.lg,
          ),
          const SizedBox(height: 16),
          Text(
            'This permanently deletes your UDrive account.',
            style: AppType.h2.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 18),
          // What goes and what stays, before the decision rather than after.
          const UdCard(
            tone: UdCardTone.tint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Point(
                  icon: Icons.delete_outline_rounded,
                  text: 'Deleted now: your name, phone number, email, profile '
                      'photo, trusted contacts, and for drivers the CNIC and '
                      'licence numbers, date of birth, address and payout '
                      'details.',
                ),
                _Point(
                  icon: Icons.logout_rounded,
                  text: 'You are signed out on every device. Your vehicles are '
                      'removed and you stop receiving rides.',
                ),
                _Point(
                  icon: Icons.receipt_long_outlined,
                  text: 'Kept without your name: past trips, payments, wallet '
                      'and commission records, as required for tax, accounting '
                      'and safety investigations.',
                ),
                _Point(
                  icon: Icons.account_balance_wallet_outlined,
                  text: 'Any remaining wallet balance or welcome credit is lost '
                      'and cannot be restored.',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          UdTextField(
            controller: _reason,
            label: 'Why are you leaving?',
            labelSuffix: '(optional)',
            icon: Icons.chat_bubble_outline_rounded,
            enabled: !_busy,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          UdTextField(
            controller: _confirm,
            label: 'Type DELETE to confirm',
            icon: Icons.lock_outline_rounded,
            enabled: !_busy,
            hint: 'DELETE',
            textCapitalization: TextCapitalization.characters,
            helper: 'Typed in capitals, so this cannot happen by a stray tap.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.error_outline_rounded,
              text: _error!,
            ),
          ],
          const SizedBox(height: 22),
          UdButton(
            label: 'Delete my account',
            variant: UdButtonVariant.dangerSolid,
            busy: _busy,
            // Stays disabled until DELETE is typed — unchanged.
            onPressed: _confirmed ? _delete : null,
          ),
          const SizedBox(height: 10),
          UdButton.ghost(
            label: 'Keep my account',
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          const SizedBox(height: 4),
          // Exactly what survives deletion and why. Opens from the copy
          // bundled with the app, so it works on the roadside with no signal.
          UdButton.ghost(
            label: 'What happens to my data?',
            size: UdButtonSize.small,
            onPressed: () => LegalScreen.open(context, 'account-deletion'),
          ),
        ],
      ),
    );
  }
}

/// One thing that happens when the account goes.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.last = false});

  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppText.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppType.body2.copyWith(color: AppText.primary),
            ),
          ),
        ],
      ),
    );
  }
}
