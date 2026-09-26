import 'package:flutter/material.dart';

import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';
import '../driver_documents_screen.dart';
import 'driver_vehicle_type_screen.dart';

/// D-07 — where a driver's registration stands.
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
///
/// No `Scaffold`. `main_shell` renders this behind the driver gate and draws
/// the bar; the design's own back arrow is that bar, not a second one.
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

    // The tone drives the halo, the icon and — for the two states that carry a
    // reviewer's words — the banner underneath. One switch, so a new status can
    // never end up with a green tick and a red message.
    final (IconData icon, UdIconTone tone, String title, String body,
        String? actionLabel) = switch (status) {
      'Submitted' || 'PendingReview' || 'UnderReview' => (
          Icons.hourglass_top_rounded,
          UdIconTone.warn,
          'With our team',
          'Our team checks new registrations within 24 hours. You can close '
              'the app — nothing is lost, and this screen will show the '
              'result.',
          null,
        ),
      'ChangesRequired' || 'Rejected' => (
          Icons.error_outline_rounded,
          UdIconTone.red,
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
          UdIconTone.soft,
          'You are approved',
          'You can go online and start taking rides.',
          null,
        ),
      _ => (
          Icons.edit_note_rounded,
          UdIconTone.neutral,
          'Not finished yet',
          'Your registration has not been sent. Pick up where you left off.',
          'Continue registration',
        ),
    };

    final rejected = status == 'ChangesRequired' || status == 'Rejected';

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 24, AppSizes.sidePadding, 34),
        children: [
          // 88px halo, same as the artboard. Bigger than any tile size the kit
          // ships, and deliberately so — on a screen with four lines of text
          // this is the one thing you read from across the room.
          Center(child: _Halo(icon: icon, tone: tone)),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(height: 1.6, color: AppText.secondary),
          ),

          // A reviewer's own words, when there are any, on a red banner rather
          // than as grey body text. They are the only part of this screen that
          // is about *your* form and not about the process.
          if (rejected && notes != null && notes.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.assignment_late_outlined,
              text: notes,
            ),
          ],

          const SizedBox(height: 26),

          if (actionLabel != null) ...[
            UdButton(
              label: actionLabel,
              icon: rejected
                  ? Icons.folder_open_rounded
                  : Icons.arrow_forward_rounded,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (routeContext) => rejected
                      ? const DriverDocumentsScreen()
                      // D-01 ships no `Scaffold` of its own — `main_shell`
                      // normally frames it. Pushed from here it has no frame,
                      // so it gets one: without it the list paints on nothing
                      // and there is no way back.
                      : Scaffold(
                          backgroundColor: AppColors.background,
                          appBar: UdTopBar(
                            title: 'Driver registration',
                            onBack: () => Navigator.pop(routeContext),
                          ),
                          body: const DriverVehicleTypeScreen(),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          UdButton.outline(
            label: _refreshing ? 'Checking…' : 'Check for an update',
            icon: Icons.refresh_rounded,
            busy: _refreshing,
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
    );
  }
}

/// The status halo — a circle of wash with the state's icon in its ink.
///
/// `UdIconTile` tops out at 56px and is a rounded square; this is round and
/// 88px, so it borrows the tile's colour pairs rather than the tile itself.
/// Every pair here is one the kit already ships, which is what keeps the icon
/// legible on its own wash.
class _Halo extends StatelessWidget {
  const _Halo({required this.icon, required this.tone});

  final IconData icon;
  final UdIconTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink) = switch (tone) {
      UdIconTone.warn => (AppTint.warning, AppTint.warningText),
      UdIconTone.red => (AppTint.danger, AppTint.dangerText),
      UdIconTone.soft => (AppColors.brandWash, AppColors.brandInk),
      UdIconTone.info => (AppTint.info, AppTint.infoText),
      UdIconTone.lime => (AppColors.brand, AppText.onBrand),
      UdIconTone.navy => (AppColors.navy, AppColors.brand),
      UdIconTone.neutral => (AppColors.surfaceAlt, AppColors.navy),
    };

    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, size: 40, color: ink),
    );
  }
}
