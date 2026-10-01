import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';
import 'driver_rewards_shared.dart';

/// The founding driver badge, and what it is worth.
///
/// The badge is the cheapest retention UDrive has: a driver who is #74 in
/// Mirpur is holding a number nobody can take and nobody arriving later can
/// have. That is worth saying plainly.
///
/// What it is deliberately not allowed to do is invent the benefits. Those come
/// from FoundingBenefit campaigns an admin configured, and when none exist the
/// screen says the benefits are being set up rather than listing things the
/// business has not agreed to pay for.
class DriverFoundingScreen extends StatelessWidget {
  const DriverFoundingScreen({required this.founding, super.key});

  final FoundingDriver founding;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.surface,
        appBar: UdTopBar(
          title: 'Founding driver',
          onBack: () => Navigator.maybePop(context),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 14, AppSizes.sidePadding, 34),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: AppRadii.all(AppRadii.largeCard),
              ),
              child: Column(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: AppRadii.all(AppRadii.largeCard),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded,
                        size: 38, color: AppColors.navy),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'UDrive Founding Driver',
                    textAlign: TextAlign.center,
                    style: AppType.h2.copyWith(color: AppText.onInk),
                  ),
                  if (founding.cityName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      founding.cityName!,
                      style: AppType.small.copyWith(color: AppText.onInkMuted),
                    ),
                  ],
                  if (founding.sequenceNo != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.inkPanel,
                        borderRadius: AppRadii.all(AppRadii.chip),
                      ),
                      child: Text(
                        'Founding Driver #${founding.sequenceNo}',
                        style: AppType.small.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppText.onInk,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),
            UdCard(
              tone: UdCardTone.tint,
              child: Text(
                'You are among the first drivers building UDrive in your city.',
                textAlign: TextAlign.center,
                style: AppType.body2.copyWith(
                  height: 1.5,
                  color: AppColors.brandInk,
                ),
              ),
            ),

            const SizedBox(height: 20),
            UdCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (founding.grantedAt != null) ...[
                    _Fact(
                      label: 'Joined',
                      value:
                          DateFormat('d MMM yyyy').format(founding.grantedAt!),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                  ],
                  if (founding.cityName != null) ...[
                    _Fact(label: 'Launch city', value: founding.cityName!),
                    const Divider(height: 1, color: AppColors.border),
                  ],
                  const _Fact(label: 'Status', value: 'Active'),
                ],
              ),
            ),

            const SizedBox(height: 22),
            Text(
              'YOUR BENEFITS',
              style: AppType.overline.copyWith(color: AppText.caption),
            ),
            const SizedBox(height: 10),

            if (founding.benefits.isEmpty)
              const UdEmptyState(
                icon: Icons.schedule_rounded,
                title: 'Benefits are being set up',
                text: 'Your founding driver benefits for this city are being '
                    'finalised. They will appear here as soon as they are live.',
              )
            else
              UdCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (var i = 0; i < founding.benefits.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.border),
                      _Benefit(benefit: founding.benefits[i]),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 14),
            Text(
              'Benefits are set by UDrive and can change.',
              style: AppType.caption.copyWith(color: AppText.caption),
            ),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
            ),
            Text(
              value,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ],
        ),
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.benefit});

  final DriverMission benefit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandWash,
                borderRadius: AppRadii.all(AppRadii.tile),
              ),
              child: const Icon(Icons.verified_rounded,
                  size: 19, color: AppColors.brandInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    benefit.title,
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  if (benefit.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      benefit.description!,
                      style: AppType.caption.copyWith(
                        height: 1.4,
                        color: AppText.secondary,
                      ),
                    ),
                  ],
                  if (benefit.windowEndsAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Until ${DateFormat('d MMM yyyy').format(benefit.windowEndsAt!)}',
                      style: AppType.caption.copyWith(color: AppText.caption),
                    ),
                  ],
                ],
              ),
            ),
            if (benefit.rewardAmount > 0) ...[
              const SizedBox(width: 10),
              Text(
                rewardRupees(benefit.rewardAmount),
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
              ),
            ],
          ],
        ),
      );
}
