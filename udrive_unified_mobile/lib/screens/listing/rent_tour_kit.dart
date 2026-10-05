import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

/// Small pieces shared by the owner's rent and tour-departure screens: the
/// navy header, the section label, the tag and the Monday-first month grid.

/// Navy header with a back square, a title and a one-line subtitle.
class RentNavyHeader extends StatelessWidget {
  const RentNavyHeader({
    required this.title,
    this.subtitle,
    this.bottom,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Defaults to an ordinary pop.
  final VoidCallback? onBack;

  /// Buttons under the title, still on navy.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: Material(
                      color: AppColors.navyLine,
                      borderRadius: AppRadii.all(14),
                      child: InkWell(
                        onTap: onBack ?? () => Navigator.maybePop(context),
                        borderRadius: AppRadii.all(14),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.chevron_left_rounded,
                              size: 24, color: AppText.onInk),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.h2.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppText.onInk,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppText.onInkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 14),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A 48px button on the navy header: lime or dark.
class RentHeaderButton extends StatelessWidget {
  const RentHeaderButton({
    required this.label,
    required this.onTap,
    this.lime = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool lime;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: lime ? AppColors.brand : AppColors.navyLine,
      borderRadius: AppRadii.all(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(14),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppType.small.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: lime ? AppColors.navy : AppText.onInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// "NEW — CONFIRM OR REJECT" and friends.
class RentSectionLabel extends StatelessWidget {
  const RentSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(
          text,
          style: AppType.caption.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
            color: AppText.secondary,
          ),
        ),
      );
}

/// A 22px tag.
class RentTag extends StatelessWidget {
  const RentTag(
    this.label, {
    this.background = AppColors.surfaceAlt,
    this.ink = AppText.primary,
    super.key,
  });

  final String label;
  final Color background;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.all(7),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: AppType.caption.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      );
}

/// Month title with previous / next arrows.
class RentMonthBar extends StatelessWidget {
  const RentMonthBar({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final DateTime month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String label, VoidCallback? onTap) =>
        Semantics(
          button: true,
          label: label,
          child: Material(
            color: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.all(12),
              side: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder:
                  RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(icon,
                    size: 22,
                    color: onTap == null ? AppText.disabled : AppColors.navy),
              ),
            ),
          ),
        );

    return Row(
      children: [
        arrow(Icons.chevron_left_rounded, 'Previous month', onPrevious),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy').format(month),
            textAlign: TextAlign.center,
            style: AppType.listTitle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
        ),
        arrow(Icons.chevron_right_rounded, 'Next month', onNext),
      ],
    );
  }
}

/// Monday-first month grid. Days outside [month] are left empty; every other
/// cell is drawn by [cell].
class RentMonthGrid extends StatelessWidget {
  const RentMonthGrid({
    required this.month,
    required this.cell,
    super.key,
  });

  final DateTime month;
  final Widget Function(DateTime day) cell;

  static const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  /// The Monday on or before the first of [month].
  static DateTime gridStart(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    return first.subtract(Duration(days: first.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final start = gridStart(month);
    final rows = <Widget>[
      Row(
        children: [
          for (final label in _weekdays)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
    ];

    for (var week = 0; week < 6; week++) {
      final days = [
        for (var d = 0; d < 7; d++)
          DateTime(start.year, start.month, start.day + week * 7 + d),
      ];
      if (week > 3 && days.every((day) => day.month != month.month)) break;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: SizedBox(
                      height: 46,
                      child: day.month == month.month
                          ? cell(day)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// One legend swatch and its label.
class RentLegendItem extends StatelessWidget {
  const RentLegendItem({
    required this.label,
    required this.fill,
    this.border,
    super.key,
  });

  final String label;
  final Color fill;
  final Color? border;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AppRadii.all(4),
              border: border == null
                  ? null
                  : Border.all(color: border!, width: 1.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
        ],
      );
}

DateTime rentDayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String rentYmd(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

/// "Fri 9 – Sun 11 Oct" or "Fri 30 Oct – Mon 2 Nov".
String rentRange(DateTime start, DateTime end) {
  if (rentDayOnly(start) == rentDayOnly(end)) {
    return DateFormat('EEE d MMM').format(start);
  }
  final sameMonth = start.month == end.month && start.year == end.year;
  return '${DateFormat(sameMonth ? 'EEE d' : 'EEE d MMM').format(start)} – '
      '${DateFormat('EEE d MMM').format(end)}';
}
