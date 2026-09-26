import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';

// PackageBookingsScreen was here — a mock booking list over `controller
// .packageBookings` with a hardcoded "5" for seats booked. Nothing routed it;
// the real screen is LiveDriverPackageBookingsScreen, the second segment of
// TourOperationsScreen.

/// D-35 — which routes each vehicle is allowed on, and what is missing.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class VehicleSuitabilityScreen extends StatelessWidget {
  const VehicleSuitabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
      children: [
        UdBanner(
          tone: UdTone.info,
          icon: Icons.terrain_rounded,
          text: context.tr('vehicleSuitabilityHelp'),
        ),
        const SizedBox(height: 18),
        if (controller.vehicles.isEmpty)
          const UdEmptyState(
            icon: Icons.directions_car_outlined,
            title: 'No vehicle yet',
            text: 'Register a vehicle and its capabilities appear here.',
          )
        else
          ...controller.vehicles.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: UdCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const UdIconTile(
                          icon: Icons.directions_car_filled_rounded,
                          tone: UdIconTone.soft,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${vehicle.make} ${vehicle.model}',
                                style: AppType.h3
                                    .copyWith(color: AppText.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${vehicle.registration} · ${vehicle.category}',
                                style: AppType.small
                                    .copyWith(color: AppText.secondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        UdBadge(
                          label: '${vehicle.readinessScore}% '
                              '${context.tr('ready')}',
                          tone: vehicle.readinessScore >= 80
                              ? UdTone.ok
                              : UdTone.warn,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    UdProgress(
                      value: vehicle.readinessScore / 100,
                      lime: vehicle.readinessScore >= 80,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Capability(
                            label: context.tr('city'), enabled: true),
                        _Capability(
                            label: context.tr('intercity'), enabled: true),
                        _Capability(
                          label: context.tr('familyTours'),
                          enabled: vehicle.childSeat || vehicle.seats >= 5,
                        ),
                        _Capability(
                          label: context.tr('mountainRoads'),
                          enabled: vehicle.mountainReady,
                        ),
                        _Capability(
                          label: context.tr('snowRoutes'),
                          enabled:
                              vehicle.fourWheelDrive && vehicle.snowChains,
                        ),
                        _Capability(
                          label: context.tr('fourByFourRoutes'),
                          enabled: vehicle.fourWheelDrive,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // What to do about it, when there is something to do.
                    // A vehicle that is ready gets the quiet version.
                    UdBanner(
                      tone: vehicle.mountainReady ? UdTone.ok : UdTone.warn,
                      icon: vehicle.mountainReady
                          ? Icons.check_circle_outline_rounded
                          : Icons.build_outlined,
                      text: vehicle.mountainReady
                          ? context.tr('mountainReadyMessage')
                          : context.tr('mountainEquipmentMessage'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One route type a vehicle either can or cannot take.
///
/// Shape as well as colour: a tick or a padlock, so the difference survives a
/// colour-blind driver and a phone in sunlight.
class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.enabled});
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink, Color edge) = enabled
        ? (AppTint.success, AppTint.successText, AppTint.successBorder)
        : (AppColors.surface, AppText.caption, AppColors.border);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppRadii.all(999),
        border: Border.all(color: edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            size: 16,
            color: ink,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// D-36 — road conditions, reported by drivers and verified by operations.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class DriverRoadReportsScreen extends StatelessWidget {
  const DriverRoadReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
      children: [
        UdButton.primary(
          label: context.tr('reportRoadCondition'),
          icon: Icons.add_road_rounded,
          onPressed: () => _newReport(context, controller),
        ),
        const SizedBox(height: 16),
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.fact_check_rounded,
          text: context.tr('driverReportNotice'),
        ),
        const SizedBox(height: 20),
        if (controller.roadReports.isEmpty)
          const UdEmptyState(
            icon: Icons.add_road_rounded,
            title: 'No reports yet',
            text: 'Report a road condition and it appears here for other '
                'drivers.',
          )
        else
          ...controller.roadReports.map(
            (report) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: UdCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The icon says what kind of report it is. Every one of
                    // them used to be the same amber warning triangle,
                    // including "Road open".
                    UdIconTile(
                      icon: _icon(report.type),
                      tone: _open(report.type)
                          ? UdIconTone.soft
                          : UdIconTone.warn,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            report.route,
                            style: AppType.listTitle
                                .copyWith(fontSize: 16, color: AppText.primary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${report.type} · ${report.details}',
                            style: AppType.small.copyWith(
                              height: 1.45,
                              color: AppText.secondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              UdBadge(
                                label: report.status,
                                tone: report.status.startsWith('Verified')
                                    ? UdTone.ok
                                    : UdTone.gray,
                                icon: report.status.startsWith('Verified')
                                    ? Icons.verified_rounded
                                    : Icons.people_outline_rounded,
                              ),
                              const Spacer(),
                              Text(
                                report.reportedAt,
                                style: AppType.caption
                                    .copyWith(color: AppText.caption),
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
          ),
      ],
    );
  }

  static const _types = <String>[
    'Road blocked',
    'Landslide risk',
    'Heavy rain',
    'Snow or ice',
    'Bridge issue',
    'Traffic delay',
    'Road open',
  ];

  static bool _open(String type) => type == 'Road open';

  static IconData _icon(String type) => switch (type) {
        'Road open' => Icons.check_circle_outline_rounded,
        'Landslide risk' => Icons.landslide_outlined,
        'Heavy rain' => Icons.water_drop_outlined,
        'Snow or ice' => Icons.ac_unit_rounded,
        'Bridge issue' => Icons.dangerous_outlined,
        'Traffic delay' => Icons.traffic_rounded,
        _ => Icons.block_rounded,
      };

  void _newReport(BuildContext context, AppController controller) {
    final route = TextEditingController(text: 'Muzaffarabad → Keran');
    final details = TextEditingController();
    var type = 'Road blocked';

    showUdSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                context.tr('reportRoadCondition'),
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 16),
              UdTextField(
                controller: route,
                label: context.tr('affectedRoute'),
                icon: Icons.route_rounded,
              ),
              const SizedBox(height: 16),

              // Was a `DropdownButtonFormField` of seven items. Seven chips
              // fit on two lines and every option is readable without
              // opening anything.
              UdLabel(context.tr('roadConditionType')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _types)
                    UdChip(
                      label: option,
                      selected: type == option,
                      icon: type == option ? Icons.check_rounded : null,
                      onTap: () => setSheet(() => type = option),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              UdTextField(
                controller: details,
                label: context.tr('touristAdvice'),
                icon: Icons.notes_rounded,
                minLines: 3,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: context.tr('submitReport'),
                icon: Icons.send_rounded,
                onPressed: () {
                  controller.addRoadReport(RoadReport(
                    id: 'RR-${DateTime.now().millisecondsSinceEpoch}',
                    route: route.text.trim(),
                    type: type,
                    details: details.text.trim().isEmpty
                        ? 'Submitted by verified driver for operations review.'
                        : details.text.trim(),
                    reportedAt: 'Just now',
                  ));
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
