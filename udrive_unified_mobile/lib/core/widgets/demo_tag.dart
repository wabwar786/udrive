import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// The small "Demo" label on a sample tour, car or hotel.
///
/// Sample listings are added and removed from the admin portal (Data
/// management → Add demo data). They show how the app works; the server refuses
/// to book them, and this label tells the customer so before they try.
class DemoTag extends StatelessWidget {
  const DemoTag({this.onDark = false, super.key});

  /// True when the tag sits on a photo or a navy header.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Demo listing, cannot be booked',
      excludeSemantics: true,
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onDark ? AppColors.background : AppTint.warning,
          borderRadius: AppRadii.all(6),
          border: Border.all(color: AppTint.warningBorder),
        ),
        child: Text(
          'Demo',
          maxLines: 1,
          style: AppType.caption.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: AppTint.warningText,
          ),
        ),
      ),
    );
  }
}

/// "New" in place of a rating, for a driver, owner or hotel nobody has rated.
class NewRatingTag extends StatelessWidget {
  const NewRatingTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'New',
      maxLines: 1,
      style: AppType.caption.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: AppColors.brandInk,
      ),
    );
  }
}

/// What the app says when a demo listing is opened for booking.
const demoListingMessage =
    'This is a demo listing that shows how UDrive works. It cannot be booked.';
