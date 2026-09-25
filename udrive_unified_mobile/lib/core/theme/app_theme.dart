import 'package:flutter/material.dart';

import 'app_type.dart';

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
///   dark-lime on white 7.90:1   the accent when it has to be ink
///
/// So lime is a *surface*, never ink, and never carries white. Where the accent
/// has to be text or an icon on a white page it is [secondary], which is now
/// the kit's deeper lime ink.
///
/// ---------------------------------------------------------------------------
/// DESIGN SYSTEM v2
/// ---------------------------------------------------------------------------
///
/// These values come from `UDrive-Design-v2/HANDOFF.md` §2 and `html/ud.css`.
/// Brand lime and navy are unchanged; what moved is the neutrals and the status
/// colours, and every one of them moved for the same reason — the old value did
/// not pass WCAG AA as text:
///
///   muted   #6B7684 → #4E5A6B   4.6:1 → 7.0:1
///   danger  #FF4D4F → #B42318   3.3:1 → 6.6:1  (the old one failed outright)
///   success #5E7A00 → #3F5A00   4.9:1 → 7.9:1
///   warning #A76A00 → #8A5600   4.4:1 → 5.7:1
///
/// This class was **merged** with the v2 token file rather than replaced by it.
/// The design file omits the `ink*` family and a few others that the app is
/// still using; dropping them would have stopped the app compiling. See the
/// note above [inkDeep] for when those go.
class AppColors {
  // ------------------------------------------------------------------ brand

  /// Brand lime. A surface colour: put [onBrand] on top of it, never white.
  static const brand = Color(0xFFC6F432);

  /// The only ink that belongs on [brand].
  static const onBrand = Color(0xFF0B1B33);

  /// A pale lime wash, for selected tiles and badges that must not shout.
  static const brandWash = Color(0xFFF3FBD9);

  /// The accent where it has to be ink, or a fill under white text.
  ///
  /// Lime itself is unreadable at 1.28:1 on white. This is the kit's deeper
  /// lime: 7.9:1 on white and 7.3:1 on [brandWash], so it is safe as link text
  /// and as "success" copy at any size — which the previous #5E7A00 was not.
  static const brandInk = Color(0xFF3F5A00);

  /// Kept as aliases so existing call sites keep working.
  static const secondary = brandInk;
  static const accent = brandInk;

  /// The focus ring drawn outside a focused field — 4px of this, then the
  /// navy border. Pale enough not to read as a second border.
  static const limeGlow = Color(0xFFE8F8B8);

  /// Dashed accents and the "current" segment of a progress stepper. Lime
  /// itself disappears at 2px on white; this holds a thin line.
  static const limeLine = Color(0xFF9BC417);

  // --------------------------------------------------------------- surfaces

  /// The app background behind everything. White, and v2 means it — screens,
  /// top bars and cards are all white now, and [surface] is reserved for small
  /// inset groups inside them.
  static const background = Color(0xFFFFFFFF);

  /// Inset groups only: a search field, a route box, a segmented control.
  ///
  /// This is no longer the colour of cards. In v1 cards were grey on a white
  /// page; in v2 a card is white with a hairline [border], and grey marks the
  /// things that are *recessed* into a card rather than the card itself.
  static const surface = Color(0xFFF5F7F9);

  /// One step further from white: progress tracks, disabled buttons.
  static const surfaceAlt = Color(0xFFEEF1F4);

  /// Elevated sheets and dialogs.
  static const surfaceHigh = Color(0xFFFFFFFF);

  // ------------------------------------------------------------------- ink

  /// Structural rather than decorative: headings, and the casing under the
  /// route line.
  static const primary = Color(0xFF0B1B33);

  /// Navy, for text on light surfaces.
  static const primaryDark = Color(0xFF0B1B33);
  static const navy = Color(0xFF0B1B33);

  /// `--navy-2` — one step lighter than [navy].
  ///
  /// For a rule or a division *inside* a navy card, where [border] would be a
  /// bright grey line across a dark panel and white at any opacity would read
  /// as a second piece of content.
  static const navyLine = Color(0xFF1B2A44);

  /// Body copy.
  static const text = Color(0xFF0B1B33);

  /// Secondary copy. 7.0:1 on white and 6.5:1 on [surface] — so unlike the
  /// value it replaces, it is safe on small print inside a card.
  static const muted = Color(0xFF4E5A6B);

  /// Captions of 13px and above, on white only. 4.9:1 — it clears AA for body
  /// text but has no margin, so it does not go on [surface] under 13px and it
  /// never carries anything important.
  static const caption = Color(0xFF667182);

  // ----------------------------------------------------------------- lines

  /// Card and list borders. In v2 this does most of the work that shadows used
  /// to do.
  static const border = Color(0xFFE3E7EC);

  /// Input borders and unchecked controls. Darker than [border], because a
  /// field the user is meant to type into has to announce its edge.
  static const borderStrong = Color(0xFFCBD2DA);

  // ---------------------------------------------------------------- status

  /// 6.6:1 on white, 6.1:1 on the danger wash, and white on it is 6.6:1 — so
  /// it works as text, as a border and as a filled SOS button.
  ///
  /// Replaces #FF4D4F, which measured 3.3:1 as text on white and so failed AA
  /// everywhere it was used as a label rather than a fill.
  static const danger = Color(0xFFB42318);

  static const success = brandInk;
  static const info = Color(0xFF1B5FA8);
  static const warning = Color(0xFF8A5600);

  // ----------------------------------------------------- dark surfaces
  //
  // RETIRING. In design v2 every screen is white, including the five that are
  // still dark in the code today: the customer trip tracker and driver
  // navigation (C-30, D-20), the route flow (C-09, C-10) and the hotel browser
  // (C-42, C-43).
  //
  // They stay defined because those screens have not been converted yet and
  // the app has to keep compiling in the meantime. Once the last of them is
  // rebuilt, this block and the ink* entries in AppTint come out together. Do
  // not use them on anything new.

  /// Behind everything on a dark screen, and the far end of a dark gradient.
  static const inkDeep = Color(0xFF071224);

  /// The dark screen's ground. The same navy as the ink on a light page.
  static const inkSurface = Color(0xFF0B1B33);

  /// Cards and sheets on a dark screen.
  static const inkPanel = Color(0xFF122540);

  /// Rows, fields and pressed states, one step lighter again.
  static const inkTile = Color(0xFF1B3050);

  /// Body copy on navy — on a dark screen, and on the one navy hero card a
  /// white screen is allowed.
  static const onInk = Color(0xFFFFFFFF);

  /// Secondary copy on navy. 10.8:1, up from 7.8:1, because v2 uses navy cards
  /// on white pages where this text sits next to full-white headings and the
  /// old value read as disabled rather than secondary.
  static const onInkMuted = Color(0xFFC4CEDB);
}

class AppTheme {
  /// The app's single theme. [light] and [dark] are the same object; both names
  /// are kept so existing call sites keep working.
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
      secondary: AppColors.brandInk,
      onSecondary: Colors.white,
      surface: AppColors.background,
      onSurface: AppColors.text,
      error: AppColors.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,

      // Plus Jakarta Sans, bundled in assets/fonts rather than fetched at run
      // time.
      //
      // This was `GoogleFonts.poppins()`, which downloads the font on first
      // use. In Azad Kashmir that means the first launch on a weak connection
      // renders the whole app in the platform fallback — every size and weight
      // in the design lands on different metrics, and the person who sees that
      // is the person least able to reload it. The five weights are 172 KB in
      // the APK and the `google_fonts` dependency is gone entirely.
      fontFamily: AppType.family,
      visualDensity: VisualDensity.compact,

      textTheme: const TextTheme(
        displayLarge: AppType.display,
        headlineLarge: AppType.h1,
        headlineMedium: AppType.h2,
        titleLarge: AppType.section,
        titleMedium: AppType.listTitle,
        bodyLarge: AppType.body,
        bodyMedium: AppType.body2,
        bodySmall: AppType.caption,
        labelLarge: AppType.button,
      ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),

      // White bars with navy text. v2 removes the navy header slabs entirely —
      // navy is kept for text, dark buttons, selected chips, avatars and at
      // most one hero card per screen.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppType.barTitle,
      ),

      // A card is white with a hairline border and almost no shadow. The border
      // is what separates it from the page; the shadow only stops it floating.
      cardTheme: CardThemeData(
        color: AppColors.surfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.navy.withValues(alpha: .05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // Fields are white, not grey. The 4px lime focus ring the design shows
      // cannot be expressed here — InputDecorationTheme has one border, not a
      // border plus an outer ring — so it lives in UdTextField. This keeps the
      // 2px navy focus border, which is the part that carries the meaning.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        hintStyle: const TextStyle(
          color: AppColors.caption,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.navy, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        errorStyle: const TextStyle(
          color: AppColors.danger,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),

      // The brand pairing, in the one place that covers most primary actions.
      // 58px and radius 17 come straight from `.btn` in ud.css.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          disabledBackgroundColor: AppColors.surfaceAlt,
          // AppText.disabled, inlined: AppText lives in app_tokens.dart, which
          // imports this file. Naming the value here keeps the chain one-way.
          disabledForegroundColor: const Color(0xFF8A94A1),
          elevation: 0,
          minimumSize: const Size.fromHeight(AppSizes.button),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.cta),
          ),
          textStyle: AppType.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          backgroundColor: AppColors.background,
          minimumSize: const Size.fromHeight(AppSizes.button),
          side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.cta),
          ),
          textStyle: AppType.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandInk,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      // Material's NavigationBar is not what v2 draws — the design has a 86px
      // bar with a lime pill behind the active icon and a raised SOS circle,
      // which is UdBottomNav. This keeps the Material one consistent for
      // anything still using it.
      navigationBarTheme: NavigationBarThemeData(
        height: AppSizes.bottomNav,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brand,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? AppColors.navy
                : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.onBrand
                : AppColors.muted,
          ),
        ),
      ),

      // Spinners take colorScheme.primary unless told otherwise, and primary
      // is lime — 1.28:1 on white. Every "loading" state in the app would be a
      // blank white area with an invisible spinner in it. The accent's ink
      // value is 7.9:1.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandInk,
        linearTrackColor: AppColors.surfaceAlt,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: AppColors.background,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.brand,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Pills, not rounded rectangles. `.chip` is 40px at radius 999.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        selectedColor: AppColors.navy,
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        labelStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        titleTextStyle: AppType.h2,
        contentTextStyle: AppType.body,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBackgroundColor: AppColors.surfaceHigh,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.brand
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.navy
              : AppColors.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.navy
              : AppColors.borderStrong,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.brand
              : Colors.white,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.navy),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.navy
              : AppColors.borderStrong,
        ),
      ),
    );
  }
}
