import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/booking/booking_repository.dart';
import '../../core/format/money.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/booking_models.dart';
import 'live_packages_screen.dart';
import 'live_tour_interest_screen.dart';

/// Tours — every published departure, as a list of vehicles.
///
/// Opened straight from the Tour button on the home screen. The list takes the
/// whole screen; where the customer is going is asked in the footer, not before
/// they have seen anything. The filters answer the questions people actually
/// ask: are there seats, is the whole vehicle still free, what leaves today,
/// what can I take for my own party.
class TourVehiclesScreen extends StatefulWidget {
  const TourVehiclesScreen({super.key});

  @override
  State<TourVehiclesScreen> createState() => _TourVehiclesScreenState();
}

enum _TourFilter { all, seats, free, today, whole }

bool _isToday(DateTime value) {
  final now = DateTime.now();
  return value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
}

extension on _TourFilter {
  String get label => switch (this) {
        _TourFilter.all => 'All',
        _TourFilter.seats => 'Seats left',
        _TourFilter.free => 'Fully free',
        _TourFilter.today => 'Today',
        _TourFilter.whole => 'Full vehicle',
      };
}

/// Which day the customer asked for. [date] is only used with [_When.date].
enum _When { any, today, tomorrow, date }

class _TourQuery {
  const _TourQuery({
    this.pickup = '',
    this.destination = '',
    this.when = _When.any,
    this.date,
  });

  final String pickup;
  final String destination;
  final _When when;
  final DateTime? date;

  DateTime? get day {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (when) {
      _When.any => null,
      _When.today => today,
      _When.tomorrow => today.add(const Duration(days: 1)),
      _When.date => date == null
          ? null
          : DateTime(date!.year, date!.month, date!.day),
    };
  }

  String get dateLabel => switch (when) {
        _When.any => 'Any date',
        _When.today => 'Today',
        _When.tomorrow => 'Tomorrow',
        _When.date =>
          date == null ? 'Any date' : DateFormat('d MMM').format(date!),
      };
}

class _TourVehiclesScreenState extends State<TourVehiclesScreen> {
  bool _busy = true;
  String? _error;
  List<LiveTourPackage> _all = const [];
  _TourFilter _filter = _TourFilter.all;
  _TourQuery _query = const _TourQuery();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final controller = AppControllerScope.of(context);
      // Every active upcoming departure. Filtering happens here, so changing a
      // chip or the destination never waits on the network.
      final list =
          await BookingRepository(controller.apiClient).getPublicPackages();
      if (!mounted) return;
      final sorted = [...list]
        ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
      setState(() {
        _all = sorted;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _matches(String needle, List<String> haystack) {
    final wanted = needle.trim().toLowerCase();
    if (wanted.isEmpty) return true;
    return haystack.any((value) => value.toLowerCase().contains(wanted));
  }

  bool _passesFilter(LiveTourPackage p) => switch (_filter) {
        _TourFilter.all => true,
        _TourFilter.seats => p.pricePerSeat > 0 && p.bookableSeats > 0,
        _TourFilter.free => p.bookableSeats >= p.totalSeats,
        _TourFilter.today => _isToday(p.departureAt),
        _TourFilter.whole =>
          p.wholeVehiclePrice > 0 && p.bookableSeats >= p.totalSeats,
      };

  bool _passesQuery(LiveTourPackage p) {
    final day = _query.day;
    if (day != null && !_sameDay(p.departureAt, day)) return false;
    if (!_matches(_query.pickup, [p.startingCity, p.pickupPoint])) {
      return false;
    }
    return _matches(_query.destination, [p.destination, p.title]);
  }

  /// Departures with nothing left to sell are not shown at all.
  List<LiveTourPackage> get _shown => _all
      .where((p) => p.bookableSeats > 0)
      .where(_passesQuery)
      .where(_passesFilter)
      .toList(growable: false);

  Future<void> _open(LiveTourPackage package) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivePackageDetailScreen(package: package),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _openWhere() async {
    final result = await showModalBottomSheet<_TourQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WhereSheet(
        initial: _query,
        pickups: _distinct(_all.map((p) => p.startingCity)),
        destinations: _distinct(_all.map((p) => p.destination)),
      ),
    );
    if (result != null && mounted) setState(() => _query = result);
  }

  static List<String> _distinct(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
      out.add(value);
    }
    return out.take(10).toList(growable: false);
  }

  String get _whereSubtitle {
    final from = _query.pickup.trim().isEmpty
        ? 'From anywhere'
        : 'From ${_query.pickup.trim()}';
    return '$from · ${_query.dateLabel.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final destination = _query.destination.trim();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                count: _busy ? null : shown.length,
                filter: _filter,
                onBack: () => Navigator.pop(context),
                onFilter: (value) => setState(() => _filter = value),
              ),
              Expanded(child: _body(shown)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _WhereFooter(
              title: destination.isEmpty
                  ? 'Where are you going?'
                  : 'To $destination',
              subtitle: _whereSubtitle,
              dateLabel: _query.dateLabel,
              onTap: _openWhere,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<LiveTourPackage> shown) {
    if (_busy) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load tours',
        text: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    if (shown.isEmpty) {
      final narrowed = _filter != _TourFilter.all ||
          _query.pickup.trim().isNotEmpty ||
          _query.destination.trim().isNotEmpty ||
          _query.when != _When.any;
      return _Message(
        icon: Icons.event_busy_rounded,
        title: narrowed ? 'No tours match this' : 'No tours published yet',
        text: 'We can tell you when a driver publishes a matching departure.',
        actionLabel: 'Match me to a tour',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LiveTourInterestScreen(standalone: true),
          ),
        ),
        secondaryLabel: narrowed ? 'Show all tours' : null,
        onSecondary: narrowed
            ? () => setState(() {
                  _filter = _TourFilter.all;
                  _query = const _TourQuery();
                })
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _TourCard(
          package: shown[index],
          onTap: () => _open(shown[index]),
        ),
      ),
    );
  }
}

/// Back, title, count and the filter chips.
class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.filter,
    required this.onBack,
    required this.onFilter,
  });

  final int? count;
  final _TourFilter filter;
  final VoidCallback onBack;
  final ValueChanged<_TourFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        onTap: onBack,
                        customBorder: RoundedRectangleBorder(
                          borderRadius: AppRadii.all(14),
                        ),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.chevron_left_rounded,
                              size: 26, color: AppColors.navy),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tours',
                        style: TextStyle(
                          fontFamily: AppType.family,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                    if (count != null)
                      Text(
                        '$count ${count == 1 ? 'vehicle' : 'vehicles'}',
                        style: AppType.small.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppText.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _TourFilter.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final value = _TourFilter.values[index];
                    return _Chip(
                      label: value.label,
                      selected: value == filter,
                      onTap: () => onFilter(value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 38,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

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
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
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

/// One departure, compact enough for four on a screen.
class _TourCard extends StatelessWidget {
  const _TourCard({required this.package, required this.onTap});

  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = package;
    final seats = p.bookableSeats;
    final wholeOnly = p.pricePerSeat <= 0;
    final free = seats >= p.totalSeats;
    final today = _isToday(p.departureAt);

    final String tag;
    final Color tagBg;
    final Color tagInk;
    if (wholeOnly) {
      tag = 'Full vehicle';
      tagBg = AppColors.surfaceAlt;
      tagInk = AppText.primary;
    } else if (free) {
      tag = 'Fully free';
      tagBg = AppColors.brandWash;
      tagInk = AppColors.brandInk;
    } else {
      tag = '$seats left';
      tagBg = AppColors.navy;
      tagInk = AppText.onInk;
    }

    final when = today
        ? 'Today ${DateFormat('h:mm a').format(p.departureAt)}'
        : DateFormat('EEE d MMM, h:mm a').format(p.departureAt);
    final seatLine = wholeOnly
        ? '${p.totalSeats} seats'
        : '$seats of ${p.totalSeats} seats free';
    final pickup = [p.pickupPoint, p.startingCity]
        .where((v) => v.trim().isNotEmpty)
        .join(', ');
    final rating = p.driverRatingOrNull;

    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Column(
                  children: [
                    _TourPhoto(
                      url: p.coverImageUrl,
                      seats: p.totalSeats,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tagBg,
                        borderRadius: AppRadii.all(8),
                      ),
                      child: Text(
                        tag,
                        maxLines: 1,
                        style: AppType.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tagInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.vehicle.trim().isEmpty ? p.title : p.vehicle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        if (rating != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.brandInk),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _RouteLines(pickup: pickup, destination: p.destination),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: today
                                ? AppColors.brand
                                : AppColors.surfaceAlt,
                            borderRadius: AppRadii.all(7),
                          ),
                          child: Text(
                            when,
                            style: AppType.caption.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            seatLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppText.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: Money.amount(wholeOnly
                                      ? p.wholeVehiclePrice
                                      : p.pricePerSeat),
                                  style: AppType.listTitle.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: wholeOnly ? ' vehicle' : ' / seat',
                                  style: AppType.caption.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppText.secondary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: AppColors.navy,
                          borderRadius: AppRadii.all(11),
                          child: InkWell(
                            onTap: onTap,
                            borderRadius: AppRadii.all(11),
                            child: Container(
                              height: 34,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              child: Text(
                                wholeOnly ? 'Book' : 'Seats',
                                style: AppType.small.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.onInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pickup over destination, joined by a short line.
class _RouteLines extends StatelessWidget {
  const _RouteLines({required this.pickup, required this.destination});

  final String pickup;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final style = AppType.small.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppText.primary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.navy, width: 2.5),
                ),
              ),
              Container(
                width: 1.5,
                height: 10,
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: AppColors.borderStrong,
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandInk,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickup.isEmpty ? 'Pickup on booking' : pickup,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
              const SizedBox(height: 3),
              Text(
                destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The driver's photo of the vehicle, or a plain tile when there is none.
class _TourPhoto extends StatelessWidget {
  const _TourPhoto({required this.url, required this.seats});

  final String? url;
  final int seats;

  @override
  Widget build(BuildContext context) {
    final icon = seats >= 15
        ? Icons.directions_bus_rounded
        : seats >= 8
            ? Icons.airport_shuttle_rounded
            : Icons.directions_car_rounded;
    final Widget fallback = Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(icon, size: 40, color: AppColors.navy),
    );
    final link = url?.trim() ?? '';

    return ClipRRect(
      borderRadius: AppRadii.all(13),
      child: SizedBox(
        width: 96,
        height: 84,
        child: link.isEmpty
            ? fallback
            : Image.network(
                link,
                fit: BoxFit.cover,
                // Decoded at the size it is drawn, not the size it was shot.
                cacheWidth: 288,
                errorBuilder: (_, __, ___) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}

/// "Where are you going?", pinned to the bottom.
class _WhereFooter extends StatelessWidget {
  const _WhereFooter({
    required this.title,
    required this.subtitle,
    required this.dateLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppShadows.floating,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: AppRadii.all(3),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: AppColors.navy,
              borderRadius: AppRadii.all(18),
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadii.all(18),
                child: SizedBox(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            size: 22, color: AppColors.brand),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.listTitle.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.onInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onInkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            borderRadius: AppRadii.all(13),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today_rounded,
                                  size: 15, color: AppColors.navy),
                              const SizedBox(width: 6),
                              Text(
                                dateLabel,
                                style: AppType.small.copyWith(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

/// Pickup, destination and day — the sheet the footer opens.
class _WhereSheet extends StatefulWidget {
  const _WhereSheet({
    required this.initial,
    required this.pickups,
    required this.destinations,
  });

  final _TourQuery initial;

  /// Starting cities and destinations of the departures actually loaded, so
  /// every chip leads somewhere.
  final List<String> pickups;
  final List<String> destinations;

  @override
  State<_WhereSheet> createState() => _WhereSheetState();
}

class _WhereSheetState extends State<_WhereSheet> {
  late final TextEditingController _pickup =
      TextEditingController(text: widget.initial.pickup);
  late final TextEditingController _destination =
      TextEditingController(text: widget.initial.destination);
  late _When _when = widget.initial.when;
  late DateTime? _date = widget.initial.date;
  bool _locating = false;
  String? _locationError;

  /// Towns a departure can start from, for "My location". Only the name is
  /// used — it is matched against each departure's starting city and pickup.
  static const List<(String, double, double)> _towns = [
    ('Muzaffarabad', 34.3700, 73.4711),
    ('Rawalakot', 33.8578, 73.7604),
    ('Bagh', 33.9810, 73.7760),
    ('Kotli', 33.5180, 73.9020),
    ('Mirpur', 33.1480, 73.7510),
    ('Bhimber', 32.9750, 74.0780),
    ('Athmuqam', 34.5740, 73.9080),
    ('Hattian Bala', 34.1680, 73.7440),
    ('Pallandri', 33.7120, 73.6860),
    ('Dhirkot', 34.0400, 73.5800),
    ('Kohala', 34.0950, 73.4950),
  ];

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on location to use this.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is off.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      var best = _towns.first.$1;
      var bestDistance = double.infinity;
      for (final town in _towns) {
        final distance = Geolocator.distanceBetween(
            position.latitude, position.longitude, town.$2, town.$3);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = town.$1;
        }
      }
      if (!mounted) return;
      setState(() => _pickup.text = best);
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _locationError = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _when = _When.date;
      });
    }
  }

  void _apply() {
    Navigator.pop(
      context,
      _TourQuery(
        pickup: _pickup.text.trim(),
        destination: _destination.text.trim(),
        when: _when,
        date: _date,
      ),
    );
  }

  String get _buttonLabel {
    final to = _destination.text.trim();
    final day = _TourQuery(when: _when, date: _date).dateLabel;
    if (to.isEmpty && _when == _When.any) return 'Show vehicles';
    if (to.isEmpty) return 'Show vehicles · ${day.toLowerCase()}';
    if (_when == _When.any) return 'Show vehicles · $to';
    return 'Show vehicles · $to, ${day.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final overline = AppType.caption.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: .3,
      color: AppText.secondary,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: AppRadii.all(3),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Where are you going?',
                        style: AppType.h3.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                    Material(
                      color: AppColors.surfaceAlt,
                      borderRadius: AppRadii.all(12),
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: AppRadii.all(12),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.close_rounded,
                              size: 20, color: AppColors.navy),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Fields.
                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.all(18),
                    border: Border.all(color: AppColors.border, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      _FieldRow(
                        label: 'PICKUP',
                        hint: 'Anywhere',
                        controller: _pickup,
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.navy, width: 3.5),
                          ),
                        ),
                        trailing: _SmallAction(
                          icon: Icons.my_location_rounded,
                          label: 'My location',
                          busy: _locating,
                          onTap: _useMyLocation,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _FieldRow(
                        label: 'DESTINATION',
                        hint: 'Search a place',
                        controller: _destination,
                        highlight: true,
                        leading: const Icon(Icons.place_rounded,
                            size: 18, color: AppColors.brandInk),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                if (_locationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _locationError!,
                    style: AppType.caption.copyWith(color: AppColors.danger),
                  ),
                ],

                if (widget.pickups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('FROM', style: overline),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in widget.pickups)
                        _Chip(
                          label: name,
                          selected: _pickup.text.trim().toLowerCase() ==
                              name.toLowerCase(),
                          onTap: () => setState(() => _pickup.text =
                              _pickup.text.trim().toLowerCase() ==
                                      name.toLowerCase()
                                  ? ''
                                  : name),
                        ),
                    ],
                  ),
                ],

                if (widget.destinations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('POPULAR', style: overline),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in widget.destinations)
                        _Chip(
                          label: name,
                          selected: _destination.text.trim().toLowerCase() ==
                              name.toLowerCase(),
                          onTap: () => setState(() => _destination.text =
                              _destination.text.trim().toLowerCase() ==
                                      name.toLowerCase()
                                  ? ''
                                  : name),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                Text('WHEN', style: overline),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final option in _When.values) ...[
                      if (option != _When.any) const SizedBox(width: 8),
                      Expanded(
                        child: _Chip(
                          height: 44,
                          label: switch (option) {
                            _When.any => 'Any',
                            _When.today => 'Today',
                            _When.tomorrow => 'Tomorrow',
                            _When.date => _when == _When.date && _date != null
                                ? DateFormat('d MMM').format(_date!)
                                : 'Date',
                          },
                          selected: _when == option,
                          onTap: option == _When.date
                              ? _pickDate
                              : () => setState(() => _when = option),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                Material(
                  color: AppColors.brand,
                  borderRadius: AppRadii.all(18),
                  child: InkWell(
                    onTap: _apply,
                    borderRadius: AppRadii.all(18),
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _buttonLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.button.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded,
                              size: 22, color: AppColors.navy),
                        ],
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
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.leading,
    required this.onChanged,
    this.trailing,
    this.highlight = false,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Widget leading;
  final Widget? trailing;
  final ValueChanged<String> onChanged;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: highlight ? AppColors.brandWash : null,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          SizedBox(width: 18, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                    color: highlight ? AppColors.brandInk : AppText.secondary,
                  ),
                ),
                TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.done,
                  style: AppType.body2.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: AppType.body2.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppText.caption,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.only(top: 2),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandWash,
      borderRadius: AppRadii.all(10),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: AppRadii.all(10),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandInk,
                  ),
                )
              else
                Icon(icon, size: 14, color: AppColors.brandInk),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.caption.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading failed, or nothing to show.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 160),
      children: [
        Icon(icon, size: 44, color: AppText.caption),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppType.h3.copyWith(color: AppText.primary),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppType.body2.copyWith(height: 1.45, color: AppText.secondary),
        ),
        const SizedBox(height: 18),
        Center(
          child: Material(
            color: AppColors.navy,
            borderRadius: AppRadii.all(14),
            child: InkWell(
              onTap: onAction,
              borderRadius: AppRadii.all(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                child: Text(
                  actionLabel,
                  style: AppType.small.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppText.onInk,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onSecondary,
              child: Text(
                secondaryLabel!,
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
