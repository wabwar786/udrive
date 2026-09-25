import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// `.card` and its variants.
enum UdCardTone {
  /// White, 1px [AppColors.border], `sh-1`. The default card.
  plain,

  /// White, no border, `sh-2`. A card that has to lift off a map or a photo.
  raised,

  /// White, 1px border, no shadow.
  flat,

  /// Grey fill, no border, no shadow — `.card.tint`. An inset group inside a
  /// white page, which is the only thing grey is for in v2.
  tint,

  /// Lime. Carries [AppText.onBrand] and nothing else.
  lime,

  /// Navy. Carries white, [AppText.onInkMuted] or lime.
  navy,
}

/// The card of design system v2 — radius 20, padding 16.
///
/// [selected] overrides the tone's edge with `.card.sel`: a 2px navy border and
/// a [AppColors.brandWash] fill. The padding drops by the extra border width so
/// the contents do not shift when a card is picked, which is what made the
/// v1 selection state jump.
class UdCard extends StatelessWidget {
  const UdCard({
    required this.child,
    this.tone = UdCardTone.plain,
    this.selected = false,
    this.padding,
    this.radius = AppRadii.card,
    this.onTap,
    this.margin,
    this.width,
    super.key,
  });

  final Widget child;
  final UdCardTone tone;
  final bool selected;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final borderRadius = AppRadii.all(radius);

    final Color background = switch (tone) {
      UdCardTone.plain ||
      UdCardTone.raised ||
      UdCardTone.flat =>
        AppColors.surfaceHigh,
      UdCardTone.tint => AppColors.surface,
      UdCardTone.lime => AppColors.brand,
      UdCardTone.navy => AppColors.navy,
    };

    final bool hasBorder =
        tone == UdCardTone.plain || tone == UdCardTone.flat;

    final List<BoxShadow> shadow = switch (tone) {
      UdCardTone.plain => AppShadows.card,
      UdCardTone.raised => AppShadows.panel,
      _ => const <BoxShadow>[],
    };

    final effectivePadding = padding ??
        EdgeInsets.all(selected && tone != UdCardTone.tint ? 15 : 16);

    final decorated = Container(
      width: width,
      margin: margin,
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: selected ? AppColors.brandWash : background,
        borderRadius: borderRadius,
        border: selected
            ? Border.all(color: AppColors.navy, width: 2)
            : hasBorder
                ? Border.all(color: AppColors.border)
                : null,
        boxShadow: shadow,
      ),
      child: child,
    );

    if (onTap == null) return decorated;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: decorated,
      ),
    );
  }
}

/// `.list` — a white rounded group with hairline dividers between its rows.
///
/// The rows are clipped to the group's radius, so a row's ink splash cannot
/// paint over the rounded corner.
class UdListGroup extends StatelessWidget {
  const UdListGroup({
    required this.children,
    this.radius = AppRadii.card,
    this.bordered = true,
    super.key,
  });

  final List<Widget> children;
  final double radius;

  /// False drops the outer border — for a group already inside a card.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(
          height: 1,
          thickness: 1,
          color: AppColors.border,
        ));
      }
      rows.add(children[i]);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.all(radius),
        border: bordered ? Border.all(color: AppColors.border) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// `.li` — one row of a [UdListGroup]. 64px minimum, padding 14/16.
class UdListRow extends StatelessWidget {
  const UdListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.titleColor,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Whatever goes at the right edge. [showChevron] adds the standard one
  /// instead, so the common case does not need a widget.
  final Widget? trailing;

  final VoidCallback? onTap;
  final bool showChevron;

  /// For the one row in a group that is destructive — "Delete account".
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppType.listTitle.copyWith(
                    fontSize: 16,
                    color: titleColor ?? AppText.primary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded,
                size: 22, color: AppText.caption),
          ],
        ],
      ),
    );

    final sized = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.listRow),
      child: row,
    );

    if (onTap == null) return sized;
    return Material(
      color: AppColors.surfaceHigh,
      child: InkWell(onTap: onTap, child: sized),
    );
  }
}

/// `.kv` — a label on the left, a value on the right, a dashed rule under it.
///
/// [total] is the last line of a fare breakdown: both halves go to 18/800 and
/// the rule is dropped.
class UdKeyValue extends StatelessWidget {
  const UdKeyValue({
    required this.label,
    required this.value,
    this.total = false,
    this.showDivider = true,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final bool total;
  final bool showDivider;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelStyle = total
        ? AppType.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800)
        : AppType.body2.copyWith(fontSize: 15, color: AppText.secondary);
    final valueStyle = total
        ? AppType.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800)
        : AppType.body2.copyWith(fontSize: 15, fontWeight: FontWeight.w700);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: labelStyle)),
              const SizedBox(width: 12),
              Text(
                value,
                textAlign: TextAlign.right,
                style: valueStyle.copyWith(
                  color: valueColor ?? AppText.primary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider && !total) const UdDashedDivider(),
      ],
    );
  }
}

/// `.dash` — a 1.5px dashed rule. CSS gets this from `border-style`; Flutter
/// has no dashed border, so it is painted.
class UdDashedDivider extends StatelessWidget {
  const UdDashedDivider({
    this.color = AppColors.border,
    this.thickness = 1.5,
    this.dash = 4,
    this.gap = 4,
    super.key,
  });

  final Color color;
  final double thickness;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: thickness,
        width: double.infinity,
        child: CustomPaint(
          painter: _DashedLinePainter(
            colour: color,
            thickness: thickness,
            dash: dash,
            gap: gap,
          ),
        ),
      );
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({
    required this.colour,
    required this.thickness,
    required this.dash,
    required this.gap,
  });

  final Color colour;
  final double thickness;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) =>
      old.colour != colour ||
      old.thickness != thickness ||
      old.dash != dash ||
      old.gap != gap;
}

/// The five tints a banner or a badge can take.
enum UdTone { ok, warn, err, info, gray, dark, lime }

/// `.banner` — radius 16, padding 14/16, 14.5/500, a 1px tinted border.
///
/// [text] or [child], not both: [child] is for a banner with a bold word or a
/// link inside it, which is most of them.
class UdBanner extends StatelessWidget {
  const UdBanner({
    this.text,
    this.child,
    this.tone = UdTone.gray,
    this.icon,
    this.trailing,
    this.onTap,
    super.key,
  }) : assert(text != null || child != null,
            'A banner needs either text or a child.');

  final String? text;
  final Widget? child;
  final UdTone tone;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color ink, Color border) = switch (tone) {
      UdTone.ok => (AppTint.success, AppTint.successText, AppTint.successBorder),
      UdTone.warn => (AppTint.warning, AppTint.warningText, AppTint.warningBorder),
      UdTone.err => (AppTint.danger, AppTint.dangerText, AppTint.dangerBorder),
      UdTone.info => (AppTint.info, AppTint.infoText, AppTint.infoBorder),
      UdTone.dark => (AppColors.navy, AppText.onInk, AppColors.navy),
      UdTone.lime => (AppColors.brand, AppText.onBrand, AppColors.brand),
      UdTone.gray => (AppColors.surface, AppText.secondary, AppColors.surface),
    };

    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(AppRadii.field),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: ink),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: DefaultTextStyle(
              style: AppType.body2.copyWith(fontSize: 14.5, color: ink),
              child: child ?? Text(text!),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.field),
        child: body,
      ),
    );
  }
}

/// `.badge` — a 28px pill, 13/700.
class UdBadge extends StatelessWidget {
  const UdBadge({
    required this.label,
    this.tone = UdTone.gray,
    this.icon,
    super.key,
  });

  final String label;
  final UdTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color ink) = switch (tone) {
      UdTone.ok => (AppTint.success, AppTint.successText),
      UdTone.warn => (AppTint.warning, AppTint.warningText),
      UdTone.err => (AppTint.danger, AppTint.dangerText),
      UdTone.info => (AppTint.info, AppTint.infoText),
      UdTone.dark => (AppColors.navy, AppText.onInk),
      UdTone.lime => (AppColors.brand, AppText.onBrand),
      UdTone.gray => (AppColors.surfaceAlt, AppText.primary),
    };

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: ink),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.empty` — the nothing-here state. A 72px icon tile, a title and one
/// paragraph, with an optional action under it.
class UdEmptyState extends StatelessWidget {
  const UdEmptyState({
    required this.icon,
    required this.title,
    this.text,
    this.action,
    this.tone = UdTone.gray,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  final UdTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color ink) = switch (tone) {
      UdTone.ok => (AppTint.success, AppTint.successText),
      UdTone.warn => (AppTint.warning, AppTint.warningText),
      UdTone.err => (AppTint.danger, AppTint.dangerText),
      UdTone.info => (AppTint.info, AppTint.infoText),
      UdTone.dark => (AppColors.navy, AppColors.brand),
      UdTone.lime => (AppColors.brandWash, AppColors.brandInk),
      UdTone.gray => (AppColors.surface, AppColors.navy),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadii.all(AppRadii.panel),
            ),
            child: Icon(icon, size: 32, color: ink),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.h2.copyWith(fontSize: 20, letterSpacing: -0.2),
          ),
          if (text != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Text(
                text!,
                textAlign: TextAlign.center,
                style: AppType.body2.copyWith(
                  fontSize: 15.5,
                  height: 1.5,
                  color: AppText.secondary,
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
