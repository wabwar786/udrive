import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/booking/driver_finance_repository.dart';
import '../../core/booking/trip_chat_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/growth/driver_growth_repository.dart';
import '../../models/driver_growth_models.dart';
import 'driver_missions_screen.dart';
import 'driver_welcome_bonus_screen.dart';

/// D-40 — this month, the rating, and the payout wallet.
///
/// Also serves D-46. The drawer's "Ratings & reviews" lands here rather than
/// on a screen of its own, because the rating and the reviews come from this
/// screen's `driverDashboard` call and there is only one of each. The screen
/// D-46 replaced showed every driver an identical invented "4.9 over 846
/// trips"; the numbers below are whatever this driver actually has, including
/// none.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  late final DriverFinanceRepository _repository;
  Map<String, dynamic>? _data;

  /// Rating, trip count, month total and what passengers wrote.
  ///
  /// This lives here rather than on the dashboard. It is worth reading, but not
  /// while a ride request is coming in — the dashboard's job is the next ride.
  DriverDashboard? _dashboard;

  /// Today, this week, this month — measured, with the breakdown behind each.
  ///
  /// The screen used to open on one number: "this month", from the dashboard
  /// call. A Driver asking the only question that matters — was today worth the
  /// fuel — could not answer it here, and a Driver asking where the money came
  /// from could not tell a fare from a reward, because both arrived as one
  /// total. Null while it loads, and null for ever on an install where the
  /// growth endpoints are not deployed: the rest of the screen still works.
  DriverEarnings? _earnings;

  /// Which period's figures are on screen. 0 today, 1 week, 2 month.
  int _period = 0;

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = DriverFinanceRepository(ApiClient(SessionStore()));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboard();
      _loadEarnings();
    });
  }

  Future<void> _loadDashboard() async {
    final controller = AppControllerScope.of(context);
    final dashboard =
        await TripChatRepository(controller.apiClient).driverDashboard();
    if (!mounted || dashboard == null) return;
    setState(() => _dashboard = dashboard);
  }

  Future<void> _loadEarnings() async {
    final controller = AppControllerScope.of(context);
    final earnings =
        await DriverGrowthRepository(controller.apiClient).earnings();
    if (!mounted) return;
    setState(() => _earnings = earnings);
  }

  EarningsPeriod? get _selected => switch (_period) {
        0 => _earnings?.today,
        1 => _earnings?.week,
        _ => _earnings?.month,
      };

  /// "2h 45m", or "—" when there is nothing to show.
  static String _hours(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      final result = await _repository.load();
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _pkr(dynamic value) =>
      'PKR ${NumberFormat('#,###').format(_number(value).round())}';

  @override
  Widget build(BuildContext context) {
    final rawWallet = _data?['wallet'];
    final wallet = rawWallet is Map
        ? Map<String, dynamic>.from(rawWallet)
        : <String, dynamic>{};
    final rawEntries = _data?['entries'];
    final entries = rawEntries is List
        ? rawEntries
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
        : <Map<String, dynamic>>[];

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _loadEarnings();
      },
      color: AppColors.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          Text(
            'Earnings',
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 6),
          Text(
            'What you earned, where it came from, and your wallets.',
            style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 20),

          // The period figures, when the growth endpoint is there.
          if (_selected case final period?) ...[
            _PeriodTabs(
              index: _period,
              labels: [
                _earnings!.today.label,
                _earnings!.week.label,
                _earnings!.month.label,
              ],
              onChanged: (value) => setState(() => _period = value),
            ),
            const SizedBox(height: 14),
            _EarningsHero(period: period),
            const SizedBox(height: 14),
            _EarningsTiles(period: period, hours: _hours(period.onlineSeconds)),
            const SizedBox(height: 14),
            _CommissionNote(
              period: period,
              percentage: _earnings!.commissionPercentage,
              commissionBalance: _earnings!.commissionBalance,
            ),
            const SizedBox(height: 26),

            if (_earnings!.waysToEarn.isNotEmpty) ...[
              const UdSectionHeader(
                title: 'Ways to earn',
                caption: 'Live in your city',
              ),
              const SizedBox(height: 12),
              UdListGroup(
                children: [
                  for (final way in _earnings!.waysToEarn) _wayRow(way),
                ],
              ),
              const SizedBox(height: 26),
            ],
          ],

          if (_dashboard != null) ...[
            // Kept: the rating and its reviews are still read here, and D-46
            // still lands on this screen.
            if (_earnings == null) ...[
              _MonthCard(dashboard: _dashboard!),
              const SizedBox(height: 14),
            ],
            _RatingBlock(dashboard: _dashboard!),
            const SizedBox(height: 26),
          ],

          if (_busy && _data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.navy),
              ),
            ),

          if (_error != null)
            UdEmptyState(
              icon: Icons.cloud_off_rounded,
              tone: UdTone.err,
              title: 'Could not load your wallet',
              text: _error,
              action: UdButton.outline(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: _load,
              ),
            ),

          if (_data != null) ...[
            // Balance, pending and paid out — three numbers from one card,
            // because they are three states of the same money.
            UdCard(
              tone: UdCardTone.navy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available balance',
                    style: AppType.small.copyWith(color: AppText.onInkMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pkr(wallet['availableBalance']),
                    style: AppType.display.copyWith(color: AppColors.brand),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: UdStat(
                          value: _pkr(wallet['pendingBalance']),
                          label: 'Pending',
                          onDark: true,
                        ),
                      ),
                      Expanded(
                        child: UdStat(
                          value: _pkr(wallet['paidBalance']),
                          label: 'Paid out',
                          onDark: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            UdButton.primary(
              label: 'Request payout',
              icon: Icons.account_balance_rounded,
              busy: _busy,
              onPressed: _busy ? null : () => _requestPayout(wallet),
            ),
            const SizedBox(height: 26),

            UdSectionHeader(
              title: 'Wallet activity',
              caption: entries.isEmpty ? null : '${entries.length}',
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const UdEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Nothing yet',
                text: 'Commission, top-ups and payouts appear here.',
              )
            else
              UdListGroup(
                children: [
                  for (final entry in entries) _entryRow(entry),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// One way to earn. The amount is only ever what an Admin configured.
  Widget _wayRow(WayToEarn way) {
    final icon = switch (way.kind) {
      'Rides' => Icons.local_taxi_rounded,
      'Tour' => Icons.luggage_rounded,
      'WelcomeBonus' => Icons.card_giftcard_rounded,
      'DailyMission' => Icons.flag_rounded,
      'PeakHourReward' => Icons.bolt_rounded,
      'WeeklyReward' => Icons.calendar_month_rounded,
      'Referral' => Icons.group_add_rounded,
      'FoundingBenefit' => Icons.workspace_premium_rounded,
      'Reactivation' => Icons.refresh_rounded,
      _ => Icons.payments_rounded,
    };

    return UdListRow(
      title: way.title,
      subtitle: way.detail.isEmpty ? null : way.detail,
      leading: UdIconTile(icon: icon, tone: UdIconTone.soft),
      // No amount means it varies with the fare. That is said by showing
      // nothing rather than by printing an "up to" figure nobody promised.
      trailing: way.amount == null
          ? null
          : Text(
              'PKR ${NumberFormat('#,###').format(way.amount!.round())}',
              style: AppType.listTitle.copyWith(
                fontSize: 15.5,
                color: AppColors.brandInk,
              ),
            ),
      onTap: _destinationFor(way) == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => _destinationFor(way)!),
              ),
    );
  }

  /// Which screen a way to earn opens, or null when it has none yet.
  ///
  /// Pushed, not routed: the app has no named routes for these, and the drawer
  /// pushes them the same way. A path with no screen built yet — the referral
  /// screen is still to come — simply makes the row untappable rather than
  /// throwing on a route that does not exist.
  Widget? _destinationFor(WayToEarn way) => switch (way.actionPath) {
        'driverMissions' => const DriverMissionsScreen(),
        'driverWelcomeBonus' => const DriverWelcomeBonusScreen(),
        // Not from here. `DriverFoundingScreen` needs the driver's
        // `FoundingDriver` record and this screen never loads one — the
        // dashboard does, and opens it from the founding row there. Writing
        // `const DriverFoundingScreen()` did not compile at all, which is how
        // this was found. Returning null makes the row untappable, exactly as
        // the comment above describes for a path with no screen behind it.
        _ => null,
      };

  /// One wallet line.
  ///
  /// Money in is lime-ink and carries a plus; money out is navy and carries a
  /// minus. Every row used to be the same weight and the same colour, so a
  /// top-up and a commission charge read identically.
  Widget _entryRow(Map<String, dynamic> entry) {
    final amount = _number(entry['amount']);
    final credit = amount >= 0;

    return UdListRow(
      title: entry['description']?.toString() ?? 'Wallet entry',
      subtitle: '${entry['entryType'] ?? ''} · ${entry['createdAt'] ?? ''}',
      leading: UdIconTile(
        icon: credit
            ? Icons.arrow_downward_rounded
            : Icons.arrow_upward_rounded,
        tone: credit ? UdIconTone.soft : UdIconTone.neutral,
      ),
      trailing: Text(
        '${credit ? '+' : '-'}PKR '
        '${NumberFormat('#,###').format(amount.abs().round())}',
        style: AppType.listTitle.copyWith(
          fontSize: 15.5,
          color: credit ? AppColors.brandInk : AppText.primary,
        ),
      ),
    );
  }

  Future<void> _requestPayout(Map<String, dynamic> wallet) async {
    final controller = TextEditingController();
    final amount = await showUdDialog<double>(
      context: context,
      title: 'Request payout',
      message: 'Available: ${_pkr(wallet['availableBalance'])}.',
      content: UdTextField(
        controller: controller,
        label: 'Amount',
        labelSuffix: 'PKR',
        icon: Icons.payments_rounded,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      actions: [
        Builder(
          builder: (dialogContext) => UdButtonRow(
            children: [
              UdButton.outline(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialogContext),
              ),
              UdButton.primary(
                label: 'Submit',
                onPressed: () => Navigator.pop(
                  dialogContext,
                  double.tryParse(controller.text.trim()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    controller.dispose();

    if (amount == null || amount <= 0) return;
    setState(() => _busy = true);
    try {
      final rawVersion = wallet['version'];
      final version = rawVersion is int
          ? rawVersion
          : int.tryParse('$rawVersion') ?? 1;
      await _repository.requestPayout(
        amount: amount,
        method: 'BankTransfer',
        version: version,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payout request submitted')),
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Today / This week / This month.
///
/// Three chips rather than a dropdown. A Driver checks today a dozen times a
/// shift, and a dropdown makes the most common action two taps.
class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: AppRadii.all(AppRadii.chip),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.navy : AppColors.background,
                      borderRadius: AppRadii.all(AppRadii.chip),
                      border: Border.all(
                        color: i == index ? AppColors.navy : AppColors.border,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: i == index ? AppText.onInk : AppText.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

/// The total, and the two things it is made of.
///
/// Fares and rewards on separate lines on purpose. A Driver who cannot tell
/// them apart cannot tell whether a good week was good driving or a campaign
/// that is about to end.
class _EarningsHero extends StatelessWidget {
  const _EarningsHero({required this.period});

  final EarningsPeriod period;

  static String _pkr(double value) =>
      'PKR ${NumberFormat('#,###').format(value.round())}';

  @override
  Widget build(BuildContext context) => UdCard(
        tone: UdCardTone.navy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${period.label} · you earned',
              style: AppType.small.copyWith(color: AppText.onInkMuted),
            ),
            const SizedBox(height: 4),
            Text(
              _pkr(period.total),
              style: AppType.display.copyWith(color: AppColors.brand),
            ),
            const SizedBox(height: 16),
            _Line(
              icon: Icons.local_taxi_rounded,
              label: 'Ride fares, after commission',
              value: _pkr(period.rideNet),
            ),
            const SizedBox(height: 10),
            _Line(
              icon: Icons.card_giftcard_rounded,
              label: 'Rewards credited',
              value: _pkr(period.bonusEarned),
              // Zero is shown, not hidden. "No rewards yet" is information a
              // Driver wants; a missing line reads as a screen that forgot.
              muted: period.bonusEarned <= 0,
            ),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: muted ? AppText.onInkMuted : AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppType.small.copyWith(color: AppText.onInkMuted),
            ),
          ),
          Text(
            value,
            style: AppType.listTitle.copyWith(
              fontSize: 15.5,
              color: muted ? AppText.onInkMuted : AppText.onInk,
            ),
          ),
        ],
      );
}

/// Trips, time online, and what that worked out to an hour.
class _EarningsTiles extends StatelessWidget {
  const _EarningsTiles({required this.period, required this.hours});

  final EarningsPeriod period;
  final String hours;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: UdStat(value: '${period.trips}', label: 'Trips'),
            ),
            Expanded(
              child: UdStat(value: hours, label: 'Online'),
            ),
            Expanded(
              child: UdStat(
                // A dash, not a number, under fifteen minutes online. An
                // hourly rate worked out from four minutes of driving is a
                // promise the platform never made.
                value: period.perHour == null
                    ? '—'
                    : NumberFormat('#,###').format(period.perHour!.round()),
                label: period.perHour == null ? 'Per hour' : 'PKR per hour',
                align: CrossAxisAlignment.end,
              ),
            ),
          ],
        ),
      );
}

/// What the platform took, and what is left to take it from.
///
/// Both numbers in one place because they are one question. A Driver whose
/// commission wallet runs out stops being sent rides, and the only warning the
/// app used to give was the rides quietly stopping.
class _CommissionNote extends StatelessWidget {
  const _CommissionNote({
    required this.period,
    required this.percentage,
    required this.commissionBalance,
  });

  final EarningsPeriod period;
  final double percentage;
  final double commissionBalance;

  static String _pkr(double value) =>
      'PKR ${NumberFormat('#,###').format(value.round())}';

  @override
  Widget build(BuildContext context) {
    final low = commissionBalance <= 0;

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: UdStat(
                  value: _pkr(period.commissionPaid),
                  label: 'Commission taken '
                      '(${percentage.toStringAsFixed(percentage % 1 == 0 ? 0 : 2)}%)',
                ),
              ),
              Expanded(
                child: UdStat(
                  value: _pkr(commissionBalance),
                  label: 'Commission wallet',
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          if (low) ...[
            const SizedBox(height: 12),
            const UdBanner(
              tone: UdTone.warn,
              icon: Icons.account_balance_wallet_outlined,
              text: 'Your commission wallet is empty, so no new ride requests '
                  'will reach you. Top it up to start receiving work again.',
            ),
          ],
        ],
      ),
    );
  }
}

/// This month's two numbers.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.dashboard});

  final DriverDashboard dashboard;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: UdStat(
                value: 'PKR '
                    '${NumberFormat('#,###').format(dashboard.earnedThisMonth.round())}',
                label: 'This month',
              ),
            ),
            Expanded(
              child: UdStat(
                value: '${dashboard.completedTrips}',
                label: 'Rides completed',
                align: CrossAxisAlignment.end,
              ),
            ),
          ],
        ),
      );
}

/// D-46 — the rating, and what passengers wrote.
///
/// Never a default score. A driver nobody has rated is shown as such, because
/// a "5.0" that nobody gave is worse than a blank.
class _RatingBlock extends StatelessWidget {
  const _RatingBlock({required this.dashboard});

  final DriverDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final rating = dashboard.rating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdCard(
          child: rating == null
              ? Row(
                  children: [
                    const UdIconTile(
                      icon: Icons.star_outline_rounded,
                      tone: UdIconTone.neutral,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'No ratings yet. Your first rated trip starts this.',
                        style: AppType.small
                            .copyWith(height: 1.45, color: AppText.secondary),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.star_rounded, size: 34, color: AppTint.star),
                    const SizedBox(width: 10),
                    Text(
                      rating.toStringAsFixed(1),
                      style: AppType.display.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'from ${dashboard.ratingCount} '
                        'passenger${dashboard.ratingCount == 1 ? '' : 's'}',
                        style: AppType.small.copyWith(
                          height: 1.4,
                          color: AppText.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (dashboard.recentReviews.isNotEmpty) ...[
          const SizedBox(height: 22),
          const UdSectionHeader(title: 'What passengers say'),
          const SizedBox(height: 12),
          for (final review in dashboard.recentReviews)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: UdCard(
                tone: UdCardTone.flat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        UdAvatar(
                          initials: _initials(review.reviewerFirstName),
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            review.reviewerFirstName,
                            style: AppType.listTitle.copyWith(
                              fontSize: 15.5,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= review.rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 15,
                            color: i <= review.rating
                                ? AppTint.star
                                : AppColors.borderStrong,
                          ),
                      ],
                    ),
                    if (review.text != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        review.text!,
                        style: AppType.small.copyWith(
                          height: 1.5,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'P' : value;
  }
}
