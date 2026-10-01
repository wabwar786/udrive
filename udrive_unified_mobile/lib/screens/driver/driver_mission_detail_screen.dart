import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';
import 'driver_rewards_shared.dart';

/// One mission or peak-hour reward, with the rules written out.
///
/// The rules are the point of this screen. A reward whose conditions a driver
/// can only discover by failing it is worse than no reward — they conclude the
/// platform moved the goalposts, and they tell every other driver so. So every
/// condition the admin configured is listed, including the ones that cannot be
/// shown as a progress bar.
///
/// It also refuses to call anything guaranteed. A peak-hour reward is a reward
/// for meeting conditions; "guaranteed earnings" is a promise the business has
/// not made.
class DriverMissionDetailScreen extends StatelessWidget {
  const DriverMissionDetailScreen({required this.mission, super.key});

  final DriverMission mission;

  @override
  Widget build(BuildContext context) {
    final state = rewardStatus(mission.status);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: mission.isPeakHour ? 'Peak hour reward' : 'Mission',
        onBack: () => Navigator.maybePop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 14, AppSizes.sidePadding, 34),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: AppRadii.all(AppRadii.largeCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mission.windowLabel != null) ...[
                  Text(
                    'TODAY',
                    style: AppType.overline.copyWith(color: AppText.onInkMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mission.windowLabel!,
                    style: AppType.h1.copyWith(color: AppText.onInk),
                  ),
                ] else
                  Text(
                    mission.title,
                    style: AppType.h2.copyWith(color: AppText.onInk),
                  ),
                if (mission.zoneName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    mission.zoneName!,
                    style: AppType.small.copyWith(color: AppText.onInkMuted),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: AppRadii.all(AppRadii.chip),
                  ),
                  child: Text(
                    'Reward ${rewardRupees(mission.rewardAmount)}',
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppText.onBrand,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (mission.windowLabel != null && mission.title.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              mission.title,
              style: AppType.listTitle.copyWith(color: AppText.primary),
            ),
          ],

          if (mission.description != null) ...[
            const SizedBox(height: 6),
            Text(
              mission.description!,
              style: AppType.body2.copyWith(
                height: 1.5,
                color: AppText.secondary,
              ),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR PROGRESS',
                  style: AppType.overline.copyWith(color: AppText.caption),
                ),
              ),
              UdBadge(label: state.label, tone: state.tone),
            ],
          ),
          const SizedBox(height: 10),
          UdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UdProgress(
                  value: mission.fraction,
                  lime: mission.status != 'Credited',
                ),
                const SizedBox(height: 8),
                Text(
                  mission.status == 'Credited'
                      ? 'Paid into your bonus balance.'
                      : mission.status == 'Qualified'
                          ? 'Finished. The bonus is credited at the end of the day.'
                          : mission.progressLabel,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: mission.status == 'InProgress'
                        ? AppText.secondary
                        : AppColors.brandInk,
                  ),
                ),
              ],
            ),
          ),

          if (mission.holdReason != null) ...[
            const SizedBox(height: 12),
            UdBanner(
              tone: UdTone.warn,
              icon: Icons.pause_circle_outline_rounded,
              text: mission.holdReason,
            ),
          ],

          ..._conditions(),

          const SizedBox(height: 18),
          const BonusNotCashNote(),
          const SizedBox(height: 10),
          UdBanner(
            tone: UdTone.gray,
            icon: Icons.shield_outlined,
            text: 'This is a reward for meeting the conditions above, not '
                'guaranteed earnings. Mock GPS or repeatedly switching online '
                'and offline puts a reward on hold for review.',
          ),
        ],
      ),
    );
  }

  /// The admin's conditions, listed only where they exist.
  ///
  /// Null is not zero. A campaign with no cancellation limit must not show
  /// "maximum 0 cancellations", which is the strictest possible rule and the
  /// opposite of what was configured.
  List<Widget> _conditions() {
    final rules = <String>[
      if (mission.zoneName != null) 'Stay inside ${mission.zoneName}',
      if (mission.windowLabel != null)
        'Be online between ${mission.windowLabel}',
      if (mission.minOnlineSeconds != null)
        'Online for at least ${rewardDuration(mission.minOnlineSeconds!)}',
      if (mission.minAcceptedRides != null)
        'Accept at least ${mission.minAcceptedRides} '
            'ride${mission.minAcceptedRides == 1 ? '' : 's'}',
      if (mission.minCompletedRides != null)
        'Complete at least ${mission.minCompletedRides} '
            'ride${mission.minCompletedRides == 1 ? '' : 's'}',
      if (mission.maxCancellations != null)
        'No more than ${mission.maxCancellations} '
            'cancellation${mission.maxCancellations == 1 ? '' : 's'}',
      if (mission.minRating != null)
        'Keep your rating at ${mission.minRating!.toStringAsFixed(1)} or above',
      if (mission.minAcceptanceRate != null)
        'Keep acceptance at ${mission.minAcceptanceRate!.round()}% or above',
      // Always true, always worth saying: a reward measured in online time is
      // measured from the server's heartbeat, and a phone with location off
      // sends nothing.
      'Keep GPS on and the app running',
    ];

    if (rules.isEmpty) return const [];

    return [
      const SizedBox(height: 20),
      Text(
        'TO QUALIFY',
        style: AppType.overline.copyWith(color: AppText.caption),
      ),
      const SizedBox(height: 10),
      UdCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var i = 0; i < rules.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 18, color: AppColors.brandInk),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        rules[i],
                        style: AppType.small.copyWith(
                          height: 1.4,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}
