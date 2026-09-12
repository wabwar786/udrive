import 'package:flutter/material.dart';

import 'accent_store.dart';

import 'app_theme.dart';

/// Tint / surface colours introduced by the Home & Tour Booking redesign.
///
/// The core brand colours stay in [AppColors]; this file only adds the
/// supporting tints, radii, shadows and text colours the redesign specifies so
/// that no widget hard-codes a hex value.
class AppTint {
  const AppTint._();

  /// Selected service tile and active bottom-nav pill — a low-opacity wash of
  /// the amber action colour rather than a pale tint, so it reads on the dark
  /// teal surfaces.
  /// The light green behind a selected tile or a badge.
  ///
  /// This is where the logo's own light green lives. It cannot carry text, so
  /// it carries nothing but colour.
  static Color get brand => AccentStore.instance.accent.wash;

  /// Secondary surface — inset rows such as the tour-booking toggle strip.
  static const surface = AppColors.surfaceAlt;

  static const success = Color(0xFFE3F5EC);
  static const successText = Color(0xFF0E6B41);

  static const danger = Color(0xFFFBEAEA);

  static const warning = Color(0xFFFCF0DF);
  static const warningText = Color(0xFF8A5600);

  /// Behind the map while tiles are still loading.
  static const mapBackdrop = Color(0xFFEDF1EE);
}

class AppText {
  const AppText._();

  static const primary = Color(0xFF0F1512);
  static const secondary = Color(0xFF5E6B65);

  /// Disabled labels and unselected icons.
  static const disabled = Color(0xFF93A099);

  /// Text placed ON the amber action colour.
  ///
  /// Near-black rather than white: amber is a light colour, and white on it
  /// fails contrast at the sizes buttons use.
  static Color get onBrand => AccentStore.instance.accent.ink;
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

  // Product tiles on the home screen: a pale wash and a dark ink for each.
  //
  // Washes rather than saturated blocks. Four fully-coloured tiles side by side
  // on a white page compete with the one button the customer is meant to press,
  // and with each other.

  // Ride — the brand family.
  static const rideSurface = Color(0xFFE3F5EC);
  static const rideAccent = Color(0xFF178B55);
  static const rideTitle = Color(0xFF0F1512);
  static const rideSub = Color(0xFF5E6B65);
  static const rideInk = Color(0xFFFFFFFF);

  // Tour — warm.
  static const tourSurface = Color(0xFFFCF0DF);
  static const tourAccent = Color(0xFFA76A00);
  static const tourTitle = Color(0xFF0F1512);
  static const tourSub = Color(0xFF5E6B65);

  // Hotel — blue.
  static const hotelSurface = Color(0xFFE7F0FA);
  static const hotelAccent = Color(0xFF1B5FA8);
  static const hotelTitle = Color(0xFF0F1512);
  static const hotelSub = Color(0xFF5E6B65);

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

  /// Shadows tuned for a white page.
  ///
  /// These were black at 35–50% opacity, which is what a dark theme needs to
  /// lift a panel off a near-black page. On white the same values print as grey
  /// smudges under every card and button — visible as haloes around the header
  /// icons, which is not depth, it is dirt.
  ///
  /// A white page separates surfaces with a hairline border and a very faint
  /// shadow, or with nothing at all.

  static List<BoxShadow> get card => [
        BoxShadow(
          color: const Color(0xFF0F1512).withValues(alpha: .06),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get panel => [
        BoxShadow(
          color: const Color(0xFF0F1512).withValues(alpha: .08),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  /// Controls that sit on top of the map.
  ///
  /// Empty. On a light map these had nothing to lift off, and the shadow read
  /// as a ring of dirt around each icon. A white button on a light map is
  /// already distinct; its own edge does the work.
  static List<BoxShadow> get floating => const <BoxShadow>[];

  /// The bottom navigation bar, shadowed upward.
  static List<BoxShadow> get navBar => [
        BoxShadow(
          color: const Color(0xFF0F1512).withValues(alpha: .06),
          blurRadius: 14,
          offset: const Offset(0, -3),
        ),
      ];
}
