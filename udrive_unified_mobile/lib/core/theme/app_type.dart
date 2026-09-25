import 'package:flutter/material.dart';

/// Typography, radii and fixed sizes for design system v2.
///
/// This file deliberately imports nothing but Material and names no colour.
///
/// `app_tokens.dart` already imports `app_theme.dart` to reach [AppColors], and
/// the theme now needs the type scale — putting the scale in either of those
/// two would have made them import each other. Keeping the colourless half of
/// the system here leaves a one-way chain:
///
///     app_type.dart  ←  app_theme.dart  ←  app_tokens.dart
///
/// `app_tokens.dart` re-exports this file, so every existing
/// `import '../theme/app_tokens.dart'` still sees [AppRadii] exactly as before
/// and nothing had to change at the call sites.
class AppType {
  const AppType._();

  /// The bundled family name. Must match the `family:` key in pubspec.yaml.
  static const String family = 'PlusJakartaSans';

  // ---------------------------------------------------------------------
  // The scale from HANDOFF.md §2.5.
  //
  // Letter-spacing in the design is given in em; Flutter wants logical pixels,
  // so each value below is the em figure multiplied by its own font size
  // (−0.03em at 34px = −1.02). Getting this wrong is not subtle at 800 weight:
  // the large headings are where tracking does the most work.
  //
  // Nothing in the system is smaller than 12.5px.
  // ---------------------------------------------------------------------

  /// Hero numbers — a fare on its own line, an earnings total.
  static const display = TextStyle(
    fontFamily: family,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.02,
    height: 1.1,
  );

  /// The title of a bottom-nav tab root. Big on purpose: these five screens
  /// are where somebody lands, and the title is how they know which one.
  static const screenTitle = TextStyle(
    fontFamily: family,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.75,
    height: 1.12,
  );

  static const h1 = TextStyle(
    fontFamily: family,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.7,
    height: 1.15,
  );

  /// Sheet and card headings.
  static const h2 = TextStyle(
    fontFamily: family,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.33,
    height: 1.2,
  );

  /// The app bar of a pushed page — smaller than a tab-root title, because a
  /// pushed page already has a back arrow telling you where you are.
  static const barTitle = TextStyle(
    fontFamily: family,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static const section = TextStyle(
    fontFamily: family,
    fontSize: 19,
    fontWeight: FontWeight.w800,
    height: 1.25,
  );

  /// Card titles.
  static const h3 = TextStyle(
    fontFamily: family,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// List rows.
  static const listTitle = TextStyle(
    fontFamily: family,
    fontSize: 16.5,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// Paragraphs. 16px because this app is read outdoors, in sunlight, often
  /// one-handed at the side of a road.
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// Secondary lines. Pair with `AppText.secondary`.
  static const body2 = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  /// Meta text. Pair with `AppText.secondary`.
  static const small = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// Timestamps and hints. Pair with `AppText.caption`, and only on white —
  /// that colour has no contrast margin left on a grey inset.
  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// Field keys: "FROM", "TO", "PICK-UP". Uppercase them at the call site;
  /// this only carries the size, weight and tracking.
  static const overline = TextStyle(
    fontFamily: family,
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.75,
    height: 1.2,
  );

  /// The main fare on a booking screen.
  static const price = TextStyle(
    fontFamily: family,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.02,
    height: 1.1,
  );

  /// A price inside a list row.
  static const priceMd = TextStyle(
    fontFamily: family,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  /// 58px buttons. [buttonSm] is for the 46px and 38px variants.
  static const button = TextStyle(
    fontFamily: family,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static const buttonSm = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );
}

class AppRadii {
  const AppRadii._();

  // v2 values. Everything grew a little except [tile], and the shapes are more
  // consistent with each other than the v1 set was.
  static const double field = 16; // was 13
  static const double row = 14;
  static const double cta = 17; // was 15
  static const double tile = 14; // was 15
  static const double card = 20; // was 18
  static const double largeCard = 26; // was 20 — booking cards, inline sheets
  static const double panel = 24;
  static const double sheet = 28; // was 24
  static const double dialog = 26;

  /// A pill. Used by chips and the bottom-nav active indicator.
  static const double chip = 999;

  static BorderRadius all(double value) => BorderRadius.circular(value);
  static BorderRadius sheetTop() =>
      const BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Fixed measurements the design repeats often enough to be worth naming.
class AppSizes {
  const AppSizes._();

  static const double button = 58;
  static const double buttonSmall = 46;
  static const double buttonXs = 38;
  static const double field = 58;
  static const double iconButton = 46;
  static const double iconTile = 46;
  static const double iconTileSm = 38;
  static const double iconTileLg = 56;
  static const double listRow = 64;
  static const double topBar = 72;
  static const double bottomNav = 86;

  /// The side gutter. Every screen in the design uses 20.
  static const double sidePadding = 20;
  static const double sectionGap = 20;

  /// Nothing may be smaller than this, anywhere.
  static const double minText = 12.5;

  /// The smallest a tappable thing may be.
  static const double minTouch = 44;
}
