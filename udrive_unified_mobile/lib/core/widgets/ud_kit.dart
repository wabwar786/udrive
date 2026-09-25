/// Design system v2, in one import.
///
/// Every screen rebuilt against the new design imports this file and nothing
/// else from `core/widgets` — so when a component changes, it changes in one
/// place and every screen picks it up.
///
/// What lives where:
///
///   ud_button.dart    UdButton, UdButtonRow
///   ud_input.dart     UdTextField, UdLabel, UdCheckbox, UdCheckboxRow,
///                     UdRadio, UdSwitch
///   ud_surface.dart   UdCard, UdListGroup, UdListRow, UdKeyValue,
///                     UdDashedDivider, UdBanner, UdBadge, UdEmptyState
///   ud_bits.dart      UdIconButton, UdIconTile, UdAvatar, UdChip,
///                     UdSegmented, UdTabs, UdStat, UdProgress, UdSteps,
///                     UdRouteBlock
///   ud_scaffold.dart  UdTopBar, UdHeroTitle, UdSectionHeader, UdBottomBar,
///                     UdSheetHandle, showUdSheet, showUdDialog
///   ud_nav.dart       UdBottomNav, UdNavDestination, UdDrawerRow
library;

export 'ud_bits.dart';
export 'ud_button.dart';
export 'ud_input.dart';
export 'ud_nav.dart';
export 'ud_scaffold.dart';
export 'ud_surface.dart';
