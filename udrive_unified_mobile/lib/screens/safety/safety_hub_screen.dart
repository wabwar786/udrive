import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';
import '../maps/live_tracking_screen.dart';

class SafetyHubScreen extends StatelessWidget {
  const SafetyHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Color(0xFF861B27), AppColors.danger]),
          ),
          child: Column(
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 54),
              const SizedBox(height: 10),
              Text(context.tr('emergency'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 23)),
              const SizedBox(height: 6),
              Text(
                context.tr('emergencyShareHelp'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _activateSos(context, controller),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.danger),
                icon: const Icon(Icons.warning_amber_rounded),
                label: Text(context.tr('activateEmergencySos')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            MetricTile(icon: Icons.shield_rounded, label: 'Route safety', value: '86/100', color: AppColors.success),
            const SizedBox(width: 10),
            MetricTile(icon: Icons.people_alt_rounded, label: 'Trusted contacts', value: '${controller.trustedContacts.length}', color: AppColors.secondary),
          ],
        ),
        const SizedBox(height: 18),
        _SafetyFeature(
          icon: Icons.share_location_rounded,
          title: context.tr('liveLocationSharing'),
          subtitle: controller.liveTrip.shareEnabled ? 'Sharing is active with your Tour Guardian' : 'Share route, driver, ETA and live position',
          color: AppColors.primary,
          onTap: () => _open(context, const LiveTrackingScreen(), 'Live trip tracking'),
        ),
        _SafetyFeature(
          icon: Icons.admin_panel_settings_rounded,
          title: context.tr('tourGuardian'),
          subtitle: controller.guardian == null ? 'Choose a guardian for this trip' : '${controller.guardian!.name} is monitoring your trip',
          color: AppColors.secondary,
          onTap: () => _open(context, const TourGuardianScreen(), context.tr('tourGuardian')),
        ),
        _SafetyFeature(
          icon: Icons.people_alt_rounded,
          title: context.tr('trustedContacts'),
          subtitle: 'Manage family and emergency contacts',
          color: const Color(0xFF7C3AED),
          onTap: () => _open(context, const TrustedContactsScreen(), context.tr('trustedContacts')),
        ),
        _SafetyFeature(
          icon: Icons.health_and_safety_rounded,
          title: context.tr('safetyCheckIns'),
          subtitle: 'Scheduled comfort and emergency confirmations',
          color: AppColors.warning,
          onTap: () => _open(context, const SafetyCheckInScreen(), context.tr('safetyCheckIns')),
        ),
        _SafetyFeature(
          icon: Icons.download_for_offline_rounded,
          title: context.tr('offlineTravelCard'),
          subtitle: 'Booking, OTP, emergency and hotel details without internet',
          color: AppColors.info,
          onTap: () => _open(context, const OfflineTravelCardScreen(), context.tr('offlineTravelCard')),
        ),
        _SafetyFeature(
          icon: Icons.report_problem_rounded,
          title: context.tr('reportIssue'),
          subtitle: 'Create a safety incident for operations review',
          color: AppColors.danger,
          onTap: () => _reportIssue(context, controller),
        ),
        if (controller.incidents.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionHeader(title: context.tr('recentSafetyIncidents')),
          const SizedBox(height: 8),
          ...controller.incidents.take(3).map(
                (incident) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PremiumCard(
                    color: const Color(0xFFFFF5F5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(incident.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(incident.details, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                              const SizedBox(height: 7),
                              StatusPill(label: incident.status.name, color: incident.status == IncidentStatus.resolved ? AppColors.success : AppColors.danger),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }

  void _activateSos(BuildContext context, AppController controller) {
    controller.createIncident(
      title: 'Emergency SOS activated',
      details: 'Passenger requested immediate help. Live location and trip details were shared with the Tour Guardian.',
      location: controller.liveTrip.currentLocation,
      severity: 'Critical',
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: AppColors.danger, size: 56),
        title: Text(context.tr('sosActivated')),
        content: Text('Your location at ${controller.liveTrip.currentLocation} has been shared with ${controller.guardian?.name ?? 'your trusted contacts'} and uDrive safety operations.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.tr('understand')))],
      ),
    );
  }

  void _reportIssue(BuildContext context, AppController controller) {
    final details = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('reportSafetyIssue'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(controller: details, maxLines: 4, decoration: InputDecoration(labelText: context.tr('whatHappened'))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                controller.createIncident(
                  title: 'Customer safety report',
                  details: details.text.trim().isEmpty ? 'Safety concern submitted from the mobile app.' : details.text.trim(),
                  location: controller.liveTrip.currentLocation,
                );
                Navigator.pop(sheetContext);
              },
              child: Text(context.tr('submitSecureReport')),
            ),
          ],
        ),
      ),
    );
  }
}

class TrustedContactsScreen extends StatelessWidget {
  const TrustedContactsScreen({super.key});

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
              const Icon(Icons.privacy_tip_rounded, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('trustedPrivacy'), style: const TextStyle(color: AppColors.muted, height: 1.45, fontSize: 12))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...controller.trustedContacts.map(
          (contact) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: PremiumCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: AppColors.primary.withValues(alpha: .11), child: const Icon(Icons.person_rounded, color: AppColors.primaryDark)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text('${contact.relationship} · ${contact.phone}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      if (contact.isGuardian) const StatusPill(label: 'Guardian', color: AppColors.secondary),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => controller.setGuardian(contact.id),
                          child: Text(contact.isGuardian ? context.tr('currentGuardian') : context.tr('setGuardian')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(onPressed: controller.trustedContacts.length > 1 ? () => controller.removeTrustedContact(contact.id) : null, icon: const Icon(Icons.delete_outline_rounded)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        FilledButton.icon(onPressed: () => _addContact(context, controller), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(context.tr('addTrustedContact'))),
      ],
    );
  }

  void _addContact(BuildContext context, AppController controller) {
    final name = TextEditingController();
    final relation = TextEditingController();
    final phone = TextEditingController(text: '+92 ');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('addTrustedContact'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: InputDecoration(labelText: context.tr('fullName'))),
            const SizedBox(height: 10),
            TextField(controller: relation, decoration: InputDecoration(labelText: context.tr('relationship'))),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('mobileWhatsapp'))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || phone.text.trim().length < 8) return;
                controller.addTrustedContact(
                  TrustedContact(
                    id: 'TC-${DateTime.now().millisecondsSinceEpoch}',
                    name: name.text.trim(),
                    relationship: relation.text.trim().isEmpty ? 'Trusted person' : relation.text.trim(),
                    phone: phone.text.trim(),
                    whatsapp: phone.text.trim(),
                  ),
                );
                Navigator.pop(sheetContext);
              },
              child: Text(context.tr('saveTrustedContact')),
            ),
          ],
        ),
      ),
    );
  }
}

class TourGuardianScreen extends StatelessWidget {
  const TourGuardianScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final guardian = controller.guardian;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF073F34), AppColors.primary])),
          child: Column(
            children: [
              const CircleAvatar(radius: 34, backgroundColor: Colors.white, child: Icon(Icons.admin_panel_settings_rounded, size: 38, color: AppColors.primaryDark)),
              const SizedBox(height: 12),
              Text(guardian?.name ?? 'No Guardian selected', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(guardian == null ? 'Select a trusted contact below' : '${guardian.relationship} · ${guardian.phone}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              const StatusPill(label: 'Privacy protected', color: AppColors.accent),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('guardianCanView'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _GuardianPermission(icon: Icons.location_on_rounded, text: context.tr('guardianLiveLocation')),
              _GuardianPermission(icon: Icons.badge_rounded, text: context.tr('guardianDriverVehicle')),
              _GuardianPermission(icon: Icons.route_rounded, text: context.tr('guardianRouteEta')),
              _GuardianPermission(icon: Icons.warning_amber_rounded, text: context.tr('guardianEmergencyAlerts')),
              _GuardianPermission(icon: Icons.task_alt_rounded, text: context.tr('guardianCompletion')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionHeader(title: context.tr('selectTourGuardian')),
        const SizedBox(height: 8),
        ...controller.trustedContacts.map(
          (contact) => RadioListTile<String>(
            value: contact.id,
            groupValue: guardian?.id,
            onChanged: (value) {
              if (value != null) controller.setGuardian(value);
            },
            title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${contact.relationship} · ${contact.phone}'),
            secondary: const Icon(Icons.shield_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: guardian == null ? null : () => controller.setLiveSharing(true, ShareDuration.untilDestination),
          icon: const Icon(Icons.share_location_rounded),
          label: Text(context.tr('startGuardianMonitoring')),
        ),
      ],
    );
  }
}

class _GuardianPermission extends StatelessWidget {
  const _GuardianPermission({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [Icon(icon, size: 19, color: AppColors.primaryDark), const SizedBox(width: 9), Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))]),
      );
}

class SafetyCheckInScreen extends StatelessWidget {
  const SafetyCheckInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        PremiumCard(
          color: const Color(0xFFFFF9E9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.timer_rounded, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('checkInHelp'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...controller.safetyCheckIns.map(
          (checkIn) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(checkIn.prompt, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                      StatusPill(label: _checkInLabel(checkIn.status), color: _checkInColor(checkIn.status)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(checkIn.dueLabel, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (checkIn.status == SafetyCheckInStatus.pending)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(label: Text(context.tr('iAmSafe')), avatar: const Icon(Icons.check_circle_rounded, color: AppColors.success), onPressed: () => controller.respondToCheckIn(checkIn.id, SafetyCheckInStatus.safe)),
                        ActionChip(label: Text(context.tr('needSupport')), avatar: const Icon(Icons.support_agent_rounded, color: AppColors.warning), onPressed: () => controller.respondToCheckIn(checkIn.id, SafetyCheckInStatus.needsSupport)),
                        ActionChip(label: Text(context.tr('unsafe')), avatar: const Icon(Icons.warning_rounded, color: AppColors.danger), onPressed: () => controller.respondToCheckIn(checkIn.id, SafetyCheckInStatus.unsafe)),
                        ActionChip(label: Text(context.tr('medicalHelp')), avatar: const Icon(Icons.local_hospital_rounded, color: AppColors.danger), onPressed: () => controller.respondToCheckIn(checkIn.id, SafetyCheckInStatus.medicalHelp)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _checkInLabel(SafetyCheckInStatus status) => switch (status) {
        SafetyCheckInStatus.pending => 'Pending',
        SafetyCheckInStatus.safe => 'Safe',
        SafetyCheckInStatus.needsSupport => 'Support requested',
        SafetyCheckInStatus.unsafe => 'Unsafe',
        SafetyCheckInStatus.medicalHelp => 'Medical help',
        SafetyCheckInStatus.missed => 'Missed',
      };

  Color _checkInColor(SafetyCheckInStatus status) => switch (status) {
        SafetyCheckInStatus.pending => AppColors.warning,
        SafetyCheckInStatus.safe => AppColors.success,
        SafetyCheckInStatus.needsSupport => AppColors.info,
        SafetyCheckInStatus.unsafe || SafetyCheckInStatus.medicalHelp || SafetyCheckInStatus.missed => AppColors.danger,
      };
}

class OfflineTravelCardScreen extends StatelessWidget {
  const OfflineTravelCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final card = AppControllerScope.of(context).offlineTravelCard;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF073F34), AppColors.primary])),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [const Icon(Icons.download_done_rounded, color: Colors.white), const Spacer(), StatusPill(label: context.tr('savedOffline'), color: AppColors.accent)]),
              const SizedBox(height: 18),
              Text(card.bookingId, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${card.pickup} → ${card.destination}', style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.25)),
              const SizedBox(height: 16),
              Text('${context.tr('tripOtp')}: ${card.tripOtp}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _OfflineSection(
          title: context.tr('driverVehicle'),
          icon: Icons.verified_user_rounded,
          rows: [
            ('Driver', card.driver),
            ('Phone', card.driverPhone),
            ('Vehicle', card.vehicle),
            ('Registration', card.registration),
          ],
        ),
        _OfflineSection(
          title: context.tr('tripInformation'),
          icon: Icons.route_rounded,
          rows: [
            ('Last known location', card.lastKnownLocation),
            ('Hotel', card.hotel),
            ('Itinerary', card.itinerary.join(' → ')),
          ],
        ),
        _OfflineSection(
          title: context.tr('emergencyContacts'),
          icon: Icons.local_hospital_rounded,
          rows: card.emergencyNumbers.map((item) => ('Emergency', item)).toList(),
        ),
        FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline Travel Card refreshed and saved on this device.'))), icon: const Icon(Icons.sync_rounded), label: Text(context.tr('refreshOfflineCard'))),
      ],
    );
  }
}

class _OfflineSection extends StatelessWidget {
  const _OfflineSection({required this.title, required this.icon, required this.rows});
  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(width: 9), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 10),
              ...rows.map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 105, child: Text(row.$1, style: const TextStyle(color: AppColors.muted, fontSize: 11))), Expanded(child: Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))]),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SafetyFeature extends StatelessWidget {
  const _SafetyFeature({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: PremiumCard(
          onTap: onTap,
          child: Row(
            children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35))])),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}

void _open(BuildContext context, Widget page, String title) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: page)));
}
