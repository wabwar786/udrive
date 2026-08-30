import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Tint / surface colours introduced by the Home & Tour Booking redesign.
///
/// The core brand colours stay in [AppColors]; this file only adds the
/// supporting tints, radii, shadows and text colours the redesign specifies so
/// that no widget hard-codes a hex value.
class AppTint {
  const AppTint._();

  /// Selected service tile and active bottom-nav pill.
  static const brand = Color(0xFFEAF6D8);

  /// Secondary surface — inset rows such as the tour-booking toggle strip.
  static const surface = Color(0xFFF1F5F4);

  static const success = Color(0xFFEAF7F1);
  static const successText = Color(0xFF0F5132);

  static const danger = Color(0xFFFDECEC);

  static const warning = Color(0xFFFEF3C7);
  static const warningText = Color(0xFF92600A);

  /// Behind the map while tiles are still loading.
  static const mapBackdrop = Color(0xFFDCE5E0);
}

class AppText {
  const AppText._();

  static const primary = Color(0xFF101828);
  static const secondary = Color(0xFF667085);

  /// Disabled labels and unselected icons.
  static const disabled = Color(0xFF98A2B3);
}

class AppRadii {
  const AppRadii._();

  static const double field = 13;
  static const double row = 14;
  static const double cta = 15;
  static const double tile = 15;
  static const double card = 18;
  static const double largeCard = 20;
  static const double panel = 24;
  static const double sheet = 24;

  static BorderRadius all(double value) => BorderRadius.circular(value);
  static BorderRadius sheetTop() =>
      const BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Soft-only shadows. The redesign explicitly rules out hard drop shadows.
class AppShadows {
  const AppShadows._();

  static List<BoxShadow> get card => [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .07),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get panel => [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .12),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> get floating => [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .16),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  /// Upward shadow for the bottom navigation bar (no border-top).
  static List<BoxShadow> get navBar => [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .08),
          blurRadius: 24,
          offset: const Offset(0, -6),
        ),
      ];
}
