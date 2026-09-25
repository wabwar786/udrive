import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

/// UDrive's brand palette: white ground, navy ink, lime action.
///
/// One scheme for the whole app — customer, driver and owner modes all read
/// from here, so nothing has to hard-code a hex value.
///
/// Taken from the UDrive brand kit. The two colours that matter are lime
/// `#C6F432` and navy `#0B1B33`, and the rule that governs every use of them is
/// contrast:
///
///   navy on lime      13.45:1   the button pairing, and the only one
///   white on lime      1.28:1   unreadable — never do this
///   dark-lime on white 4.93:1   the accent when it has to be ink
///
/// So lime is a *surface*, never ink, and never carries white. Where the accent
/// has to be text or an icon on a white page it is [secondary], the kit's
/// darker lime, which is legible both as ink on white and as a fill under white
/// text.
///
/// This replaces a scheme with a customer-selectable accent (green/blue/amber).
/// A brand the customer can repaint is not a brand, and the picker meant no two
/// screenshots of the app agreed with each other or with the store listing.
class AppColors {
  // ------------------------------------------------------------------ brand

  /// Brand lime. A surface colour: put [onBrand] on top of it, never white.
  static const brand = Color(0xFFC6F432);

  /// The only ink that belongs on [brand].
  static const onBrand = Color(0xFF0B1B33);

  /// A pale lime wash, for selected tiles and badges that must not shout.
  static const brandWash = Color(0xFFF2FCD6);

  /// The accent where it has to be ink, or a fill under white text.
  ///
  /// The kit's darker lime. Lime itself is unreadable at 1.28:1 on white, and
  /// this is the value the kit names for exactly that reason.
  ///
  /// Now a `const`, where it used to be a getter into the accent picker. The
  /// seventeen call sites that had their `const` stripped to accommodate that
  /// can take it back; `tool/check_const_colours.py` no longer has anything to
  /// catch here.
  static const secondary = Color(0xFF5E7A00);

  /// Kept as an alias so existing call sites keep working.
  static const accent = secondary;

  // --------------------------------------------------------------- surfaces

  /// Deepest layer — the app background behind everything.
  static const background = Color(0xFFFFFFFF);

  /// Cards and panels. On a white page these sit *below* the background
  /// rather than above it — a raised white card on a white page needs a shadow
  /// to exist, and a faint grey needs nothing.
  static const surface = Color(0xFFF4F6F8);

  /// Inset rows, chips and pressed states, one step further from white.
  static const surfaceAlt = Color(0xFFEEF1F4);

  /// Elevated sheets and dialogs. White, so they read as lifted off the page.
  static const surfaceHigh = Color(0xFFFFFFFF);

  // ------------------------------------------------------------------- ink

  /// Structural rather than decorative: headings, and the casing under the
  /// route line.
  static const primary = Color(0xFF0B1B33);

  /// Navy, for text on light surfaces.
  static const primaryDark = Color(0xFF0B1B33);
  static const navy = Color(0xFF0B1B33);

  /// Secondary copy. 4.62:1 on white; 4.26:1 on [surface], which clears AA for
  /// large text but not for small — so keep it off small print inside cards.
  static const muted = Color(0xFF6B7684);
  static const border = Color(0xFFE3E7EC);

  // Status colours, dark enough to read on white.
  //
  // danger is the kit's SOS red. White on it is 3.27:1, which is AA for large
  // text only — fine for the SOS button, which is large and bold, and the
  // reason navy is used on it wherever the text is small.
  static const danger = Color(0xFFFF4D4F);
  static const success = Color(0xFF5E7A00);
  static const info = Color(0xFF1B5FA8);
  static const warning = Color(0xFFA76A00);

  /// Body copy.
  static const text = Color(0xFF0B1B33);

  // ----------------------------------------------------- dark surfaces
  //
  // A handful of screens are dark by design and should stay that way: the
  // route flow and the hotel browser put a panel over a photograph or a map,
  // where a white sheet would wash out the thing it is sitting on.
  //
  // Those screens each carried their own private palette of near-black greens
  // (#0C0E0D, #161816, #202220 and a dozen neighbours), left over from when
  // the whole app was dark and green. The layout was right; the hue was a
  // different brand. These are the same ramp in navy, so a dark screen is now
  // dark *UDrive* rather than dark something-else.
  //
  // White on [inkSurface] is 17.2:1, [onInkMuted] is 7.8:1, and [brand] is
  // 13.4:1 — the dark screens can carry the lime as ink, which the white ones
  // cannot.

  /// Behind everything on a dark screen, and the far end of a dark gradient.
  static const inkDeep = Color(0xFF071224);

  /// The dark screen's ground. The same navy as the ink on a light page.
  static const inkSurface = Color(0xFF0B1B33);

  /// Cards and sheets on a dark screen.
  static const inkPanel = Color(0xFF122540);

  /// Rows, fields and pressed states, one step lighter again.
  static const inkTile = Color(0xFF1B3050);

  /// Body copy on a dark screen.
  static const onInk = Color(0xFFFFFFFF);

  /// Secondary copy on a dark screen. 7.8:1 on [inkSurface].
  static const onInkMuted = Color(0xFF9FB0C4);
}

class AppTheme {
  /// The app's single theme. Named [dark] to say what it is; [light] is kept
  /// as an alias so existing call sites keep working.
  static ThemeData get light => dark;

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      // Lime is the primary action colour, and navy is the only thing legible
      // on it. Stated rather than derived: fromSeed would pick its own
      // onPrimary, and for a colour this light it picks white.
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
      onError: AppColors.onBrand,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: GoogleFonts.poppins().fontFamily,
      visualDensity: VisualDensity.compact,
      textTheme: GoogleFonts.poppinsTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          headlineLarge: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 15),
          bodyMedium: TextStyle(fontSize: 14),
          bodySmall: TextStyle(fontSize: 12.5),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
        // The focus ring is the darker lime, not brand lime: a 1.6px lime line
        // on a near-white field is invisible.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      // The brand pairing, in the one place that covers most primary actions.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.brand,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.navy
                : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            // On the lime indicator, so navy.
            color: states.contains(WidgetState.selected)
                ? AppColors.onBrand
                : AppColors.muted,
          ),
        ),
      ),
      // Spinners take colorScheme.primary unless told otherwise, and primary
      // is now lime — which is 1.28:1 on white. Every "loading" state in the
      // app was a blank white area, on 48 screens, because the spinner was
      // there and could not be seen. The accent's ink value can.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.secondary,
        refreshBackgroundColor: AppColors.background,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.brand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.brandWash,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }
}
