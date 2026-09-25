import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// `.ibtn` — a 46px square icon button, radius 15, 1.5px border.
enum UdIconButtonVariant {
  /// White with a border. The default.
  plain,

  /// Grey fill, no visible border.
  soft,

  /// White, no border, `sh-2`. The variant that sits on a map.
  float,
}

class UdIconButton extends StatelessWidget {
  const UdIconButton({
    required this.icon,
    required this.onPressed,
    this.variant = UdIconButtonVariant.plain,
    this.small = false,
    this.badgeDot = false,
    this.tooltip,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final UdIconButtonVariant variant;

  /// `.ibtn.sm` — 38px, radius 12.
  final bool small;

  /// A 9px danger dot with a 2px white ring, top right. Unread notifications.
  final bool badgeDot;

  final String? tooltip;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final side = small ? AppSizes.iconTileSm : AppSizes.iconButton;
    final radius = AppRadii.all(small ? 12 : 15);
    final ink = iconColor ?? AppColors.navy;

    final button = SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: switch (variant) {
            UdIconButtonVariant.plain => AppColors.background,
            UdIconButtonVariant.soft => AppColors.surface,
            UdIconButtonVariant.float => AppColors.background,
          },
          borderRadius: radius,
          border: variant == UdIconButtonVariant.plain
              ? Border.all(color: AppColors.border, width: 1.5)
              : null,
          boxShadow: variant == UdIconButtonVariant.float
              ? AppShadows.floating
              : const <BoxShadow>[],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: small ? 18 : 22, color: ink),
                if (badgeDot)
                  Positioned(
                    top: small ? 6 : 9,
                    right: small ? 7 : 10,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.background,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // The visual is 46px but the design's minimum tap target is 44, so the
    // plain size already clears it; the small variant does not, and gets the
    // difference back as invisible padding rather than by growing.
    final tappable = small
        ? SizedBox(
            width: AppSizes.minTouch,
            height: AppSizes.minTouch,
            child: Center(child: button),
          )
        : button;

    return tooltip == null
        ? tappable
        : Tooltip(message: tooltip!, child: tappable);
  }
}

/// `.ico` — a rounded tile holding an icon. Not a button; the row around it is.
enum UdIconTone {
  /// Grey tile, navy icon. The default.
  neutral,

  /// Lime tile, navy icon.
  lime,

  /// Pale lime tile, lime-ink icon.
  soft,

  /// Navy tile, lime icon.
  navy,
  red,
  warn,
  info,
}

enum UdIconTileSize { sm, md, lg }

class UdIconTile extends StatelessWidget {
  const UdIconTile({
    required this.icon,
    this.tone = UdIconTone.neutral,
    this.size = UdIconTileSize.md,
    super.key,
  });

  final IconData icon;
  final UdIconTone tone;
  final UdIconTileSize size;

  @override
  Widget build(BuildContext context) {
    final (double side, double radius, double iconSize) = switch (size) {
      UdIconTileSize.sm => (AppSizes.iconTileSm, 12.0, 18.0),
      UdIconTileSize.md => (AppSizes.iconTile, AppRadii.tile, 22.0),
      UdIconTileSize.lg => (AppSizes.iconTileLg, 18.0, 26.0),
    };

    final (Color background, Color ink) = switch (tone) {
      UdIconTone.neutral => (AppColors.surface, AppColors.navy),
      UdIconTone.lime => (AppColors.brand, AppText.onBrand),
      UdIconTone.soft => (AppColors.brandWash, AppColors.brandInk),
      UdIconTone.navy => (AppColors.navy, AppColors.brand),
      UdIconTone.red => (AppTint.danger, AppTint.dangerText),
      UdIconTone.warn => (AppTint.warning, AppTint.warningText),
      UdIconTone.info => (AppTint.info, AppTint.infoText),
    };

    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(radius),
      ),
      child: Icon(icon, size: iconSize, color: ink),
    );
  }
}

/// `.av` — a navy circle with lime initials.
class UdAvatar extends StatelessWidget {
  const UdAvatar({
    required this.initials,
    this.size = 52,
    this.lime = false,
    super.key,
  });

  /// Take these from the name at the call site; the widget does not guess.
  final String initials;

  /// 40 small, 52 default, 76 large.
  final double size;

  /// Flips the pairing: lime circle, navy initials.
  final bool lime;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lime ? AppColors.brand : AppColors.navy,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: AppType.h2.copyWith(
          // 19 at 52px, scaled so the smaller and larger sizes keep the ratio.
          fontSize: size * 0.365,
          color: lime ? AppText.onBrand : AppColors.brand,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// `.chip` — a 40px pill, 14.5/700.
class UdChip extends StatelessWidget {
  const UdChip({
    required this.label,
    this.onTap,
    this.selected = false,
    this.lime = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;

  /// `.chip.on` — navy fill, white label.
  final bool selected;

  /// `.chip.lime` — lime fill, navy label. A chip that is *stating* something
  /// rather than offering a choice.
  final bool lime;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color background = lime
        ? AppColors.brand
        : selected
            ? AppColors.navy
            : AppColors.background;
    final Color ink = lime
        ? AppText.onBrand
        : selected
            ? AppText.onInk
            : AppText.primary;
    final Color border = lime
        ? AppColors.brand
        : selected
            ? AppColors.navy
            : AppColors.border;

    final chip = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(AppRadii.chip),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: AppType.listTitle.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.chip),
        child: chip,
      ),
    );
  }
}

/// `.seg` — a segmented control. Grey track, white raised active segment.
class UdSegmented extends StatelessWidget {
  const UdSegmented({
    required this.options,
    required this.index,
    required this.onChanged,
    super.key,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.field),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  height: AppSizes.buttonSmall,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? AppColors.surfaceHigh
                        : Colors.transparent,
                    borderRadius: AppRadii.all(12),
                    boxShadow:
                        i == index ? AppShadows.panel : const <BoxShadow>[],
                  ),
                  child: Text(
                    options[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.buttonSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: i == index
                          ? AppText.primary
                          : AppText.secondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.tabs` — underline tabs on a hairline rule, 15.5/700.
class UdTabs extends StatelessWidget {
  const UdTabs({
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSizes.sidePadding),
    super.key,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: EdgeInsets.only(right: i == tabs.length - 1 ? 0 : 22),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == index
                            ? AppColors.navy
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    tabs[i],
                    style: AppType.listTitle.copyWith(
                      fontSize: 15.5,
                      color: i == index
                          ? AppText.primary
                          : AppText.secondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.stat` — a number over its label.
class UdStat extends StatelessWidget {
  const UdStat({
    required this.value,
    required this.label,
    this.onDark = false,
    this.align = CrossAxisAlignment.start,
    super.key,
  });

  final String value;
  final String label;

  /// Inside a navy card, where the label takes [AppText.onInkMuted].
  final bool onDark;

  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppType.priceMd.copyWith(
              fontSize: 26,
              letterSpacing: -0.52,
              color: onDark ? AppText.onInk : AppText.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 13.5,
              color: onDark ? AppText.onInkMuted : AppText.secondary,
            ),
          ),
        ],
      );
}

/// `.bar-track` + `.bar-fill` — an 8px progress bar.
class UdProgress extends StatelessWidget {
  const UdProgress({
    required this.value,
    this.height = 8,
    this.lime = false,
    super.key,
  });

  /// 0 to 1. Null is not accepted: an indeterminate bar is a different widget
  /// and a different promise.
  final double value;

  final double height;

  /// The lime line rather than navy — for a step in progress rather than done.
  final bool lime;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: AppRadii.all(height / 2),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: AppColors.surfaceAlt,
          valueColor: AlwaysStoppedAnimation(
            lime ? AppColors.limeLine : AppColors.navy,
          ),
        ),
      );
}

/// `.steps` — one 6px segment per step: navy behind, lime at the current one,
/// grey ahead.
///
/// Named [UdSteps] and not `UdStepper`, because `ud_controls.dart` already has
/// a `UdStepper` and it is the −/+ counter on the passenger and seat rows. Two
/// unrelated widgets cannot share a name, and renaming the counter would touch
/// screens this phase is not rebuilding.
class UdSteps extends StatelessWidget {
  const UdSteps({
    required this.total,
    required this.current,
    super.key,
  });

  final int total;

  /// Zero-based.
  final int current;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                decoration: BoxDecoration(
                  color: i < current
                      ? AppColors.navy
                      : i == current
                          ? AppColors.limeLine
                          : AppColors.surfaceAlt,
                  borderRadius: AppRadii.all(3),
                ),
              ),
            ),
        ],
      );
}

/// `.route` — the from/to block.
///
/// The rail tells the two ends apart by shape, not by hue: an open navy ring
/// for where you are, a lime square with a navy border for where you are going.
/// That is what replaced the green and orange dots, which were the only two
/// colours left in the app belonging to no part of the brand — and which a
/// colour-blind rider could not tell apart anyway.
class UdRouteBlock extends StatelessWidget {
  const UdRouteBlock({
    required this.fromLabel,
    required this.fromValue,
    required this.toLabel,
    required this.toValue,
    this.onTapFrom,
    this.onTapTo,
    this.fromPlaceholder,
    this.toPlaceholder,
    this.trailingFrom,
    this.trailingTo,
    super.key,
  });

  final String fromLabel;
  final String? fromValue;
  final String toLabel;
  final String? toValue;
  final VoidCallback? onTapFrom;
  final VoidCallback? onTapTo;

  /// Shown, in the caption colour, when the value is null or empty.
  final String? fromPlaceholder;
  final String? toPlaceholder;

  final Widget? trailingFrom;
  final Widget? trailingTo;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight, and it is not optional.
    //
    // The rail has to be exactly as tall as the two stops beside it, which is
    // what `CrossAxisAlignment.stretch` asks for — but stretch takes the row's
    // height from its own constraints, and inside a scrolling column those are
    // unbounded. In a debug build that trips an assertion; in a release build
    // the assertions are gone, so the row simply becomes infinitely tall and
    // every widget after it is pushed past the end of the scroll view. That is
    // the "only the map shows, the rest is blank" screen: the card was there,
    // a mile below the fold.
    //
    // IntrinsicHeight measures the children first and gives the row a real
    // height, so stretch has something finite to stretch to.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        const SizedBox(width: 22, child: UdRouteRail()),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RouteStop(
                label: fromLabel,
                value: fromValue,
                placeholder: fromPlaceholder,
                onTap: onTapFrom,
                trailing: trailingFrom,
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              _RouteStop(
                label: toLabel,
                value: toValue,
                placeholder: toPlaceholder,
                onTap: onTapTo,
                trailing: trailingTo,
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }
}

/// The rail beside a from/to pair: a navy ring, a line, a lime square.
///
/// Public because two screens draw their own stops beside it — the place
/// search, where one end is a live text field, and the route flow. It must be
/// given a bounded height, which in practice means an [IntrinsicHeight] around
/// the row it sits in.
class UdRouteRail extends StatelessWidget {
  const UdRouteRail({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppTint.pinPickupFill, width: 3),
              ),
            ),
            const Expanded(
              child: SizedBox(
                width: 2,
                child: ColoredBox(color: AppColors.borderStrong),
              ),
            ),
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: AppTint.pinDropFill,
                borderRadius: AppRadii.all(3),
                border: Border.all(color: AppTint.pinDropBorder, width: 2.5),
              ),
            ),
          ],
        ),
      );
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    required this.trailing,
  });

  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final filled = (value ?? '').trim().isNotEmpty;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppType.overline.copyWith(color: AppText.secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  filled ? value! : (placeholder ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.listTitle.copyWith(
                    fontSize: 16.5,
                    color: filled ? AppText.primary : AppText.caption,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(10),
        child: content,
      ),
    );
  }
}
