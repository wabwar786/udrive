import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';

class PackageBookingsScreen extends StatelessWidget {
  const PackageBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        Row(
          children: [
            MetricTile(icon: Icons.confirmation_number_rounded, label: context.tr('totalBookings'), value: '${controller.packageBookings.length}', color: AppColors.primary),
            const SizedBox(width: 10),
            MetricTile(icon: Icons.event_seat_rounded, label: context.tr('seatsBooked'), value: '5', color: AppColors.secondary),
          ],
        ),
        const SizedBox(height: 18),
        ...controller.packageBookings.map(
          (booking) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusPill(label: booking.status, color: _statusColor(booking.status)),
                      const Spacer(),
                      Text(booking.travelDate, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(booking.packageTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.person_rounded, size: 18, color: AppColors.muted), const SizedBox(width: 6), Expanded(child: Text('${booking.customer} · ${booking.phone}', style: const TextStyle(color: AppColors.muted, fontSize: 12)))]),
                  const SizedBox(height: 8),
                  Row(children: [Icon(booking.bookingType == BookingType.perSeat ? Icons.event_seat_rounded : Icons.directions_car_filled_rounded, size: 18, color: AppColors.primaryDark), const SizedBox(width: 6), Text(booking.bookingType == BookingType.perSeat ? '${booking.seats} ${context.tr('seats')}' : context.tr('wholeVehicle'), style: const TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('PKR ${booking.total}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
                  if (booking.status == 'Pending confirmation') ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => controller.updatePackageBooking(booking.id, 'Changes requested'), child: Text(context.tr('requestDetails')))),
                        const SizedBox(width: 9),
                        Expanded(child: FilledButton(onPressed: () => controller.updatePackageBooking(booking.id, 'Confirmed'), child: Text(context.tr('confirmBooking')))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    if (status == 'Confirmed') return AppColors.success;
    if (status == 'Changes requested') return AppColors.warning;
    return AppColors.info;
  }
}

class VehicleSuitabilityScreen extends StatelessWidget {
  const VehicleSuitabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        PremiumCard(
          color: const Color(0xFFF1FAF6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.terrain_rounded, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('vehicleSuitabilityHelp'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...controller.vehicles.map(
          (vehicle) => Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark)),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${vehicle.make} ${vehicle.model}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text('${vehicle.registration} · ${vehicle.category}', style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
                      StatusPill(label: '${vehicle.readinessScore}% ${context.tr('ready')}', color: vehicle.readinessScore >= 80 ? AppColors.success : AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 13),
                  LinearProgressIndicator(value: vehicle.readinessScore / 100, minHeight: 8, borderRadius: BorderRadius.circular(20)),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _Capability(label: context.tr('city'), enabled: true),
                      _Capability(label: context.tr('intercity'), enabled: true),
                      _Capability(label: context.tr('familyTours'), enabled: vehicle.childSeat || vehicle.seats >= 5),
                      _Capability(label: context.tr('mountainRoads'), enabled: vehicle.mountainReady),
                      _Capability(label: context.tr('snowRoutes'), enabled: vehicle.fourWheelDrive && vehicle.snowChains),
                      _Capability(label: context.tr('fourByFourRoutes'), enabled: vehicle.fourWheelDrive),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Text(vehicle.mountainReady ? context.tr('mountainReadyMessage') : context.tr('mountainEquipmentMessage'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.enabled});
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: (enabled ? AppColors.success : AppColors.muted).withValues(alpha: .11), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded, size: 15, color: enabled ? AppColors.success : AppColors.muted), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: enabled ? AppColors.success : AppColors.muted))]),
      );
}

class DriverRoadReportsScreen extends StatelessWidget {
  const DriverRoadReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        FilledButton.icon(onPressed: () => _newReport(context, controller), icon: const Icon(Icons.add_road_rounded), label: Text(context.tr('reportRoadCondition'))),
        const SizedBox(height: 14),
        PremiumCard(
          color: const Color(0xFFFFF9E9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.fact_check_rounded, color: AppColors.warning), const SizedBox(width: 10), Expanded(child: Text(context.tr('driverReportNotice'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)))]),
        ),
        const SizedBox(height: 14),
        ...controller.roadReports.map(
          (report) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: PremiumCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning)),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(report.route, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('${report.type} · ${report.details}', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                        const SizedBox(height: 8),
                        Row(children: [StatusPill(label: report.status, color: report.status.startsWith('Verified') ? AppColors.success : AppColors.warning), const Spacer(), Text(report.reportedAt, style: const TextStyle(color: AppColors.muted, fontSize: 10))]),
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

  void _newReport(BuildContext context, AppController controller) {
    final route = TextEditingController(text: 'Muzaffarabad → Keran');
    final details = TextEditingController();
    var type = 'Road blocked';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('reportRoadCondition'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: route, decoration: InputDecoration(labelText: context.tr('affectedRoute'))),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(value: type, decoration: InputDecoration(labelText: context.tr('roadConditionType')), items: const ['Road blocked', 'Landslide risk', 'Heavy rain', 'Snow or ice', 'Bridge issue', 'Traffic delay', 'Road open'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => type = value!)),
              const SizedBox(height: 10),
              TextField(controller: details, maxLines: 3, decoration: InputDecoration(labelText: context.tr('touristAdvice'))),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  controller.addRoadReport(RoadReport(id: 'RR-${DateTime.now().millisecondsSinceEpoch}', route: route.text.trim(), type: type, details: details.text.trim().isEmpty ? 'Submitted by verified driver for operations review.' : details.text.trim(), reportedAt: 'Just now'));
                  Navigator.pop(sheetContext);
                },
                child: Text(context.tr('submitReport')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
