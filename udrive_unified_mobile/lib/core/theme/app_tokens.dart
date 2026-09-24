import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Tint / surface colours introduced by the Home & Tour Booking redesign.
///
/// The core brand colours stay in [AppColors]; this file only adds the
/// supporting tints, radii, shadows and text colours the redesign specifies so
/// that no widget hard-codes a hex value.
class AppTint {
  const AppTint._();

  /// The pale lime behind a selected tile or a badge.
  ///
  /// A wash, not the brand lime itself: full-strength lime behind a row of
  /// chips is louder than the button it is supposed to defer to. It cannot
  /// carry text, so it carries nothing but colour.
  static const brand = AppColors.brandWash;

  /// Secondary surface — inset rows such as the tour-booking toggle strip.
  static const surface = AppColors.surfaceAlt;

  static const success = Color(0xFFEDF7D6);

  /// Ink on [success].
  ///
  /// A shade darker than [AppColors.secondary], which is the accent's value on
  /// white. On this pale lime wash the accent measures 4.42:1 — under AA for
  /// the "3 seats left" sized text it mostly carries. This is 5.84:1.
  static const successText = Color(0xFF4E6600);

  static const danger = Color(0xFFFFECEC);
  static const dangerText = Color(0xFFB3272A);

  /// A danger outline. Written as a fixed alpha because `withValues` is not a
  /// const expression and these sit inside `const BorderSide`.
  static const dangerBorder = Color(0x33FF4D4F);

  static const warning = Color(0xFFFCF0DF);
  static const warningText = Color(0xFF8A5600);

  static const info = Color(0xFFEAF2FF);
  static const infoText = AppColors.info;

  /// Rating stars. Gold, and nothing else in the app is this colour.
  static const star = Color(0xFFF5B942);

  // Map semantics. These are not brand colours and do not follow the brand:
  // green means "where you are", amber means "where you are going", and a
  // rider reads those two before they read any label. Tokens so the two
  // meanings stay one colour each across the map, the route sheet and the
  // trip panel.
  static const pickup = Color(0xFF16A34A);
  static const dropoff = Color(0xFFF97316);

  /// Waiting on someone: a request out to drivers, an offer not yet answered.
  /// Amber because it is neither done nor wrong, and it has to read at a
  /// glance on the dark route sheet as well as on a white card.
  static const pending = Color(0xFFF79009);
  static const pendingBorder = Color(0x55F79009);

  // Scrims and glass on the dark screens: navy at fixed opacities, for the
  // same const reason as [dangerBorder].
  static const inkScrim = Color(0xE80B1B33);
  static const inkVeil = Color(0xB80B1B33);
  static const inkGlass = Color(0xA80B1B33);
  static const inkGlassSoft = Color(0x840B1B33);

  /// Card and panel shadows, as a const colour.
  static const shadow = Color(0x1F0B1B33);
  static const shadowSoft = Color(0x140B1B33);

  /// Behind the map while tiles are still loading.
  static const mapBackdrop = Color(0xFFEEF1F4);
}

class AppText {
  const AppText._();

  static const primary = AppColors.navy;
  static const secondary = AppColors.muted;

  /// Disabled labels and unselected icons.
  static const disabled = Color(0xFF9AA3AF);

  /// Text placed ON the brand lime.
  ///
  /// Navy, always. White on lime is 1.28:1 — not dim, not marginal; invisible.
  static const onBrand = AppColors.onBrand;
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

  // Product tiles on the home screen.
  //
  // Deeper than the near-white washes these started as. On a white page a 4%
  // tint is not a colour, it is a smudge — the tiles read as empty space with
  // words in it rather than as blocks you press. These are saturated enough to
  // hold an edge without a border.
  //
  // Still not full-strength brand colour: four saturated blocks side by side
  // compete with each other and with the one button on the screen. The ink
  // stays near-black on all of them, which is what keeps them readable at this
  // depth and is the reason the depth is safe.

  // Ride is the brand's own tile and takes the brand's own colour; the others
  // are neutral, with their hue carried by the icon rather than the whole
  // block. Four saturated blocks beside a lime button was three colours too
  // many, and it is the brand tile that should win.

  // Ride — brand lime.
  static const rideSurface = AppColors.brand;
  static const rideAccent = AppColors.onBrand;
  static const rideTitle = AppColors.onBrand;
  static const rideSub = Color(0xFF2E3C52);
  static const rideInk = AppColors.onBrand;

  // Tour — neutral block, warm icon.
  static const tourSurface = Color(0xFFF4F6F8);
  static const tourAccent = Color(0xFF8A5600);
  static const tourTitle = AppColors.navy;
  static const tourSub = AppColors.muted;

  // Hotel — neutral block, blue icon.
  static const hotelSurface = Color(0xFFEEF1F4);
  static const hotelAccent = Color(0xFF16497F);
  static const hotelTitle = AppColors.navy;
  static const hotelSub = AppColors.muted;

  // Seats — used by the per-seat control rather than a card.
  static const seatsAccent = Color(0xFF5E7A00);
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
          color: AppColors.navy.withValues(alpha: .06),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get panel => [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .08),
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
          color: AppColors.navy.withValues(alpha: .06),
          blurRadius: 14,
          offset: const Offset(0, -3),
        ),
      ];
}
