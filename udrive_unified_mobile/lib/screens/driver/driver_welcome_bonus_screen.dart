import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/growth/driver_growth_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';
import 'driver_rewards_shared.dart';

/// The staged welcome bonus — how much is unlocked and what unlocks next.
///
/// Shown as six steps rather than one figure because that is what it is. A
/// driver told only "Rs 1,000 welcome bonus" and then paid Rs 200 believes they
/// were short-changed; a driver who can see which three steps are done and
/// which three are left is being told the truth before they have to ask.
///
/// Every amount, condition and date here is the admin's configuration. The
/// screen has no numbers of its own, which is why it shows nothing at all when
/// no bonus has been set up.
class DriverWelcomeBonusScreen extends StatefulWidget {
  const DriverWelcomeBonusScreen({super.key});

  @override
  State<DriverWelcomeBonusScreen> createState() =>
      _DriverWelcomeBonusScreenState();
}

class _DriverWelcomeBonusScreenState extends State<DriverWelcomeBonusScreen> {
  WelcomeBonus? _bonus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = AppControllerScope.of(context);
    final bonus = await DriverGrowthRepository(controller.apiClient).welcomeBonus();
    if (!mounted) return;
    setState(() {
      _bonus = bonus;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bonus = _bonus;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: 'Welcome bonus',
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : bonus == null
              ? const Padding(
                  padding: EdgeInsets.all(AppSizes.sidePadding),
                  child: RewardEmptyState(
                    title: 'No welcome bonus right now',
                    text: 'UDrive runs welcome bonuses during a city launch. '
                        'When one is running in your city it appears here.',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.navy,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSizes.sidePadding, 14, AppSizes.sidePadding, 34),
                    children: [
                      _BonusHeader(bonus: bonus),
                      if (bonus.nextMilestone != null) ...[
                        const SizedBox(height: 12),
                        _NextReward(milestone: bonus.nextMilestone!),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        'MILESTONES',
                        style: AppType.overline.copyWith(color: AppText.caption),
                      ),
                      const SizedBox(height: 10),
                      UdCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (var i = 0; i < bonus.milestones.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1, color: AppColors.border),
                              _MilestoneRow(
                                index: i + 1,
                                milestone: bonus.milestones[i],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const BonusNotCashNote(),
                      if (bonus.endsAt != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Valid until '
                          '${DateFormat('d MMM yyyy').format(bonus.endsAt!)}',
                          style: AppType.caption.copyWith(
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _BonusHeader extends StatelessWidget {
  const _BonusHeader({required this.bonus});

  final WelcomeBonus bonus;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: AppRadii.all(AppRadii.largeCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bonus.title.toUpperCase(),
              style: AppType.overline.copyWith(color: AppText.onInkMuted),
            ),
            const SizedBox(height: 6),
            Text(
              rewardRupees(bonus.totalAmount),
              style: AppType.display.copyWith(color: AppText.onInk),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: AppRadii.all(AppRadii.chip),
              child: LinearProgressIndicator(
                value: bonus.fraction,
                minHeight: 8,
                backgroundColor: AppColors.inkPanel,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _HeaderFigure(
                    value: rewardRupees(bonus.unlockedAmount),
                    label: 'Unlocked',
                    accent: true,
                  ),
                ),
                Expanded(
                  child: _HeaderFigure(
                    value: rewardRupees(bonus.remainingAmount),
                    label: 'Remaining',
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _HeaderFigure extends StatelessWidget {
  const _HeaderFigure({
    required this.value,
    required this.label,
    this.accent = false,
    this.alignEnd = false,
  });

  final String value;
  final String label;
  final bool accent;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppType.h3.copyWith(
              fontWeight: FontWeight.w800,
              color: accent ? AppColors.brand : AppText.onInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppType.caption.copyWith(color: AppText.onInkMuted),
          ),
        ],
      );
}

class _NextReward extends StatelessWidget {
  const _NextReward({required this.milestone});

  final GrowthMilestone milestone;

  @override
  Widget build(BuildContext context) => UdCard(
        tone: UdCardTone.tint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXT REWARD',
              style: AppType.overline.copyWith(color: AppColors.brandInk),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rewardRupees(milestone.rewardAmount),
                        style: AppType.h3.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        milestone.title,
                        style: AppType.caption.copyWith(
                          color: AppColors.brandInk,
                        ),
                      ),
                    ],
                  ),
                ),
                if (milestone.targetValue > 1)
                  Text(
                    '${milestone.progressValue.round()} / '
                    '${milestone.targetValue.round()}',
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandInk,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.index, required this.milestone});

  final int index;
  final GrowthMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final credited = milestone.isCredited;
    final active = milestone.isQualified ||
        (!credited && milestone.progressValue > 0) ||
        (!credited && milestone.status == 'InProgress' && index == 1);

    // Three states, three weights. A locked step is deliberately quiet: it is
    // not a failure, it is simply not this week's work.
    final (Color tileColour, Color tileInk) = credited
        ? (AppColors.brand, AppColors.navy)
        : active
            ? (AppColors.navy, AppText.onInk)
            : (AppColors.surfaceAlt, AppText.disabled);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tileColour,
              shape: BoxShape.circle,
            ),
            child: credited
                ? Icon(Icons.check_rounded, size: 15, color: tileInk)
                : Text(
                    '$index',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: tileInk,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.title,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: credited || active
                        ? AppText.primary
                        : AppText.disabled,
                  ),
                ),
                if (milestone.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    milestone.description!,
                    style: AppType.caption.copyWith(color: AppText.caption),
                  ),
                ],

                // The bar only appears on the step being worked on. On a
                // finished step it says nothing, and on a locked one it would
                // be a zero-length bar implying failure.
                if (active && !credited && milestone.targetValue > 1) ...[
                  const SizedBox(height: 8),
                  UdProgress(value: milestone.fraction, lime: true),
                  const SizedBox(height: 5),
                  Text(
                    '${milestone.progressValue.round()} of '
                    '${milestone.targetValue.round()}',
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ],

                if (credited && milestone.creditedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Credited ${DateFormat('d MMM').format(milestone.creditedAt!)}',
                    style: AppType.caption.copyWith(color: AppColors.brandInk),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            rewardRupees(milestone.rewardAmount),
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w800,
              color: credited || active ? AppText.primary : AppText.disabled,
            ),
          ),
        ],
      ),
    );
  }
}
