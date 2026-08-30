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
  static const brand = Color(0xFF1F3A1B);

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
  static const onBrand = Color(0xFF07120A);
}

/// Per-product colours.
///
/// Each service owns a hue so the four products read as four different things
/// rather than four shades of the brand. Flat tinted surfaces rather than
/// gradients: a gradient per card looks striking on a monitor but reads as busy
/// on a phone outdoors, and four of them compete with the map behind.
///
/// Each product carries a surface, an accent for its icon and border, a title
/// ink and a subdued ink. Colour means something here, so the same hue follows
/// a product wherever it appears.
class AppProduct {
  const AppProduct._();

  // Ride — the brand green.
  static const rideSurface = Color(0xFF1F3A1B);
  static const rideAccent = Color(0xFFA6FF2E);
  static const rideTitle = Color(0xFFEAF7D6);
  static const rideSub = Color(0xFFA8C98A);
  static const rideInk = Color(0xFF07120A);

  // Tour — amber.
  static const tourSurface = Color(0xFF3A2A12);
  static const tourAccent = Color(0xFFFFB84D);
  static const tourTitle = Color(0xFFFFD79A);
  static const tourSub = Color(0xFFC99C56);

  // Hotel — blue.
  static const hotelSurface = Color(0xFF12293D);
  static const hotelAccent = Color(0xFF5AA9FF);
  static const hotelTitle = Color(0xFFB8DCFF);
  static const hotelSub = Color(0xFF6FA3CE);

  // Seats — violet. Used by the per-seat control rather than a card.
  static const seatsAccent = Color(0xFF8B5CF6);
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
