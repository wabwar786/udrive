import 'package:flutter/material.dart';

import '../../core/growth/driver_growth_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';
import 'driver_mission_detail_screen.dart';
import 'driver_referral_screen.dart';
import 'driver_rewards_shared.dart';
import 'driver_updates_screen.dart';
import 'driver_weekly_screen.dart';
import 'driver_welcome_bonus_screen.dart';

/// Everything a driver can earn today that is not a fare.
///
/// The screen a driver opens when there are no rides, which during a launch is
/// most of the day. So it is ordered by what they can still do something about:
/// what is in progress, then what is already earned, then what has been paid.
/// A mission they cannot affect any more sits at the bottom.
class DriverMissionsScreen extends StatefulWidget {
  const DriverMissionsScreen({super.key});

  @override
  State<DriverMissionsScreen> createState() => _DriverMissionsScreenState();
}

class _DriverMissionsScreenState extends State<DriverMissionsScreen> {
  List<DriverMission> _missions = const [];
  WelcomeBonus? _bonus;
  bool _loading = true;

  /// 0 = open, 1 = done today.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository =
        DriverGrowthRepository(AppControllerScope.of(context).apiClient);
    final missions = await repository.missions();
    final bonus = await repository.welcomeBonus();
    if (!mounted) return;
    setState(() {
      _missions = missions;
      _bonus = bonus;
      _loading = false;
    });
  }

  /// Pushes a reward screen and reloads on the way back, because a milestone
  /// can be credited while one of them is open.
  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  static const _openStatuses = {'InProgress', 'Qualified', 'OnHold'};

  List<DriverMission> get _visible => _missions
      .where((mission) => _tab == 0
          ? _openStatuses.contains(mission.status)
          : !_openStatuses.contains(mission.status))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final openCount =
        _missions.where((m) => _openStatuses.contains(m.status)).length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: 'Rewards & missions',
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 14, AppSizes.sidePadding, 34),
                children: [
                  // The welcome bonus sits above the missions because it is the
                  // larger number and the one a new driver is waiting on.
                  if (_bonus != null) ...[
                    _BonusSummaryCard(
                      bonus: _bonus!,
                      onOpen: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverWelcomeBonusScreen(),
                          ),
                        );
                        if (mounted) await _load();
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  // The three screens this release adds. They live here rather
                  // than on the dashboard because this is the screen a Driver
                  // opens when they are looking for something to earn, and
                  // because the dashboard already carries one card per reward
                  // and cannot take three more rows.
                  UdListGroup(
                    children: [
                      UdListRow(
                        title: 'This week',
                        subtitle: "The weekly target, and what last week came to",
                        leading: const UdIconTile(
                          icon: Icons.calendar_today_rounded,
                          tone: UdIconTone.lime,
                        ),
                        showChevron: true,
                        onTap: () => _open(const DriverWeeklyScreen()),
                      ),
                      UdListRow(
                        title: 'Invite a driver',
                        subtitle: 'Your code, and what each invite has earned',
                        leading: const UdIconTile(
                          icon: Icons.group_add_rounded,
                          tone: UdIconTone.navy,
                        ),
                        showChevron: true,
                        onTap: () => _open(const DriverReferralScreen()),
                      ),
                      UdListRow(
                        title: 'Updates',
                        subtitle: 'Roads, busy days and policy for your city',
                        leading: const UdIconTile(
                          icon: Icons.campaign_rounded,
                          tone: UdIconTone.soft,
                        ),
                        showChevron: true,
                        onTap: () => _open(const DriverUpdatesScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  if (_missions.isNotEmpty) ...[
                    Row(
                      children: [
                        _Tab(
                          label: 'Open',
                          count: openCount,
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                        const SizedBox(width: 8),
                        _Tab(
                          label: 'Finished',
                          count: _missions.length - openCount,
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (visible.isEmpty)
                    RewardEmptyState(
                      title: _missions.isEmpty
                          ? 'No missions right now'
                          : _tab == 0
                              ? 'Nothing open'
                              : 'Nothing finished yet',
                      text: _missions.isEmpty
                          ? 'UDrive runs missions and peak hour rewards during '
                              'a city launch. When one is running in your city '
                              'it appears here.'
                          : _tab == 0
                              ? "You've finished everything available today. "
                                  'New missions appear each day.'
                              : 'Missions you finish today will be listed here.',
                    )
                  else
                    for (final mission in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RewardMissionCard(
                          mission: mission,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DriverMissionDetailScreen(mission: mission),
                              ),
                            );
                            if (mounted) await _load();
                          },
                        ),
                      ),

                  if (_missions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const BonusNotCashNote(),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : AppColors.background,
        borderRadius: AppRadii.all(AppRadii.chip),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(AppRadii.chip),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(AppRadii.chip),
              border: Border.all(
                color: selected ? AppColors.navy : AppColors.border,
              ),
            ),
            child: Text(
              count > 0 ? '$label  $count' : label,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? AppText.onInk : AppText.secondary,
              ),
            ),
          ),
        ),
      );
}

class _BonusSummaryCard extends StatelessWidget {
  const _BonusSummaryCard({required this.bonus, required this.onOpen});

  final WelcomeBonus bonus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => UdCard(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bonus.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.overline.copyWith(color: AppText.caption),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppText.secondary),
              ],
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                text: rewardRupees(bonus.unlockedAmount),
                style: AppType.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
                children: [
                  TextSpan(
                    text: '  unlocked of ${rewardRupees(bonus.totalAmount)}',
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 11),
            UdProgress(value: bonus.fraction, lime: true),
            if (bonus.nextMilestone != null) ...[
              const SizedBox(height: 8),
              Text(
                'Next ${rewardRupees(bonus.nextMilestone!.rewardAmount)} — '
                '${bonus.nextMilestone!.title}',
                maxLines: 2,
                style: AppType.caption.copyWith(color: AppText.secondary),
              ),
            ],
          ],
        ),
      );
}
