import 'package:flutter/material.dart';

import '../../core/listings/listing_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'rent_tour_kit.dart';

/// R2 — when is the car free?
///
/// The owner taps a free day to block it (they need the car) and a blocked day
/// to free it again. Booked, pending and tour days belong to someone else and
/// cannot be tapped. Changes stay on the phone until Save.
class ListingRentCalendarScreen extends StatefulWidget {
  const ListingRentCalendarScreen({required this.vehicle, super.key});

  final ListingVehicle vehicle;

  @override
  State<ListingRentCalendarScreen> createState() =>
      _ListingRentCalendarScreenState();
}

class _ListingRentCalendarScreenState extends State<ListingRentCalendarScreen> {
  ListingRepository? _repository;

  late DateTime _month = _firstOfMonth(DateTime.now());

  /// Day → state as the server last said, across every month loaded.
  final Map<DateTime, String> _states = {};

  /// Free days the owner has blocked, and blocked days they freed, unsaved.
  final Set<DateTime> _added = {};
  final Set<DateTime> _removed = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saved;

  static DateTime _firstOfMonth(DateTime value) =>
      DateTime(value.year, value.month, 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository = ListingRepository(AppControllerScope.of(context).apiClient);
      _load();
    }
  }

  bool get _dirty => _added.isNotEmpty || _removed.isNotEmpty;

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = await repository.calendar(
        widget.vehicle.id,
        RentMonthGrid.gridStart(_month),
        days: 42,
      );
      if (!mounted) return;
      setState(() {
        for (final day in days) {
          _states[rentDayOnly(day.date)] = day.state;
        }
        _loading = false;
      });
    } on ListingRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _error = refusal.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _saved = null;
    });
    _load();
  }

  /// The state to draw, with unsaved taps applied.
  String _stateOf(DateTime day) {
    final today = rentDayOnly(DateTime.now());
    if (day.isBefore(today)) return 'past';
    if (_added.contains(day)) return 'blocked';
    if (_removed.contains(day)) return 'free';
    return _states[day] ?? 'free';
  }

  void _tap(DateTime day) {
    final server = _states[day] ?? 'free';
    setState(() {
      _saved = null;
      if (server == 'free') {
        if (!_added.remove(day)) _added.add(day);
      } else if (server == 'blocked') {
        if (!_removed.remove(day)) _removed.add(day);
      }
    });
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || !_dirty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final block = _added.toList()..sort();
      final unblock = _removed.toList()..sort();
      final days = await repository.setBlockedDays(
        widget.vehicle.id,
        block: block,
        unblock: unblock,
      );
      if (!mounted) return;
      setState(() {
        for (final day in block) {
          _states[day] = 'blocked';
        }
        for (final day in unblock) {
          _states[day] = 'free';
        }
        for (final day in days) {
          _states[rentDayOnly(day.date)] = day.state;
        }
        _added.clear();
        _removed.clear();
        _saving = false;
        _saved = 'Saved. Customers see the new dates now.';
      });
    } on ListingRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _error = refusal.message;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final current = _firstOfMonth(DateTime.now());
    final changes = _added.length + _removed.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          RentNavyHeader(
            title: 'When is it free?',
            subtitle:
                '${v.year > 0 ? '${v.name} ${v.year}' : v.name} · tap days to block',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (_error != null) ...[
                    UdBanner(tone: UdTone.err, text: _error),
                    const SizedBox(height: 12),
                  ],
                  if (_saved != null) ...[
                    UdBanner(
                      tone: UdTone.ok,
                      icon: Icons.check_rounded,
                      text: _saved,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: AppRadii.all(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        RentMonthBar(
                          month: _month,
                          onPrevious: _loading || !_month.isAfter(current)
                              ? null
                              : () => _shiftMonth(-1),
                          onNext: _loading ? null : () => _shiftMonth(1),
                        ),
                        const SizedBox(height: 12),
                        Stack(
                          children: [
                            RentMonthGrid(
                              month: _month,
                              cell: (day) => _DayCell(
                                day: day,
                                state: _stateOf(day),
                                today: day == rentDayOnly(DateTime.now()),
                                onTap: _loading || _saving
                                    ? null
                                    : switch (_stateOf(day)) {
                                        'free' || 'blocked' => () => _tap(day),
                                        _ => null,
                                      },
                              ),
                            ),
                            if (_loading)
                              const Positioned.fill(
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.navy),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      RentLegendItem(
                        label: 'Free',
                        fill: AppColors.background,
                        border: AppColors.borderStrong,
                      ),
                      RentLegendItem(label: 'Booked', fill: AppColors.navy),
                      RentLegendItem(
                        label: 'Waiting',
                        fill: AppColors.background,
                        border: AppColors.navy,
                      ),
                      RentLegendItem(
                          label: 'You blocked', fill: AppColors.surfaceAlt),
                      RentLegendItem(
                        label: 'Tour day',
                        fill: AppColors.brandWash,
                        border: AppColors.limeLine,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Tap a free day to block it (you need the car). Tap '
                    'again to free it. Booked days can\'t be blocked — open '
                    'the booking instead.',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: UdButton.primary(
                label: changes == 0
                    ? 'Save'
                    : 'Save · $changes ${changes == 1 ? 'change' : 'changes'}',
                busy: _saving,
                onPressed: _dirty ? _save : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.state,
    required this.today,
    required this.onTap,
  });

  final DateTime day;

  /// free, pending, booked, blocked, tour or past.
  final String state;
  final bool today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill = switch (state) {
      'booked' => AppColors.navy,
      'blocked' => AppColors.surfaceAlt,
      'tour' => AppColors.brandWash,
      _ => AppColors.background,
    };
    final Color ink = switch (state) {
      'booked' => AppText.onInk,
      'blocked' || 'past' => AppText.disabled,
      'tour' => AppColors.brandInk,
      _ => AppText.primary,
    };
    final BorderSide side = switch (state) {
      'pending' => const BorderSide(color: AppColors.navy, width: 2),
      'free' => BorderSide(
          color: today ? AppColors.brand : AppColors.border,
          width: today ? 2 : 1.5),
      'tour' => const BorderSide(color: AppColors.limeLine, width: 1.5),
      _ => BorderSide.none,
    };
    final label = switch (state) {
      'booked' => 'booked',
      'pending' => 'waiting for your answer',
      'blocked' => 'blocked by you',
      'tour' => 'tour day',
      'past' => 'past',
      _ => 'free',
    };

    return Semantics(
      button: onTap != null,
      label: '${day.day}, $label',
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(12),
          side: side,
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
          child: Center(
            child: Text(
              '${day.day}',
              style: AppType.listTitle.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ink,
                decoration:
                    state == 'blocked' ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
