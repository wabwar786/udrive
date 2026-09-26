import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import 'driver_documents_screen.dart';
import 'onboarding/live_vehicle_registration_screen.dart';
import 'tour_rate_screen.dart';

/// D-44 — the vehicles on this driver's account.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class LiveVehicleListScreen extends StatefulWidget {
  const LiveVehicleListScreen({super.key});

  @override
  State<LiveVehicleListScreen> createState() => _LiveVehicleListScreenState();
}

class _LiveVehicleListScreenState extends State<LiveVehicleListScreen> {
  Future<void> _refresh() => AppControllerScope.of(context).refreshAccount();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final vehicles = controller.liveVehicles;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          Text(
            _t('Vehicles', 'گاڑیاں'),
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 20),

          UdButton.primary(
            label: _t('Register vehicle', 'گاڑی رجسٹر کریں'),
            icon: Icons.add_rounded,
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LiveVehicleRegistrationScreen()));
              if (mounted) await _refresh();
            },
          ),
          const SizedBox(height: 10),
          // Tour pricing lives beside the vehicles rather than in settings,
          // because it is a fact about a vehicle. It is also editable after
          // verification, unlike the rest of the vehicle record — a price is
          // commercial, not compliance.
          UdButton.outline(
            label: _t('Set your tour rate', 'اپنا ٹور کرایہ مقرر کریں'),
            icon: Icons.sell_outlined,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TourRateScreen()),
            ),
          ),
          const SizedBox(height: 10),
          // Personal documents sit beside the vehicles because a Driver
          // thinks of both as "my paperwork". Splitting them across two areas
          // of the app is why people ask support where their licence went.
          UdButton.outline(
            label: _t('My documents', 'میرے کاغذات'),
            icon: Icons.badge_outlined,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverDocumentsScreen()),
            ),
          ),
          const SizedBox(height: 26),

          UdSectionHeader(
            title: _t('Your vehicles', 'آپ کی گاڑیاں'),
            caption: vehicles.isEmpty ? null : '${vehicles.length}',
          ),
          const SizedBox(height: 12),
          if (vehicles.isEmpty)
            UdEmptyState(
              icon: Icons.directions_car_outlined,
              title: _t('No vehicle yet', 'ابھی کوئی گاڑی نہیں'),
              text: _t(
                  'Register a vehicle and submit its documents for '
                      'verification.',
                  'گاڑی رجسٹر کریں اور دستاویزات تصدیق کے لیے جمع کریں۔'),
            )
          else
            ...vehicles.map(
              (vehicle) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VehicleCard(vehicle: vehicle),
              ),
            ),
        ],
      ),
    );
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

/// One vehicle: its photograph if there is one, what it is, and its four
/// facts.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});
  final LiveVehicle vehicle;

  static UdTone _tone(String status) => switch (status) {
        'Verified' || 'Approved' => UdTone.ok,
        'Rejected' || 'Suspended' => UdTone.err,
        _ => UdTone.warn,
      };

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        vehicle.imageUrl != null && vehicle.imageUrl!.isNotEmpty;

    return UdCard(
      padding: hasPhoto ? EdgeInsets.zero : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPhoto)
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadii.card)),
              child: Image.network(
                vehicle.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: hasPhoto ? const EdgeInsets.all(16) : EdgeInsets.zero,
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
                            '${vehicle.make} ${vehicle.model} ${vehicle.year}',
                            style:
                                AppType.h3.copyWith(color: AppText.primary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${vehicle.registrationNumber} · '
                            '${vehicle.category} · ${vehicle.colour}',
                            style: AppType.small
                                .copyWith(color: AppText.secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    UdBadge(
                      label: vehicle.status,
                      tone: _tone(vehicle.status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _Fact(
                      icon: Icons.people_alt_rounded,
                      label: '${vehicle.passengerCapacity} seats',
                    ),
                    _Fact(
                      icon: Icons.luggage_rounded,
                      label: '${vehicle.luggageCapacity} bags',
                    ),
                    _Fact(
                      icon: Icons.terrain_rounded,
                      label: '${vehicle.mountainReadinessScore}/100',
                    ),
                    _Fact(
                      icon: Icons.description_rounded,
                      label: '${vehicle.documents.length} documents',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppText.caption),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
        ],
      );
}
