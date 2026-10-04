import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'hotel_bits.dart';

/// "Your stay" — where, which nights, how many people.
///
/// A whole screen rather than a sheet: the month calendar needs the room, and
/// check-in and check-out are picked on it directly — first tap is the
/// arrival day, second tap the departure day. Returns the new [HotelQuery], or
/// null when closed.
class HotelSearchScreen extends StatefulWidget {
  const HotelSearchScreen({
    required this.initial,
    this.cities = const [],
    super.key,
  });

  final HotelQuery initial;

  /// Cities that actually have hotels, offered as chips.
  final List<String> cities;

  @override
  State<HotelSearchScreen> createState() => _HotelSearchScreenState();
}

class _HotelSearchScreenState extends State<HotelSearchScreen> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initial.query);
  late DateTime _checkIn = hotelDay(widget.initial.checkIn);
  late DateTime? _checkOut = hotelDay(widget.initial.checkOut);
  late int _guests = widget.initial.guests;
  late int _rooms = widget.initial.rooms;
  late DateTime _month = DateTime(_checkIn.year, _checkIn.month);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  DateTime get _today => hotelDay(DateTime.now());

  void _tapDay(DateTime day) {
    setState(() {
      final out = _checkOut;
      if (out == null && day.isAfter(_checkIn)) {
        _checkOut = day;
      } else {
        _checkIn = day;
        _checkOut = null;
      }
    });
  }

  void _clear() => setState(() {
        _query.clear();
        _checkIn = _today.add(const Duration(days: 1));
        _checkOut = _checkIn.add(const Duration(days: 1));
        _guests = 2;
        _rooms = 1;
        _month = DateTime(_checkIn.year, _checkIn.month);
      });

  void _apply() {
    final out = _checkOut ?? _checkIn.add(const Duration(days: 1));
    Navigator.pop(
      context,
      HotelQuery(
        query: _query.text.trim(),
        checkIn: _checkIn,
        checkOut: out,
        guests: _guests,
        rooms: _rooms,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final out = _checkOut;
    final nights = out == null ? 0 : out.difference(_checkIn).inDays;
    final firstMonth = DateTime(_today.year, _today.month);
    final canGoBack = _month.isAfter(firstMonth);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Material(
                    color: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.all(14),
                      side: const BorderSide(
                          color: AppColors.border, width: 1.5),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      customBorder: RoundedRectangleBorder(
                          borderRadius: AppRadii.all(14)),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.close_rounded,
                            size: 20, color: AppColors.navy),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your stay',
                      style: AppType.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clear,
                    child: Text(
                      'Clear',
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppText.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.all(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            size: 20, color: AppColors.navy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _query,
                            textInputAction: TextInputAction.done,
                            style: AppType.body2.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppText.primary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'City or hotel',
                              hintStyle: AppType.body2.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppText.caption,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.cities.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final city in widget.cities)
                          _Pill(
                            label: city,
                            selected: _query.text.trim().toLowerCase() ==
                                city.toLowerCase(),
                            onTap: () => setState(() => _query.text = city),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Month header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(_month),
                          style: AppType.listTitle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppText.primary,
                          ),
                        ),
                      ),
                      _MonthButton(
                        icon: Icons.chevron_left_rounded,
                        label: 'Previous month',
                        onTap: canGoBack
                            ? () => setState(() => _month =
                                DateTime(_month.year, _month.month - 1))
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _MonthButton(
                        icon: Icons.chevron_right_rounded,
                        label: 'Next month',
                        onTap: () => setState(() =>
                            _month = DateTime(_month.year, _month.month + 1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MonthGrid(
                    month: _month,
                    today: _today,
                    checkIn: _checkIn,
                    checkOut: _checkOut,
                    onTap: _tapDay,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DateBox(
                          label: 'CHECK-IN',
                          value: hotelDate(_checkIn),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DateBox(
                          label: out == null
                              ? 'CHECK-OUT'
                              : 'CHECK-OUT · $nights '
                                  '${nights == 1 ? 'NIGHT' : 'NIGHTS'}',
                          value: out == null ? 'Pick a day' : hotelDate(out),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Counter(
                          label: 'Guests',
                          value: _guests,
                          min: 1,
                          max: 20,
                          onChanged: (value) => setState(() => _guests = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Counter(
                          label: 'Rooms',
                          value: _rooms,
                          min: 1,
                          max: 10,
                          onChanged: (value) => setState(() => _rooms = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: HotelPrimaryButton(
                label: out == null
                    ? 'Pick your check-out day'
                    : 'Show hotels · $nights '
                        '${nights == 1 ? 'night' : 'nights'}',
                icon: Icons.chevron_right_rounded,
                onPressed: out == null ? null : _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.checkIn,
    required this.checkOut,
    required this.onTap,
  });

  final DateTime month;
  final DateTime today;
  final DateTime checkIn;
  final DateTime? checkOut;
  final ValueChanged<DateTime> onTap;

  static const _week = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    final out = checkOut;

    Widget cell(int index) {
      final dayNumber = index - lead + 1;
      if (dayNumber < 1 || dayNumber > days) return const SizedBox(height: 44);
      final day = DateTime(month.year, month.month, dayNumber);
      final past = day.isBefore(today);
      final isStart = day == checkIn;
      final isEnd = out != null && day == out;
      final inside = out != null && day.isAfter(checkIn) && day.isBefore(out);
      final hasRange = out != null;

      // The lime band runs behind the range, half a cell into each end.
      final Widget band = Row(
        children: [
          Expanded(
            child: Container(
              color: inside || (isEnd && hasRange)
                  ? AppColors.brandWash
                  : null,
            ),
          ),
          Expanded(
            child: Container(
              color: inside || (isStart && hasRange)
                  ? AppColors.brandWash
                  : null,
            ),
          ),
        ],
      );

      return SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: band),
            Material(
              color: isStart || isEnd ? AppColors.navy : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: past ? null : () => onTap(day),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: AppType.small.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isStart || isEnd
                            ? AppText.onInk
                            : past
                                ? AppText.disabled
                                : AppText.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            for (final label in _week)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: AppType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppText.caption,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: cell(row * 7 + col)),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(11),
          side: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder:
              RoundedRectangleBorder(borderRadius: AppRadii.all(11)),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon,
                size: 20,
                color: onTap == null ? AppText.disabled : AppColors.navy),
          ),
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: hotelOverline().copyWith(fontSize: 10.5)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppType.listTitle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, bool dark, VoidCallback? onTap, String hint) {
      final enabled = onTap != null;
      return Semantics(
        button: true,
        label: hint,
        child: Material(
          color: !enabled
              ? AppColors.surfaceAlt
              : dark
                  ? AppColors.navy
                  : AppColors.surfaceAlt,
          borderRadius: AppRadii.all(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.all(10),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon,
                  size: 18,
                  color: !enabled
                      ? AppText.disabled
                      : dark
                          ? AppText.onInk
                          : AppColors.navy),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        borderRadius: AppRadii.all(14),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ),
          button(Icons.remove_rounded, false,
              value > min ? () => onChanged(value - 1) : null, 'Fewer $label'),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ),
          button(Icons.add_rounded, true,
              value < max ? () => onChanged(value + 1) : null, 'More $label'),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(12),
        side: BorderSide(
          color: selected ? AppColors.navy : AppColors.border,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppType.small.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppText.onInk : AppText.primary,
            ),
          ),
        ),
      ),
    );
  }
}
