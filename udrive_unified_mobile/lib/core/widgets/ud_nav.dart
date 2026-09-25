import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// One slot in [UdBottomNav].
///
/// Either an ordinary destination — tapping it selects that index — or the
/// customer bar's SOS button, which is a destination in the layout only: it
/// opens a sheet and never becomes the selected tab.
class UdNavDestination {
  const UdNavDestination({
    required this.icon,
    required this.label,
    this.activeIcon,
  })  : onTap = null,
        isSos = false;

  /// The raised red circle in the middle of the customer bar.
  ///
  /// It carries [onTap] itself because it is not a tab: selecting it would
  /// leave the bar highlighting a screen that is not open.
  const UdNavDestination.sos({
    required this.label,
    required this.onTap,
    this.icon = Icons.sos_rounded,
  })  : activeIcon = null,
        isSos = true;

  final IconData icon;

  /// Drawn in place of [icon] when this slot is the selected one. Optional —
  /// most of the design's icons do not change shape when active, because the
  /// lime pill behind them already says which one is open.
  final IconData? activeIcon;

  final String label;
  final VoidCallback? onTap;
  final bool isSos;
}

/// `.nav` — the bottom navigation bar of design system v2.
///
/// 86px, white, separated from the page by a 1px top border and nothing else:
/// a shadow under a bar that already sits against the bottom edge of the screen
/// only smudges the row of labels above it.
///
/// The selected tab is marked by a lime pill behind its icon, 58×34, with the
/// label below it in navy. That pill is the reason the icons do not need a
/// filled variant to show state.
///
/// This widget knows nothing about modes. `main_shell.dart` builds the customer
/// list, the driver list and the owner list and passes whichever one applies,
/// so the tabs live where the routing lives rather than in two places.
class UdBottomNav extends StatelessWidget {
  const UdBottomNav({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<UdNavDestination> destinations;

  /// Index into [destinations]. An SOS slot is never the current index.
  final int currentIndex;

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNav,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavCell(
                      destination: destinations[i],
                      selected: i == currentIndex,
                      onTap: destinations[i].onTap ?? () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final UdNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sos = destination.isSos;
    final Color labelColour = sos
        ? AppColors.danger
        : selected
            ? AppText.primary
            : AppText.secondary;

    return Semantics(
      button: true,
      selected: sos ? false : selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.field),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sos ? const _SosPill() : _Pill(destination: destination, selected: selected),
            const SizedBox(height: 5),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppType.overline.copyWith(
                letterSpacing: 0,
                fontWeight: FontWeight.w700,
                color: labelColour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.destination, required this.selected});

  final UdNavDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 58,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.transparent,
          borderRadius: AppRadii.all(17),
        ),
        child: Icon(
          selected ? (destination.activeIcon ?? destination.icon) : destination.icon,
          size: 22,
          color: selected ? AppText.onBrand : AppText.secondary,
        ),
      );
}

/// The SOS button, raised 26px out of the bar.
///
/// Its layout box is the same 34px as an ordinary pill, so the five labels
/// stay on one line; the circle is drawn above that box rather than inside it.
/// [Clip.none] is what allows that — without it the top of the circle is cut
/// off at the bar's edge.
class _SosPill extends StatelessWidget {
  const _SosPill();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 58,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              top: -26,
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  // A white ring so the circle reads as sitting on top of the
                  // bar rather than punched through it.
                  border: Border.all(color: AppColors.background, width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59B42318), // danger at 35%
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      );
}

/// A row in the side drawer.
///
/// The handoff builds this inline on both drawer screens and then notes that
/// it should be shared, because the customer drawer and the driver drawer need
/// it identically. Selected is a pale lime pill with lime ink — not the full
/// brand lime, which behind a whole row of menu items shouts louder than the
/// button it is meant to defer to.
class UdDrawerRow extends StatelessWidget {
  const UdDrawerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Color ink = selected ? AppColors.brandInk : AppText.primary;
    final Color iconInk = selected ? AppColors.brandInk : AppText.secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(13),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? AppColors.brandWash : Colors.transparent,
              borderRadius: AppRadii.all(13),
            ),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: iconInk),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontSize: 15.5,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
