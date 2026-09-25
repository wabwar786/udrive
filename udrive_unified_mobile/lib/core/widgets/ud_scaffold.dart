import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'ud_bits.dart';

/// `.bar` — the top bar of a pushed page.
///
/// White, 72px, navy title at 20/800. There are no navy header slabs in v2:
/// the bar is the same colour as the page and is separated from it, when it
/// needs to be, by a hairline.
///
/// Implements [PreferredSizeWidget] so it can go straight into
/// `Scaffold.appBar`, which is where most screens want it.
class UdTopBar extends StatelessWidget implements PreferredSizeWidget {
  const UdTopBar({
    this.title,
    this.onBack,
    this.actions = const <Widget>[],
    this.divider = false,
    this.leading,
    this.centerTitle = false,
    super.key,
  });

  final String? title;

  /// Null shows no back button at all — a tab root. To get the ordinary pop,
  /// pass `() => Navigator.maybePop(context)`; nothing is assumed, because a
  /// screen that has unsaved input usually wants to ask first.
  final VoidCallback? onBack;

  final List<Widget> actions;

  /// `.bar.line` — a 1px rule under the bar, for a page that scrolls under it.
  final bool divider;

  /// Replaces the back button: a logo, an avatar.
  final Widget? leading;

  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.topBar);

  /// White bar, so the clock and the battery have to be dark.
  ///
  /// Material's `AppBar` worked this out from its own background colour and
  /// asserted it. This bar is an ordinary widget, so it asserts it itself —
  /// otherwise the status bar falls back to whatever the last screen set,
  /// which on a white page can mean a white clock on white.
  static const _overlay = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlay,
      child: _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.topBar),
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 14, AppSizes.sidePadding, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: divider
            ? const Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (leading != null)
              leading!
            else if (onBack != null)
              UdIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: onBack,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            if (leading != null || onBack != null) const SizedBox(width: 12),
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign:
                          centerTitle ? TextAlign.center : TextAlign.start,
                      style: AppType.barTitle.copyWith(color: AppText.primary),
                    ),
            ),
            for (final action in actions) ...[
              const SizedBox(width: 10),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// `.hero-title` — the big title of a tab root, with an optional line under it.
///
/// 30/800. Bigger than a pushed page's bar title on purpose: these five screens
/// are where somebody lands with no back arrow to tell them where they are.
class UdHeroTitle extends StatelessWidget {
  const UdHeroTitle({
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
        AppSizes.sidePadding, 4, AppSizes.sidePadding, 8),
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppType.screenTitle.copyWith(color: AppText.primary)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: trailing == null
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: text),
                const SizedBox(width: 12),
                trailing!,
              ],
            ),
    );
  }
}

/// `.sec` — a section header, with an optional action on the right.
class UdSectionHeader extends StatelessWidget {
  const UdSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppType.section.copyWith(
                letterSpacing: -0.19,
                color: AppText.primary,
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  actionLabel!,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandInk,
                  ),
                ),
              ),
            ),
        ],
      );
}

/// `.foot` — the pinned bar at the bottom of a page that holds its main action.
///
/// There are no floating action buttons in this system. A screen's primary
/// action lives here, full width, where a thumb reaches it.
class UdBottomBar extends StatelessWidget {
  const UdBottomBar({
    required this.children,
    this.gap = 10,
    super.key,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(children[i]);
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 12, AppSizes.sidePadding, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// `.handle` — the grab bar at the top of a sheet.
class UdSheetHandle extends StatelessWidget {
  const UdSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 44,
          height: 5,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.borderStrong,
            borderRadius: AppRadii.all(3),
          ),
        ),
      );
}

/// `.sheet` + `.scrim` — the modal bottom sheet of design system v2.
///
/// Top corners at 28, a handle, a navy 45% scrim. [builder] returns the body
/// only; the handle, padding and shape are supplied here so every sheet in the
/// app is the same shape.
Future<T?> showUdSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showHandle = true,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(
      AppSizes.sidePadding, 10, AppSizes.sidePadding, 22),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: AppColors.surfaceHigh,
    barrierColor: AppTint.scrim,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop()),
    builder: (sheetContext) => Padding(
      // Lifts the sheet clear of the keyboard when it holds a field.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHandle) const UdSheetHandle(),
              Flexible(child: builder(sheetContext)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// `.dialog` — radius 26, padding 24/22, `sh-3`.
///
/// [actions] stack vertically rather than sitting in a row, because a 58px
/// button does not fit twice across a 390px phone with the padding this design
/// uses, and a shrunk confirm button is how people tap the wrong one.
Future<T?> showUdDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const <Widget>[],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: AppTint.scrim,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.surfaceHigh,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.dialog)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppType.h2.copyWith(color: AppText.primary)),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(
                message,
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
            ],
            if (content != null) ...[
              const SizedBox(height: 14),
              content,
            ],
            for (final action in actions) ...[
              const SizedBox(height: 10),
              action,
            ],
          ],
        ),
      ),
    ),
  );
}
