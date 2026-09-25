import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// The seven button fills of design system v2 (`.btn.*` in `ud.css`).
///
/// There is no eighth. A screen that needs a button this list does not cover is
/// a screen whose design has drifted, and the fix is to pick one of these
/// rather than to add a colour here.
enum UdButtonVariant {
  /// Lime. The one thing the screen wants you to do — never more than one.
  primary,

  /// Navy with white text. A second action of equal weight, or the primary
  /// action on a screen whose accent is already spent.
  dark,

  /// White with a 1.5px border.
  outline,

  /// Grey fill, no border. Quieter than [outline] and used inside cards.
  soft,

  /// No fill at all.
  ghost,

  /// A destructive action offered, not urged: danger wash, danger ink.
  danger,

  /// A destructive action being confirmed. Solid danger, white text (6.6:1).
  dangerSolid,
}

/// The three heights: `.btn`, `.btn.sm`, `.btn.xs`.
enum UdButtonSize { large, small, xs }

/// The button of design system v2.
///
/// 58px tall, radius 17, label 17/800 — and every one of those numbers is the
/// same on every screen, which is the whole point of the widget. The Material
/// theme still styles `FilledButton` and friends for anything not yet
/// converted; this is what the converted screens use.
///
/// Disabled is a *fill*, not an opacity: `.btn.disabled` is the grey
/// [AppColors.surfaceAlt] with [AppText.disabled] on it. That pairing is 3.1:1,
/// which fails AA — deliberately, and only here, because a disabled control is
/// meant to read as unavailable and its label is not information anyone needs.
/// Nothing else in the app may use that colour.
class UdButton extends StatelessWidget {
  const UdButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = UdButtonVariant.primary,
    this.size = UdButtonSize.large,
    this.busy = false,
    this.expand = true,
    this.semanticLabel,
    super.key,
  });

  /// A lime button that fills its row. The common case.
  const UdButton.primary({
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = UdButtonSize.large,
    this.busy = false,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : variant = UdButtonVariant.primary;

  const UdButton.dark({
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = UdButtonSize.large,
    this.busy = false,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : variant = UdButtonVariant.dark;

  const UdButton.outline({
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = UdButtonSize.large,
    this.busy = false,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : variant = UdButtonVariant.outline;

  const UdButton.soft({
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = UdButtonSize.large,
    this.busy = false,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : variant = UdButtonVariant.soft;

  const UdButton.ghost({
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = UdButtonSize.large,
    this.busy = false,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : variant = UdButtonVariant.ghost;

  final String label;

  /// Null disables the button. [busy] disables it too, without the caller
  /// having to null this out and lose it.
  final VoidCallback? onPressed;

  final IconData? icon;
  final IconData? trailingIcon;
  final UdButtonVariant variant;
  final UdButtonSize size;

  /// Replaces [icon] with a spinner and blocks the tap.
  final bool busy;

  /// False makes the button only as wide as its label — `.btn.auto`.
  final bool expand;

  final String? semanticLabel;

  double get _height => switch (size) {
        UdButtonSize.large => AppSizes.button,
        UdButtonSize.small => AppSizes.buttonSmall,
        UdButtonSize.xs => AppSizes.buttonXs,
      };

  double get _radius => switch (size) {
        UdButtonSize.large => AppRadii.cta,
        UdButtonSize.small => AppRadii.row,
        UdButtonSize.xs => 12,
      };

  double get _hPadding => switch (size) {
        UdButtonSize.large => 20,
        UdButtonSize.small => 16,
        UdButtonSize.xs => 14,
      };

  double get _iconSize => size == UdButtonSize.large ? 22 : 18;

  TextStyle get _textStyle => switch (size) {
        UdButtonSize.large => AppType.button,
        UdButtonSize.small => AppType.buttonSm,
        UdButtonSize.xs => AppType.buttonSm.copyWith(fontSize: 14),
      };

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;

    // Resolved together so the pair is always one of the checked combinations
    // from HANDOFF §3 — picking a fill in one place and an ink in another is
    // how white-on-lime happens.
    final (Color background, Color foreground, BorderSide? side) =
        _palette(disabled);

    final radius = AppRadii.all(_radius);

    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel,
      child: SizedBox(
        height: _height,
        width: expand ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: side == null ? null : Border.fromBorderSide(side),
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: radius,
            child: InkWell(
              onTap: disabled ? null : onPressed,
              borderRadius: radius,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _hPadding),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      SizedBox(
                        width: _iconSize,
                        height: _iconSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, size: _iconSize, color: foreground),
                    if (busy || icon != null) const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _textStyle.copyWith(color: foreground),
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 10),
                      Icon(trailingIcon, size: _iconSize, color: foreground),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, BorderSide?) _palette(bool disabled) {
    if (disabled) {
      // `.btn.disabled`. The outline and ghost variants keep their shape so a
      // row of buttons does not change size when one of them turns off.
      return switch (variant) {
        UdButtonVariant.outline => (
            AppColors.background,
            AppText.disabled,
            const BorderSide(color: AppColors.border, width: 1.5),
          ),
        UdButtonVariant.ghost => (
            Colors.transparent,
            AppText.disabled,
            null,
          ),
        _ => (AppColors.surfaceAlt, AppText.disabled, null),
      };
    }

    return switch (variant) {
      UdButtonVariant.primary => (AppColors.brand, AppText.onBrand, null),
      UdButtonVariant.dark => (AppColors.navy, AppText.onInk, null),
      UdButtonVariant.outline => (
          AppColors.background,
          AppText.primary,
          const BorderSide(color: AppColors.borderStrong, width: 1.5),
        ),
      UdButtonVariant.soft => (AppColors.surface, AppText.primary, null),
      UdButtonVariant.ghost => (Colors.transparent, AppText.primary, null),
      UdButtonVariant.danger => (
          AppTint.danger,
          AppTint.dangerText,
          const BorderSide(color: AppTint.dangerBorder, width: 1.5),
        ),
      UdButtonVariant.dangerSolid => (
          AppColors.danger,
          AppText.onInk,
          null,
        ),
    };
  }
}

/// A row of buttons, `.btns` — 10px apart, each taking an equal share.
class UdButtonRow extends StatelessWidget {
  const UdButtonRow({required this.children, this.gap = 10, super.key});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final row = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) row.add(SizedBox(width: gap));
      row.add(Expanded(child: children[i]));
    }
    return Row(children: row);
  }
}
