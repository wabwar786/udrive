import 'package:flutter/material.dart';

import 'brand.dart';

/// The horizontal UDrive logo.
///
/// Kept as a name because the first prototype screens call it. Everything it
/// used to do — pick an asset, pick a height — now lives in [UDriveWordmark],
/// so the brand has exactly one place that names a file on disk. It used to
/// point at `assets/images/udrive_wordmark_v3.png`, which is not the mark in
/// the brand kit and is not what the app icon or the store listing show.
class UDriveLogo extends StatelessWidget {
  const UDriveLogo({super.key, this.compact = false, this.onDark = false});

  final bool compact;

  /// Lime pin and white text, for placing on navy.
  final bool onDark;

  @override
  Widget build(BuildContext context) =>
      UDriveWordmark(compact: compact, onDark: onDark);
}
