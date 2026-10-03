import 'package:flutter/material.dart';

import '../../core/growth/driver_growth_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';

/// D-62 — this week's target, and what last week came to.
///
/// The engine has understood `WeeklyReward` from the start: it has a period key
/// that buckets by ISO week, an expiry that lands on Monday morning, and a place
/// in every list of campaign types. What it never had was anywhere to appear. A
/// target a Driver cannot see is not a target — it is a rule the platform
/// applies to them privately, and nobody changes their week for one of those.
///
/// Last week is deliberately four lines. What was earned, how many rides,
/// whether the reward landed, and the single day that paid best — that last one
/// being the only part a Driver can act on, because it tells them which day to
/// keep clear.
class DriverWeeklyScreen extends StatefulWidget {
  const DriverWeeklyScreen({super.key});

  @override
  State<DriverWeeklyScreen> createState() => _DriverWeeklyScreenState();
}

class _DriverWeeklyScreenState extends State<DriverWeeklyScreen> {
  late final DriverGrowthRepository _repository =
      DriverGrowthRepository(AppControllerScope.of(context).apiClient);

  DriverWeekly? _week;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  Future<void> _load() async {
    setState(() => _loading = true);
    final week = await _repository.weekly();
    if (!mounted) return;
    setState(() {
      _week = week;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('This week', 'یہ ہفتہ'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 14, AppSizes.sidePadding, 40),
                children: week == null
                    ? [
                        UdEmptyState(
                          icon: Icons.calendar_today_outlined,
                          title: _t('Not available', 'دستیاب نہیں'),
                          text: _t('Pull down to try again.',
                              'نیچے کھینچ کر دوبارہ کوشش کریں۔'),
                        ),
                      ]
                    : _content(week),
              ),
            ),
    );
  }

  List<Widget> _content(DriverWeekly week) => [
        if (week.hasTarget)
          _Target(week: week, t: _t)
        else
          // Said plainly instead of drawing a bar against zero, which reads as
          // a bug rather than as "there is no target".
          UdBanner(
            tone: UdTone.info,
            icon: Icons.info_outline_rounded,
            text: _t(
              'No weekly target is running in your city right now. Your rides '
              'this week: ${week.ridesThisWeek}.',
              'آپ کے شہر میں اس وقت کوئی ہفتہ وار ٹارگٹ نہیں چل رہا۔ اس ہفتے '
                  'آپ کی رائیڈز: ${week.ridesThisWeek}۔',
            ),
          ),

        const SizedBox(height: 22),
        UdSectionHeader(title: _t('Last week', 'پچھلا ہفتہ')),
        const SizedBox(height: 10),
        UdListGroup(
          children: [
            UdListRow(
              title: 'PKR ${week.lastWeekEarnings.round()}',
              subtitle: _t(
                '${week.lastWeekRides} ride(s) · '
                '${(week.lastWeekOnlineSeconds / 3600).round()} hour(s) online',
                '${week.lastWeekRides} رائیڈ · '
                    '${(week.lastWeekOnlineSeconds / 3600).round()} گھنٹے آن لائن',
              ),
              leading: const UdIconTile(
                icon: Icons.payments_outlined,
                tone: UdIconTone.soft,
              ),
            ),
            if (week.lastWeekReward > 0 || week.lastWeekRewardEarned)
              UdListRow(
                title: 'PKR ${week.lastWeekReward.round()}',
                subtitle: week.lastWeekRewardEarned
                    ? _t('Weekly target reached', 'ہفتہ وار ٹارگٹ پورا ہوا')
                    : _t('Weekly target missed', 'ہفتہ وار ٹارگٹ رہ گیا'),
                leading: UdIconTile(
                  icon: week.lastWeekRewardEarned
                      ? Icons.check_rounded
                      : Icons.remove_rounded,
                  tone: week.lastWeekRewardEarned
                      ? UdIconTone.soft
                      : UdIconTone.neutral,
                ),
                trailing: UdBadge(
                  label: week.lastWeekRewardEarned
                      ? _t('PAID', 'ملا')
                      : _t('MISSED', 'نہیں ملا'),
                  tone: week.lastWeekRewardEarned ? UdTone.ok : UdTone.gray,
                ),
              ),
            if (week.lastWeekBestDay != null)
              UdListRow(
                title: _t('Best day — ${week.lastWeekBestDay}',
                    'بہترین دن — ${week.lastWeekBestDay}'),
                subtitle: 'PKR ${week.lastWeekBestDayEarnings.round()} · '
                    '${week.lastWeekBestDayRides} ride(s)',
                leading: const UdIconTile(
                  icon: Icons.trending_up_rounded,
                  tone: UdIconTone.neutral,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _t(
            'Weeks run Monday to Sunday, Pakistan time — the same week the '
            'reward is counted against.',
            'ہفتہ پیر سے اتوار تک، پاکستان کے وقت کے مطابق — اسی ہفتے کے حساب '
                'سے انعام گنا جاتا ہے۔',
          ),
          style: AppType.caption.copyWith(color: AppText.caption),
        ),
      ];
}

/// The target, as a bar with the number of rides still to go under it.
class _Target extends StatelessWidget {
  const _Target({required this.week, required this.t});

  final DriverWeekly week;
  final String Function(String, String) t;

  @override
  Widget build(BuildContext context) {
    return UdCard(
      selected: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('THIS WEEK', 'اس ہفتے').toUpperCase(),
                      style: AppType.caption.copyWith(
                        color: AppColors.brandInk,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${week.ridesThisWeek} / ${week.targetRides} '
                      '${t('rides', 'رائیڈز')}',
                      style: AppType.h1.copyWith(
                        color: AppText.primary,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'PKR ${week.rewardAmount.round()}',
                style: AppType.h3.copyWith(color: AppColors.brandInk),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: AppRadii.all(999),
            child: LinearProgressIndicator(
              value: week.progress,
              minHeight: 11,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(
                week.rewardEarned ? AppColors.brandInk : AppColors.brand,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            week.rewardEarned
                ? t('Reward earned — it will be credited shortly.',
                    'انعام مل گیا — جلد والیٹ میں آ جائے گا۔')
                : week.ridesLeft == 0
                    ? t('Target reached.', 'ٹارگٹ پورا ہو گیا۔')
                    : t('${week.ridesLeft} ride(s) to go · until Sunday night',
                        '${week.ridesLeft} رائیڈ باقی · اتوار رات تک'),
            style: AppType.small.copyWith(color: AppColors.brandInk),
          ),
        ],
      ),
    );
  }
}
