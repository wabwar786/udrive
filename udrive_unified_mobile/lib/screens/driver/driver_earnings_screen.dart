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

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = DriverFinanceRepository(ApiClient(SessionStore()));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboard());
  }

  Future<void> _loadDashboard() async {
    final controller = AppControllerScope.of(context);
    final dashboard =
        await TripChatRepository(controller.apiClient).driverDashboard();
    if (!mounted || dashboard == null) return;
    setState(() => _dashboard = dashboard);
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
      onRefresh: _load,
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
            "Your rating, this month's trips, and your prepaid wallet.",
            style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 20),

          if (_dashboard != null) ...[
            _MonthCard(dashboard: _dashboard!),
            const SizedBox(height: 14),
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
