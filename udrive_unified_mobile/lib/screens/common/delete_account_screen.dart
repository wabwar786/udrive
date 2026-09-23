import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/auth_models.dart';

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
      appBar: AppBar(
        title: const Text('Delete account', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 44),
            const SizedBox(height: 10),
            const Text(
              'This permanently deletes your UDrive account.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text),
            ),
            const SizedBox(height: 14),
            const _Point(
              icon: Icons.delete_outline_rounded,
              text: 'Deleted now: your name, phone number, email, profile photo, trusted contacts, '
                  'and for drivers the CNIC and licence numbers, date of birth, address and payout details.',
            ),
            const _Point(
              icon: Icons.logout_rounded,
              text: 'You are signed out on every device. Your vehicles are removed and you stop receiving rides.',
            ),
            const _Point(
              icon: Icons.receipt_long_outlined,
              text: 'Kept without your name: past trips, payments, wallet and commission records, '
                  'as required for tax, accounting and safety investigations.',
            ),
            const _Point(
              icon: Icons.account_balance_wallet_outlined,
              text: 'Any remaining wallet balance or welcome credit is lost and cannot be restored.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _reason,
              maxLength: 500,
              maxLines: 3,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Why are you leaving? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _confirmed && !_busy ? _delete : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Delete my account',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Keep my account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}
