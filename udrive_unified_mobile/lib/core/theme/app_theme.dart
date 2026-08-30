import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// UDrive's dark premium palette.
///
/// One scheme for the whole app — customer, driver and owner modes all read
/// from here, so nothing has to hard-code a hex value.
class AppColors {
  /// Brand green. The only saturated colour in the system; it carries every
  /// primary action, so it stays loud against the dark surfaces.
  /// Brightened from #8ED12B. The old value was mixed for light surfaces and
  /// sat flat against the dark theme; this lifts without leaving the family.
  static const secondary = Color(0xFFA6FF2E);
  static const accent = Color(0xFFA6FF2E);

  /// Deepest layer — the app background behind everything.
  static const background = Color(0xFF080F12);

  /// Cards and panels sit one step above the background.
  static const surface = Color(0xFF0E1A21);

  /// Inset rows, chips and pressed states sit one step above [surface].
  static const surfaceAlt = Color(0xFF182833);

  /// Elevated sheets and dialogs.
  static const surfaceHigh = Color(0xFF213741);

  /// Kept as the dark ink used for text ON the brand green.
  static const primary = Color(0xFF07120A);
  static const primaryDark = Color(0xFF060E11);
  static const navy = Color(0xFF07120A);

  static const muted = Color(0xFF9FB3BB);
  static const border = Color(0xFF233A44);

  /// Redesign token. Previously 0xFFE5484D — the handoff pins danger to
  /// #D92D20 so the SOS control and cancellation states match the spec.
  // Status colours, brightened so they stay legible on dark surfaces.
  static const danger = Color(0xFFFF5A4E);
  static const success = Color(0xFF3DD68C);
  static const info = Color(0xFF5AA9FF);
  static const warning = Color(0xFFFFB84D);

  /// Body copy on dark surfaces.
  static const text = Color(0xFFF1F6F7);
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
