import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Tint / surface colours introduced by the Home & Tour Booking redesign.
///
/// The core brand colours stay in [AppColors]; this file only adds the
/// supporting tints, radii, shadows and text colours the redesign specifies so
/// that no widget hard-codes a hex value.
class AppTint {
  const AppTint._();

  /// Selected service tile and active bottom-nav pill — a low-opacity wash of
  /// the brand green rather than a pale tint, so it reads on dark surfaces.
  static const brand = Color(0xFF23361A);

  /// Secondary surface — inset rows such as the tour-booking toggle strip.
  static const surface = AppColors.surfaceAlt;

  static const success = Color(0xFF11302A);
  static const successText = Color(0xFF6EE7B0);

  static const danger = Color(0xFF3A1A18);

  static const warning = Color(0xFF3A2E14);
  static const warningText = Color(0xFFFFC96B);

  /// Behind the map while tiles are still loading.
  static const mapBackdrop = Color(0xFF16242B);
}

class AppText {
  const AppText._();

  static const primary = Color(0xFFF1F6F7);
  static const secondary = Color(0xFF9FB3BB);

  /// Disabled labels and unselected icons.
  static const disabled = Color(0xFF64808A);

  /// Text placed ON the brand green.
  static const onBrand = Color(0xFF0B1417);
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
          color: Colors.black.withValues(alpha: .35),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get panel => [
        BoxShadow(
          color: Colors.black.withValues(alpha: .45),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> get floating => [
        BoxShadow(
          color: Colors.black.withValues(alpha: .50),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  /// Upward shadow for the bottom navigation bar (no border-top).
  static List<BoxShadow> get navBar => [
        BoxShadow(
          color: Colors.black.withValues(alpha: .40),
          blurRadius: 24,
          offset: const Offset(0, -6),
        ),
      ];
}
