/// Pieces every reward screen shares.
///
/// In one file rather than copied four times, because the thing they all have
/// in common is a promise about money — and a progress bar that means one thing
/// on the missions screen and something slightly different on the bonus screen
/// is how a driver stops trusting both.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';

String rewardRupees(num value) =>
    'PKR ${NumberFormat('#,###').format(value.round())}';

/// Seconds as a driver would say them.
String rewardDuration(int seconds) {
  if (seconds <= 0) return '0m';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// What a reward's status means, in words and in colour.
///
/// Five states, and the two that matter most are the ones a driver would
/// otherwise read as failure: Qualified means the work is done and the money is
/// coming, and OnHold means the work is done and something else is in the way —
/// which is a thing to go and read, not a thing to give up on.
({String label, UdTone tone}) rewardStatus(String status) => switch (status) {
      'Credited' => (label: 'Paid', tone: UdTone.ok),
      'Qualified' => (label: 'Earned', tone: UdTone.lime),
      'OnHold' => (label: 'On hold', tone: UdTone.warn),
      'Expired' => (label: 'Expired', tone: UdTone.gray),
      'Rejected' => (label: 'Not paid', tone: UdTone.err),
      _ => (label: 'In progress', tone: UdTone.gray),
    };

/// The card a mission appears as, on every screen that lists missions.
class RewardMissionCard extends StatelessWidget {
  const RewardMissionCard({required this.mission, this.onTap, super.key});

  final DriverMission mission;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = rewardStatus(mission.status);
    final done = mission.status == 'Credited' || mission.status == 'Qualified';

    return UdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  mission.title,
                  style: AppType.listTitle.copyWith(color: AppText.primary),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(label: rewardRupees(mission.rewardAmount), tone: state.tone),
            ],
          ),

          // The window and the area, when there is one. A peak-hour reward with
          // no time on the card is a reward a driver can miss by an hour.
          if (mission.windowLabel != null || mission.zoneName != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (mission.windowLabel != null) mission.windowLabel!,
                if (mission.zoneName != null) mission.zoneName!,
              ].join('  ·  '),
              style: AppType.caption.copyWith(color: AppText.secondary),
            ),
          ],

          if (mission.description != null) ...[
            const SizedBox(height: 6),
            Text(
              mission.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                height: 1.4,
                color: AppText.secondary,
              ),
            ),
          ],

          const SizedBox(height: 11),
          UdProgress(value: mission.fraction, lime: !done),
          const SizedBox(height: 7),

          Row(
            children: [
              Expanded(
                child: Text(
                  mission.status == 'Credited'
                      ? 'Credited to your bonus balance'
                      : mission.status == 'Qualified'
                          ? 'Earned — credited at the end of the day'
                          : mission.progressLabel,
                  style: AppType.caption.copyWith(
                    fontWeight: done ? FontWeight.w800 : FontWeight.w600,
                    color: done ? AppColors.brandInk : AppText.secondary,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppText.secondary),
            ],
          ),

          // The reason a finished mission has not paid. Shown in full, because
          // a driver who cannot see it will ring support instead.
          if (mission.holdReason != null) ...[
            const SizedBox(height: 10),
            UdBanner(
              tone: UdTone.warn,
              icon: Icons.pause_circle_outline_rounded,
              text: mission.holdReason,
            ),
          ],
        ],
      ),
    );
  }
}

/// The line that has to appear wherever a bonus amount does.
///
/// A driver who believes the bonus is cash finds out at payout, and that is the
/// worst possible moment and the one they will tell other drivers about.
class BonusNotCashNote extends StatelessWidget {
  const BonusNotCashNote({super.key});

  @override
  Widget build(BuildContext context) => UdBanner(
        tone: UdTone.warn,
        icon: Icons.info_outline_rounded,
        text: 'Bonus goes to your bonus balance. It pays your UDrive '
            'commission and cannot be withdrawn as cash.',
      );
}

/// What a reward screen shows when the server has nothing configured.
class RewardEmptyState extends StatelessWidget {
  const RewardEmptyState({required this.title, required this.text, super.key});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => UdEmptyState(
        icon: Icons.star_outline_rounded,
        title: title,
        text: text,
      );
}
