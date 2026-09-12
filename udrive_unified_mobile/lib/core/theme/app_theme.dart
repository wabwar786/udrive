import 'package:flutter/material.dart';

import 'accent_store.dart';
import 'package:google_fonts/google_fonts.dart';

/// UDrive's dark premium palette.
///
/// One scheme for the whole app — customer, driver and owner modes all read
/// from here, so nothing has to hard-code a hex value.
///
/// Light, after a spell on dark teal. A ride app is used outdoors in daylight
/// far more than it is used at night, and a dark surface in the sun is the one
/// condition where every contrast ratio gets worse at once.
///
/// Two greens, not one. The logo's green is light, and white text on a light
/// green fails contrast at button sizes — so [secondary] is a deep green that
/// carries the actions, and the light one lives in `AppTint.brand` as a wash
/// behind selected tiles and badges.
/// UDrive's palette: white ground, near-black text, green action.
///
/// One scheme for the whole app — customer, driver and owner modes all read
/// from here, so nothing has to hard-code a hex value.
///
/// The lime-on-black scheme this replaces had two problems. Lime is what every
/// ride-hailing app in the region already uses, so nothing on screen said which
/// app you were in. And a green action colour sat one hue away from the green
/// success states and the green route line, which left the button competing
/// with the map underneath it.
///
/// Teal and amber are far enough apart that the thing to press is never in
/// doubt, and amber is the one warm tone that does not collide with the red
/// used for danger.
class AppColors {
  /// The action colour, and the one thing the customer can change.
  ///
  /// A getter, not a `const`. It carries every primary action, so a picker that
  /// only repainted the handful of widgets driven by `ThemeData` would leave
  /// most of the app in the old colour and look broken rather than customised.
  ///
  /// The cost is that it cannot appear inside a `const` expression. There are
  /// seventeen such places and they have had their `const` removed;
  /// `tool/check_imports.py` fails the build if a new one appears, which is the
  /// only compiler-like guard available here.
  static Color get secondary => AccentStore.instance.accent.seed;
  static Color get accent => AccentStore.instance.accent.seed;

  /// Deepest layer — the app background behind everything.
  static const background = Color(0xFFFFFFFF);

  /// Cards and panels. On a white page these sit *below* the background
  /// rather than above it — a raised white card on a white page needs a shadow
  /// to exist, and a faint grey needs nothing.
  static const surface = Color(0xFFF5F8F6);

  /// Inset rows, chips and pressed states, one step further from white.
  static const surfaceAlt = Color(0xFFECF1EE);

  /// Elevated sheets and dialogs. White, so they read as lifted off the page.
  static const surfaceHigh = Color(0xFFFFFFFF);

  /// Structural rather than decorative: headings, and the casing under the
  /// route line.
  static const primary = Color(0xFF0F1512);

  /// Near-black, for text on light surfaces.
  static const primaryDark = Color(0xFF0F1512);
  static const navy = Color(0xFF0F1512);

  static const muted = Color(0xFF5E6B65);
  static const border = Color(0xFFE3EAE6);

  // Status colours, dark enough to read on white. The dark-theme versions
  // were mint, coral and sky — all of which vanish on a white page.
  static const danger = Color(0xFFCF3A3A);
  static const success = Color(0xFF178B55);
  static const info = Color(0xFF1B5FA8);
  static const warning = Color(0xFFA76A00);

  /// Body copy.
  static const text = Color(0xFF0F1512);
}

class AppTheme {
  /// The app's single theme. Named [dark] to say what it is; [light] is kept
  /// as an alias so existing call sites keep working.
  static ThemeData get light => dark;

  /// The theme, built around whichever accent the customer has chosen.
  ///
  /// The accent is read here rather than threaded through every widget: it
  /// changes the colour of buttons, selected states and the fare, and those
  /// appear on nearly every screen.
  static ThemeData get dark {
    final accent = AccentStore.instance.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: Brightness.light,
      primary: accent.seed,
      onPrimary: accent.ink,
      secondary: accent.seed,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      // Light, and stated. Without this Material picks its own defaults for
      // anything the scheme does not cover — dialog scrims, ripples, switch
      // tracks — and picks dark ones.
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: GoogleFonts.montserrat().fontFamily,
      visualDensity: VisualDensity.compact,
      textTheme: GoogleFonts.montserratTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
          headlineLarge: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 13),
          bodyMedium: TextStyle(fontSize: 12),
          bodySmall: TextStyle(fontSize: 10.5),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: .40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent.seed, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent.seed,
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.surface,
        indicatorColor: accent.seed.withValues(alpha: .22),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? accent.seed : AppColors.muted,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: accent.seed.withValues(alpha: .20),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
      ),
    );
  }
}
