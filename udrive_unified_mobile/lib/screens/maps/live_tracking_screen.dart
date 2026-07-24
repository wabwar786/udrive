import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/services/map_config.dart';
import '../../core/services/simulated_location_service.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  StreamSubscription<SimulatedLocationPoint>? _locationSubscription;
  bool _autoMove = false;
  final SimulatedLocationService _locationService = const SimulatedLocationService();

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _toggleMovement(AppController controller) {
    setState(() => _autoMove = !_autoMove);
    _locationSubscription?.cancel();
    if (_autoMove) {
      _locationSubscription = _locationService.watchTrip().listen(
        (point) {
          controller.applySimulatedLocation(
            label: point.label,
            progress: point.progress,
            etaMinutes: point.etaMinutes,
          );
        },
        onDone: () {
          if (mounted) setState(() => _autoMove = false);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final trip = controller.liveTrip;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        if (!MapConfig.hasLiveConfiguration)
          PremiumCard(
            color: const Color(0xFFEAF4FF),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.map_rounded, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('googleMapsDemo'),
                    style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _AnimatedRouteMap(progress: trip.progress, routeDeviation: trip.routeDeviation),
        const SizedBox(height: 14),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(
                    label: trip.progress >= 1 ? context.tr('arrived') : context.tr('tripInProgress'),
                    color: trip.progress >= 1 ? AppColors.success : AppColors.info,
                  ),
                  const Spacer(),
                  Text('${trip.etaMinutes} ${context.tr('minutesEta')}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 14),
              Text(trip.currentLocation, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(trip.route, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: trip.progress, minHeight: 8, borderRadius: BorderRadius.circular(20)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text('${trip.driver} · ${trip.vehicle}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Text(trip.registration, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _toggleMovement(controller),
                icon: Icon(_autoMove ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(_autoMove ? context.tr('pauseDemo') : context.tr('moveVehicle')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _shareSheet(context, controller),
                icon: const Icon(Icons.share_location_rounded),
                label: Text(context.tr('shareTrip')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PremiumCard(
          color: trip.routeDeviation ? const Color(0xFFFFF0F0) : null,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: trip.routeDeviation,
            onChanged: controller.setRouteDeviation,
            secondary: Icon(Icons.alt_route_rounded, color: trip.routeDeviation ? AppColors.danger : AppColors.primaryDark),
            title: Text(context.tr('routeDeviationSimulation'), style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(
              trip.routeDeviation
                  ? context.tr('routeDeviationCreated')
                  : context.tr('routeDeviationHelp'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('liveTripControls'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _ActionRow(icon: Icons.call_rounded, label: context.tr('callDriver'), value: '+92 300 901 2204', onTap: () => _notice(context, 'Dummy driver call opened.')),
              _ActionRow(icon: Icons.chat_rounded, label: context.tr('messageDriver'), value: 'Open secure chat', onTap: () => _notice(context, 'Secure trip chat opened.')),
              _ActionRow(icon: Icons.support_agent_rounded, label: context.tr('contactSafety'), value: '24/7 demo support', onTap: () => _notice(context, 'Safety support ticket created.')),
            ],
          ),
        ),
      ],
    );
  }

  void _shareSheet(BuildContext context, AppController controller) {
    var duration = controller.shareDuration;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('shareLiveLocation'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(context.tr('sharePrivacyHelp'), style: TextStyle(color: AppColors.muted, height: 1.4)),
              const SizedBox(height: 14),
              SegmentedButton<ShareDuration>(
                segments: [
                  ButtonSegment(value: ShareDuration.oneHour, label: Text(context.tr('oneHour'))),
                  ButtonSegment(value: ShareDuration.untilDestination, label: Text(context.tr('untilArrival'))),
                  ButtonSegment(value: ShareDuration.completeTrip, label: Text(context.tr('fullTrip'))),
                ],
                selected: {duration},
                onSelectionChanged: (value) => setModalState(() => duration = value.first),
              ),
              const SizedBox(height: 14),
              PremiumCard(
                color: const Color(0xFFF1FAF6),
                child: SelectableText(controller.buildShareLink(), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await controller.setLiveSharing(true, duration);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) _notice(context, 'Tracking link copied and shared with your Tour Guardian.');
                },
                icon: const Icon(Icons.share_rounded),
                label: Text(context.tr('shareTrackingLink')),
              ),
              if (controller.liveTrip.shareEnabled)
                TextButton(
                  onPressed: () async {
                    await controller.setLiveSharing(false, duration);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: Text(context.tr('stopLiveSharing')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedRouteMap extends StatelessWidget {
  const _AnimatedRouteMap({required this.progress, required this.routeDeviation});
  final double progress;
  final bool routeDeviation;

  @override
  Widget build(BuildContext context) => Container(
        height: 290,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(colors: [Color(0xFFE8F5EF), Color(0xFFE5EEF6)]),
          border: Border.all(color: AppColors.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final x = 30 + (constraints.maxWidth - 90) * progress;
            final y = constraints.maxHeight * (.72 - .42 * progress) + (routeDeviation ? 32 : 0);
            return Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _LiveRoutePainter(routeDeviation: routeDeviation))),
                const Positioned(left: 20, bottom: 38, child: _MapBadge(icon: Icons.trip_origin_rounded, label: 'Ghari Pan')),
                const Positioned(right: 18, top: 28, child: _MapBadge(icon: Icons.location_on_rounded, label: 'Keran')),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  left: x,
                  top: y,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: routeDeviation ? AppColors.danger : AppColors.navy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .2), blurRadius: 18)],
                    ),
                    child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(15)),
                    child: Row(
                      children: [
                        Icon(routeDeviation ? Icons.warning_amber_rounded : Icons.gps_fixed_rounded, size: 18, color: routeDeviation ? AppColors.danger : AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(routeDeviation ? context.tr('routeDeviationDetected') : 'Live GPS simulation · API-ready', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _LiveRoutePainter extends CustomPainter {
  const _LiveRoutePainter({required this.routeDeviation});
  final bool routeDeviation;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .55)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (.12 + i * .14);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 18), grid);
    }
    final route = Paint()
      ..color = routeDeviation ? AppColors.danger : AppColors.primary
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final routePath = Path()
      ..moveTo(32, size.height * .76)
      ..cubicTo(size.width * .25, size.height * .6, size.width * .54, size.height * .52, size.width * .83, size.height * .22);
    canvas.drawPath(routePath, route);
    if (routeDeviation) {
      final deviation = Paint()
        ..color = AppColors.danger.withValues(alpha: .5)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke;
      final deviationPath = Path()
        ..moveTo(size.width * .45, size.height * .54)
        ..quadraticBezierTo(size.width * .56, size.height * .82, size.width * .68, size.height * .62);
      canvas.drawPath(deviationPath, deviation);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveRoutePainter oldDelegate) => oldDelegate.routeDeviation != routeDeviation;
}

class _MapBadge extends StatelessWidget {
  const _MapBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .1), blurRadius: 14)]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: AppColors.primaryDark), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]),
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: AppColors.primary.withValues(alpha: .1), child: Icon(icon, color: AppColors.primaryDark)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(value),
        trailing: const Icon(Icons.chevron_right_rounded),
      );
}

void _notice(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
