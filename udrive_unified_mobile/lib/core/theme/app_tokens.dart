import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_type.dart';

/// Radii, sizes and the type scale come from `app_type.dart`, which names no
/// colour so that the theme can use it without importing this file back.
/// Re-exported here so every existing `import '../theme/app_tokens.dart'`
/// keeps seeing [AppRadii] and friends exactly as it did before.
export 'app_type.dart';

/// Tint and surface colours for design system v2.
///
/// The core brand colours stay in [AppColors]; this file adds the supporting
/// tints, shadows and text colours so that no widget hard-codes a hex value.
///
/// Every status pairing below is a *pair* — a wash, the ink that goes on it,
/// and a border — and the ink is chosen for that wash, not for white. Using
/// [AppColors.danger] on [danger] is the combination that was measured
/// (6.1:1); using it on white is a different number (6.6:1) and both are fine,
/// but putting `successText` on a white card or `dangerText` on the brand wash
/// is not something that has been checked.
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

  // ------------------------------------------------------------- status

  static const success = Color(0xFFF3FBD9);
  static const successText = Color(0xFF3F5A00); // 7.3:1 on the wash
  static const successBorder = Color(0xFFD9EE9A);

  static const danger = Color(0xFFFEF3F2);
  static const dangerText = Color(0xFFB42318); // 6.1:1 on the wash

  /// A danger outline. An opaque colour rather than an alpha over white,
  /// because these sit inside `const BorderSide` and `withValues` is not a
  /// const expression — which is what `tool/check_const_colours.py` enforces.
  static const dangerBorder = Color(0xFFF6C7C2);

  static const warning = Color(0xFFFFF6E5);
  static const warningText = Color(0xFF8A5600); // 5.7:1 on the wash
  static const warningBorder = Color(0xFFF5D9A8);

  static const info = Color(0xFFEEF4FF);
  static const infoText = Color(0xFF1B5FA8); // 5.9:1 on the wash
  static const infoBorder = Color(0xFFC9DBF7);

  /// A person's own emergency contact, as opposed to an official helpline.
  ///
  /// The one hue in the app that belongs to no part of the brand, and it is
  /// here on purpose: on the SOS sheet the difference between "Rescue 1122"
  /// and "my brother" has to be visible at a glance, in an emergency, and
  /// lime-versus-navy is not that difference — both of those are *the app*.
  /// The design keeps this purple; these three values are it, named, so the
  /// sheet does not carry raw hexes of its own.
  static const personal = Color(0xFF6C55C9); // 4.9:1 on [personalWash]
  static const personalWash = Color(0xFFF0ECFF);
  static const personalBorder = Color(0xFFDDD5FA);

  /// The grab bar at the top of a sheet, and other hairline furniture that is
  /// a shade rather than a line.
  static const handle = Color(0x1F0B1B33);

  /// The deep end of the emergency gradient, under [AppColors.danger].
  ///
  /// The safety centre's SOS card is the one place in v2 that is not white,
  /// navy or lime: a status colour keeps its own palette, and that card must
  /// not be mistaken for an ordinary one. This is its darker stop, named so
  /// the screen does not carry a hex of its own.
  static const dangerDeep = Color(0xFF8C1D18);

  /// Rating stars. Gold, and nothing else in the app is this colour.
  static const star = Color(0xFFF5B942);

  // ---------------------------------------------------------------- map

  /// Where the trip starts.
  ///
  /// Navy, not the green this used to be. In v2 the route block tells the two
  /// ends apart by *shape* — a ring for the start, a filled square for the
  /// destination — and both are drawn in brand colours. Green and orange were
  /// the only two hues left in the app that belonged to no part of the brand.
  static const pickup = AppColors.navy;

  /// Where the trip ends.
  ///
  /// Also navy, and deliberately the same value as [pickup]. The design's
  /// destination marker is a lime square *with a navy border*, and the border
  /// is what makes it legible — a bare lime icon on a white page is 1.3:1,
  /// i.e. invisible. Anything that draws the real marker should use
  /// [pinDropFill] with [pinDropBorder]; anything drawing a plain icon should
  /// use this and let the icon's shape carry the meaning.
  static const dropoff = AppColors.navy;

  /// The start marker on the map: a navy dot inside a thick white ring.
  static const pinPickupFill = AppColors.navy;
  static const pinPickupRing = Color(0xFFFFFFFF);

  /// The destination marker: a lime rounded square with a navy border.
  static const pinDropFill = AppColors.brand;
  static const pinDropBorder = AppColors.navy;

  /// The chosen route, 6px.
  static const routeActive = AppColors.navy;

  /// The routes not chosen, 4px and behind.
  static const routeAlternative = Color(0xFFA9B2BC);

  /// Behind the map while tiles are still loading, and the land colour of the
  /// design's own map artwork.
  static const mapBackdrop = Color(0xFFEAEFE7);
  static const mapPark = Color(0xFFDCE8D2);
  static const mapWater = Color(0xFFCFE3F2);

  // ------------------------------------------------------------ waiting

  /// Waiting on someone: a request out to drivers, an offer not yet answered.
  /// Amber because it is neither done nor wrong.
  static const pending = Color(0xFF8A5600);
  static const pendingBorder = Color(0xFFF5D9A8);

  /// The same amber at panel strength, for the body of a waiting or
  /// "nothing available yet" card.
  static const pendingSurface = Color(0xFFFFF6E5);

  // ------------------------------------------------------- scrims & glass

  /// Behind a sheet or a dialog. Navy at 45%, per `.scrim`.
  static const scrim = Color(0x730B1B33);

  // RETIRING with the dark screens — see the note in AppColors.
  static const inkScrim = Color(0xE80B1B33);
  static const inkVeil = Color(0xB80B1B33);
  static const inkGlass = Color(0xA80B1B33);

  /// The lightest of the glass fills.
  ///
  /// Kept even though nothing in this tree references it any more. It was
  /// deleted once, on the grounds that it was unused — which was true here and
  /// false in the repository this ships to, where an older copy of
  /// `udrive_route_flow_screen.dart` still calls it and the build stopped with
  /// "Member not found: 'inkGlassSoft'".
  ///
  /// A token costs one line. Removing one breaks every file that has not been
  /// updated yet, and a theme file is the wrong place to find out that two
  /// trees have drifted. These go when the dark screens go, together, in one
  /// change that can see all the call sites.
  static const inkGlassSoft = Color(0x840B1B33);

  // ------------------------------------------------------------ shadows

  /// Card and panel shadow colours, as const values.
  ///
  /// All three are navy, and all three are fainter than they were. On a white
  /// page a shadow is not how a card separates from the background — the
  /// hairline border is — so the shadow only has to stop the card looking
  /// painted on.
  static const shadowSoft = Color(0x0D0B1B33); // 5%  — cards at rest
  static const shadow = Color(0x140B1B33); // 8%  — raised cards
  static const shadowStrong = Color(0x240B1B33); // 14% — dialogs
}

class AppText {
  const AppText._();

  static const primary = AppColors.navy;

  /// Secondary copy. 7.0:1 on white, 6.5:1 on a grey inset.
  static const secondary = AppColors.muted;

  /// Captions of 13px and up, **on white only**. 4.9:1 — it passes, but with
  /// no margin, so it does not go on a grey inset and it never carries
  /// anything the reader has to have.
  static const caption = AppColors.caption;

  /// Disabled labels. 3.1:1 on white, which fails AA — allowed *only* on a
  /// disabled button, where the whole control is meant to read as unavailable
  /// and the text is not information the reader needs.
  static const disabled = Color(0xFF8A94A1);

  /// Text placed ON the brand lime.
  ///
  /// Navy, always. White on lime is 1.28:1 — not dim, not marginal; invisible.
  static const onBrand = AppColors.onBrand;

  /// Text on navy: a dark button, a navy hero card, a dark screen.
  static const onInk = Colors.white;

  /// Secondary text on navy. 10.8:1.
  static const onInkMuted = AppColors.onInkMuted;
}

/// Per-product colours.
///
/// Each service owns a hue so the four products read as four different things
/// rather than four shades of the brand. Flat tinted surfaces rather than
/// gradients: a gradient per card looks striking on a monitor but reads as busy
/// on a phone outdoors, and four of them compete with the map behind.
///
/// Ride is the brand's own tile and takes the brand's own colour; the others
/// are neutral, with their hue carried by the icon rather than the whole block.
/// Four saturated blocks beside a lime button was three colours too many, and
/// it is the brand tile that should win.
class AppProduct {
  const AppProduct._();

  // Ride — brand lime.
  static const rideSurface = AppColors.brand;
  static const rideAccent = AppColors.onBrand;
  static const rideTitle = AppColors.onBrand;
  static const rideSub = Color(0xFF2E3C52);
  static const rideInk = AppColors.onBrand;

  // Tour — white block with a border, warm icon.
  //
  // These were grey blocks. In v2 the secondary service tiles are white cards
  // like everything else, and grey is reserved for insets, so the tile is
  // separated by its border instead of its fill.
  static const tourSurface = AppColors.surfaceHigh;
  static const tourAccent = Color(0xFF8A5600);
  static const tourTitle = AppColors.navy;
  static const tourSub = AppColors.muted;

  // Hotel — white block, blue icon.
  static const hotelSurface = AppColors.surfaceHigh;
  static const hotelAccent = Color(0xFF16497F);
  static const hotelTitle = AppColors.navy;
  static const hotelSub = AppColors.muted;

  /// Used by the per-seat control rather than a card.
  static const seatsAccent = AppColors.brandInk;
}

/// The three elevations of design system v2, plus the two that have a shape of
/// their own.
///
/// `sh-1`, `sh-2` and `sh-3` in `ud.css`. Softer than the v1 set, and far
/// softer than the black 35–50% shadows this started as when the whole app was
/// dark — on white those printed as grey smudges under every card, visible as
/// haloes around the header icons, which is not depth, it is dirt.
class AppShadows {
  const AppShadows._();

  /// sh-1 — a card at rest. Barely there on purpose; the border does the work.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: AppTint.shadowSoft,
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// sh-2 — a raised card, a floating map button, the active segment of a
  /// segmented control.
  static const List<BoxShadow> panel = [
    BoxShadow(
      color: AppTint.shadow,
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];

  /// Controls that sit on top of the map.
  ///
  /// These are sh-2 now, where they used to be empty. On the v1 light map a
  /// white button had nothing to lift off and the shadow read as a ring of
  /// dirt; the v2 map artwork is a green-grey that a white chip does need
  /// separating from.
  static const List<BoxShadow> floating = panel;

  /// sh-3 — dialogs.
  static const List<BoxShadow> dialog = [
    BoxShadow(
      color: AppTint.shadowStrong,
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  /// A bottom sheet, shadowed upward.
  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color(0x1F0B1B33), // 12%
      blurRadius: 34,
      offset: Offset(0, -10),
    ),
  ];

  /// The bottom navigation bar. Nothing — v2 separates it with a 1px top
  /// border, and a shadow under a bar that is already against the screen edge
  /// only muddies the row of labels above it.
  static const List<BoxShadow> navBar = <BoxShadow>[];
}
