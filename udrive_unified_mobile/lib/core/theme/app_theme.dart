import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// UDrive's dark premium palette.
///
/// One scheme for the whole app — customer, driver and owner modes all read
/// from here, so nothing has to hard-code a hex value.
/// UDrive's palette: deep teal ground, amber action.
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
  /// Amber. The only saturated colour in the system; it carries every primary
  /// action, so it stays loud against the dark surfaces.
  static const secondary = Color(0xFFF5A524);
  static const accent = Color(0xFFF5A524);

  /// Deepest layer — the app background behind everything.
  static const background = Color(0xFF0A1614);

  /// Cards and panels sit one step above the background.
  static const surface = Color(0xFF102422);

  /// Inset rows, chips and pressed states sit one step above [surface].
  static const surfaceAlt = Color(0xFF1A3330);

  /// Elevated sheets and dialogs.
  static const surfaceHigh = Color(0xFF204340);

  /// Deep teal. Structural rather than decorative: headings, the casing under
  /// the route line, and the dark ink that sits ON the amber action colour.
  static const primary = Color(0xFF0E4F4F);

  /// Near-black with a teal cast, for text on light driver surfaces.
  static const primaryDark = Color(0xFF06201F);
  static const navy = Color(0xFF0E4F4F);

  static const muted = Color(0xFF9BB3AE);
  static const border = Color(0xFF24423E);

  // Status colours, tuned to stay legible on the teal surfaces.
  static const danger = Color(0xFFE5484D);
  static const success = Color(0xFF2FB27C);
  static const info = Color(0xFF4C9AFF);
  static const warning = Color(0xFFE8A33D);

  /// Body copy on dark surfaces.
  static const text = Color(0xFFF2F7F5);
}

class AppTheme {
  /// The app's single theme. Named [dark] to say what it is; [light] is kept
  /// as an alias so existing call sites keep working.
  static ThemeData get light => dark;

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.secondary,
      brightness: Brightness.dark,
      primary: AppColors.secondary,
      onPrimary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
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
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.secondary,
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
        indicatorColor: AppColors.secondary.withValues(alpha: .22),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? AppColors.secondary : AppColors.muted,
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
        selectedColor: AppColors.secondary.withValues(alpha: .20),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
      ),
    );
  }
}
