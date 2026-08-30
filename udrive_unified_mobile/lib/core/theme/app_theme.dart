import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF10212B);
  static const primaryDark = Color(0xFF08151C);
  static const secondary = Color(0xFF8ED12B);
  static const accent = Color(0xFF8ED12B);
  static const navy = Color(0xFF10212B);
  static const background = Color(0xFFF6F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const muted = Color(0xFF667085);
  static const border = Color(0xFFE2E9EB);

  /// Redesign token. Previously 0xFFE5484D — the handoff pins danger to
  /// #D92D20 so the SOS control and cancellation states match the spec.
  static const danger = Color(0xFFD92D20);
  static const success = Color(0xFF16A36A);
  static const info = Color(0xFF2F80ED);
  static const warning = Color(0xFFF59E0B);

  /// Body copy. Slightly warmer than [navy], used for text rather than fills.
  static const text = Color(0xFF101828);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
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
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.navy.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.secondary.withValues(alpha: .22),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? AppColors.primaryDark : AppColors.muted,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        selectedColor: AppColors.primary.withValues(alpha: .14),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
      ),
    );
  }
}
