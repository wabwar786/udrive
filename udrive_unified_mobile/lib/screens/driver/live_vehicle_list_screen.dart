import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/auth_models.dart';
import 'driver_documents_screen.dart';
import 'onboarding/live_vehicle_registration_screen.dart';
import 'tour_rate_screen.dart';

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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          FilledButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveVehicleRegistrationScreen()));
              if (mounted) await _refresh();
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(_t('Register vehicle', 'گاڑی رجسٹر کریں')),
          ),
          const SizedBox(height: 10),
          // Tour pricing lives beside the vehicles rather than in settings,
          // because it is a fact about a vehicle. It is also editable after
          // verification, unlike the rest of the vehicle record — a price is
          // commercial, not compliance.
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TourRateScreen()),
            ),
            icon: const Icon(Icons.sell_outlined),
            label: Text(_t('Set your tour rate', 'اپنا ٹور کرایہ مقرر کریں')),
          ),
          const SizedBox(height: 10),
          // Personal documents sit beside the vehicles because a Driver
          // thinks of both as "my paperwork". Splitting them across two areas
          // of the app is why people ask support where their licence went.
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverDocumentsScreen()),
            ),
            icon: const Icon(Icons.badge_outlined),
            label: Text(_t('My documents', 'میرے کاغذات')),
          ),
          const SizedBox(height: 16),
          if (vehicles.isEmpty)
            _Empty(message: _t('No vehicle exists in your account. Register a vehicle and submit its documents for verification.', 'آپ کے اکاؤنٹ میں کوئی گاڑی موجود نہیں۔ گاڑی رجسٹر کریں اور دستاویزات تصدیق کے لیے جمع کریں۔'))
          else
            ...vehicles.map((vehicle) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _VehicleCard(vehicle: vehicle))),
        ],
      ),
    );
  }

  String _t(String en, String ur) => AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});
  final LiveVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final verified = vehicle.status == 'Verified';
    return PremiumCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (vehicle.imageUrl != null && vehicle.imageUrl!.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(vehicle.imageUrl!, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 12),
        ],
        Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${vehicle.make} ${vehicle.model} ${vehicle.year}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 3), Text('${vehicle.registrationNumber} · ${vehicle.category} · ${vehicle.colour}', style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
          StatusPill(label: vehicle.status, color: verified ? AppColors.success : AppColors.warning),
        ]),
        const Divider(height: 24),
        Wrap(spacing: 14, runSpacing: 8, children: [
          _Fact(icon: Icons.people_alt_rounded, label: '${vehicle.passengerCapacity} seats'),
          _Fact(icon: Icons.luggage_rounded, label: '${vehicle.luggageCapacity} bags'),
          _Fact(icon: Icons.terrain_rounded, label: '${vehicle.mountainReadinessScore}/100 readiness'),
          _Fact(icon: Icons.description_rounded, label: '${vehicle.documents.length} documents'),
        ]),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});
  final IconData icon; final String label;
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: AppColors.primaryDark), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message}); final String message;
  @override Widget build(BuildContext context) => PremiumCard(child: Column(children: [const Icon(Icons.directions_car_outlined, size: 54, color: AppColors.muted), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4))]));
}
