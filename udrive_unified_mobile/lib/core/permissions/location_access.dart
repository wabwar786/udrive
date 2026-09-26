import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/ud_kit.dart';
import '../../screens/common/legal_screen.dart';

/// Why the app is about to ask for location, which decides what the person is
/// told before the system dialog appears.
enum LocationPurpose {
  /// A customer picking a pickup point, finding vehicles or places nearby.
  /// One reading at a time, nothing sent anywhere but the booking.
  customer,

  /// A Driver going online or running a trip. This one is continuous and it
  /// leaves the device, so it has to say so.
  driver,
}

/// The single place the app asks for location.
///
/// WHY THIS EXISTS
///
/// Google Play's Location Permissions policy requires a *prominent disclosure*
/// before the runtime permission prompt: the app must say, in its own UI, that
/// it collects location, and what for, and the person must be able to decline
/// without the system dialog ever appearing. A system dialog on its own does
/// not satisfy it, and neither does a privacy policy the person has to go and
/// find — the disclosure has to be in the flow.
///
/// Before this, eight screens called `Geolocator.requestPermission()` directly
/// with nothing shown first, and the very first one fired while the customer
/// home screen was still loading. The only location copy in the app was the
/// error text *after* a refusal. That is the shape of a policy rejection, and
/// on the Driver side it was asking for a continuously uploaded location trail
/// without ever mentioning it.
///
/// HOW IT BEHAVES
///
///  * Already granted → returns immediately. No dialog, ever, on the happy path.
///  * Permanently denied → returns that, so the caller can point at Settings.
///    No disclosure: there is no prompt left to precede.
///  * Denied → shows the disclosure. Declining returns [LocationPermission.denied]
///    and the system prompt is never raised. Only "Continue" reaches
///    `Geolocator.requestPermission()`.
///
/// Nothing is persisted. Once permission is granted the first branch means this
/// is never shown again, and if the person declined, seeing it again next time
/// they tap something that needs their location is correct — they asked for
/// that feature again.
class LocationAccess {
  const LocationAccess._();

  /// Discloses, then asks. Use this instead of calling Geolocator directly.
  static Future<LocationPermission> ensure(
    BuildContext context,
    LocationPurpose purpose,
  ) async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return permission;
    }

    // Nothing to precede: the system will not prompt again, so showing a
    // disclosure here would only be a dialog in the way of the real message.
    if (permission == LocationPermission.deniedForever) {
      return permission;
    }

    if (!context.mounted) return permission;

    final agreed = await _disclose(context, purpose);
    if (agreed != true) {
      // Declined the disclosure. The system prompt is deliberately not raised.
      return LocationPermission.denied;
    }

    permission = await Geolocator.requestPermission();
    return permission;
  }

  /// True when [permission] lets the app read a position.
  static bool granted(LocationPermission permission) =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  static Future<bool?> _disclose(BuildContext context, LocationPurpose purpose) {
    final driver = purpose == LocationPurpose.driver;

    return showUdDialog<bool>(
      context: context,
      // Not dismissible by tapping outside. A disclosure that can be waved
      // away by accident has not been made, and the person needs a deliberate
      // "Not now" rather than a stray tap that leaves them wondering why the
      // feature does nothing.
      barrierDismissible: false,
      title: driver ? 'UDrive needs your location' : 'Use your location?',
      message: driver
          ? 'UDrive collects your precise location while you are online or on a '
              'trip, and sends it to UDrive so the customer can see you coming '
              'and so support can find you if something goes wrong.'
          : 'UDrive collects your precise location to set your pickup point, '
              'show vehicles and places near you, and follow your trip on the '
              'map.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Point(
            icon: Icons.schedule_rounded,
            text: driver
                ? 'Only while the app is open and you are online. UDrive never '
                    'collects your location in the background, and stops when '
                    'you go offline.'
                : 'Only while the app is open. UDrive never collects your '
                    'location in the background.',
          ),
          const SizedBox(height: 12),
          _Point(
            icon: Icons.people_outline_rounded,
            text: driver
                ? 'Shared with the customer on your current trip, and with '
                    'UDrive staff handling a safety alert. Never sold, never '
                    'used for ads.'
                : 'Shared with your driver for the trip you book. Never sold, '
                    'never used for ads.',
          ),
          const SizedBox(height: 12),
          _Point(
            icon: Icons.delete_outline_rounded,
            text: driver
                ? 'Your trip trail is deleted after 30 days.'
                : 'You can decline and set your pickup by typing it instead.',
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => LegalScreen.open(context, 'privacy-policy'),
            child: Text(
              'Read the Privacy Policy',
              style: AppType.body2.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UdButton.primary(
          label: 'Continue',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        UdButton.ghost(
          label: 'Not now',
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ),
      ],
    );
  }
}
