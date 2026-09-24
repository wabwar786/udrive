import 'package:flutter/material.dart';

import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../driver_documents_screen.dart';
import 'driver_vehicle_type_screen.dart';

/// Where a driver's registration stands.
///
/// This screen did not exist, and its absence was the whole problem: after
/// submitting, a driver was returned to the same "how do you want to earn?"
/// list they had started from. Nothing said the form had arrived, nothing said
/// anyone was looking at it, and nothing changed when the answer came — people
/// were closing and reopening the app to find out.
///
/// Four states, and each one says what to do next rather than only what has
/// happened. "Submitted" with no idea whether to wait an hour or a week is
/// barely better than silence.
class DriverVerificationStatusScreen extends StatefulWidget {
  const DriverVerificationStatusScreen({super.key});

  @override
  State<DriverVerificationStatusScreen> createState() =>
      _DriverVerificationStatusScreenState();
}

class _DriverVerificationStatusScreenState
    extends State<DriverVerificationStatusScreen> {
  bool _refreshing = false;

  /// Asks the server again.
  ///
  /// There is a manual button as well as the pull-to-refresh, because someone
  /// waiting on a decision will look more often than any polling interval worth
  /// running, and a button they pressed themselves is more reassuring than a
  /// screen that might be updating.
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await AppControllerScope.of(context).refreshDriverProfile();
    } catch (_) {
      // A failed refresh leaves the last known status on screen, which is
      // better than an error where a status used to be.
    }
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final status = controller.driverVerificationStatus;
    final notes = controller.driverProfile?.reviewNotes;

    final (icon, tint, ink, title, body, actionLabel) = switch (status) {
      'Submitted' || 'PendingReview' || 'UnderReview' => (
          Icons.hourglass_top_rounded,
          AppTint.warning,
          AppTint.warningText,
          'With our team',
          'Our team checks new registrations within 24 hours. You can close '
              'the app — nothing is lost, and this screen will show the '
              'result.',
          null,
        ),
      'ChangesRequired' || 'Rejected' => (
          Icons.error_outline_rounded,
          AppTint.danger,
          AppTint.dangerText,
          'Something needs to be sent again',
          notes == null || notes.trim().isEmpty
              // A rejection with no reason is the worst of both: the driver
              // knows they failed and not what to fix.
              ? 'A reviewer has asked for a change. Open your documents to see '
                  'which one.'
              : notes,
          'Open my documents',
        ),
      'Approved' => (
          Icons.verified_rounded,
          AppTint.success,
          AppTint.successText,
          'You are approved',
          'You can go online and start taking rides.',
          null,
        ),
      _ => (
          Icons.edit_note_rounded,
          AppColors.surfaceAlt,
          AppText.secondary,
          'Not finished yet',
          'Your registration has not been sent. Pick up where you left off.',
          'Continue registration',
        ),
    };

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: 42, color: ink),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.6,
              color: AppText.secondary,
            ),
          ),

          const SizedBox(height: 26),

          if (actionLabel != null)
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => status == 'ChangesRequired' ||
                          status == 'Rejected'
                      ? const DriverDocumentsScreen()
                      : const DriverVehicleTypeScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(actionLabel),
            ),

          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _refreshing ? null : _refresh,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_refreshing ? 'Checking…' : 'Check for an update'),
          ),
        ],
      ),
    );
  }
}
