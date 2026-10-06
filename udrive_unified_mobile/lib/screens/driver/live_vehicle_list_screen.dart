import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/vehicles/vehicle_usage_repository.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import 'driver_documents_screen.dart';
import 'driver_rentals_screen.dart';
import 'live_vehicle_usage_screen.dart';
import 'onboarding/live_vehicle_registration_screen.dart';
import 'onboarding/vehicle_register_choice_screen.dart';
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
  /// What each vehicle is used for, keyed by vehicle id.
  ///
  /// Loaded alongside the vehicles rather than folded into them: a Driver
  /// opening this list wants to see at a glance which car is on what, and
  /// before this there was nowhere in the app that said.
  Map<String, VehicleUsage> _usage = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsage());
  }

  Future<void> _loadUsage() async {
    try {
      final list =
          await VehicleUsageRepository(AppControllerScope.of(context).apiClient)
              .list();
      if (!mounted) return;
      setState(() {
        _usage = {for (final vehicle in list) vehicle.vehicleId: vehicle};
      });
    } catch (_) {
      // The pills are a convenience. Losing them must not cost the Driver the
      // list of their own vehicles.
    }
  }

  Future<void> _refresh() async {
    await AppControllerScope.of(context).refreshAccount();
    await _loadUsage();
  }

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
                      builder: (_) => VehicleRegisterChoiceScreen(
                            ridesScreen: (choice) =>
                                LiveVehicleRegistrationScreen(choice: choice),
                          )));
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
          // Rentals sit here rather than under bookings, because a rental is a
          // fact about a vehicle: one of these cars is in somebody else's
          // driveway for a week, and this is the list of cars.
          UdButton.outline(
            label: _t('Rentals', 'کرائے'),
            icon: Icons.vpn_key_outlined,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverRentalsScreen()),
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
                child: _VehicleCard(
                  vehicle: vehicle,
                  usage: _usage[vehicle.id],
                  onOpenUsage: () => _openUsage(vehicle.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openUsage(String vehicleId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveVehicleUsageScreen(vehicleId: vehicleId),
      ),
    );
    if (mounted) await _loadUsage();
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

/// One vehicle: its photograph if there is one, what it is, and its four
/// facts.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.usage,
    required this.onOpenUsage,
  });

  final LiveVehicle vehicle;

  /// Null until the usage request lands, or if it failed.
  final VehicleUsage? usage;

  final VoidCallback onOpenUsage;

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
                cacheWidth: 900,
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
                      icon: Icons.description_rounded,
                      label: '${vehicle.documents.length} documents',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _TourReadiness(vehicle: vehicle),

                // What the vehicle is actually for. Three pills, because one
                // glance should answer "which car is on what" — a question the
                // app could not answer anywhere before this.
                if (usage != null && usage!.isVerified) ...[
                  const SizedBox(height: 12),
                  UdListGroup(
                    children: [
                      UdListRow(
                        title: 'What this vehicle is for',
                        subtitle: _usageSentence(usage!),
                        onTap: onOpenUsage,
                        showChevron: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _UsagePill(label: 'CITY', on: usage!.availableForCity),
                      _UsagePill(label: 'TOUR', on: usage!.availableForTour),
                      _UsagePill(label: 'RENT', on: usage!.availableForRent),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _usageSentence(VehicleUsage usage) {
    final on = <String>[
      if (usage.availableForCity) 'city rides',
      if (usage.availableForTour) 'tours',
      if (usage.availableForRent) 'rent',
    ];
    if (on.isEmpty) return 'Nothing switched on — no work will come';
    if (on.length == 1) return 'On ${on.first}';
    return 'On ${on.sublist(0, on.length - 1).join(', ')} and ${on.last}';
  }
}

/// One of the three usages, on or off.
class _UsagePill extends StatelessWidget {
  const _UsagePill({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.brandWash : AppColors.surfaceAlt,
          borderRadius: AppRadii.all(999),
          border: Border.all(
            color: on ? AppTint.successBorder : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppType.caption.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: on ? AppColors.brandInk : AppText.caption,
          ),
        ),
      );
}

/// Whether this vehicle may carry a tour, and what is missing if not.
///
/// The score was already on this card, as "45/100" beside the seat count — a
/// number with no scale and no consequence. It is the number that decides
/// whether a Driver can publish a tour package at all, and the only place it
/// was ever explained was the refusal they got on pressing Save, which named
/// neither the score nor the target nor anything to do about it.
///
/// Both gates are shown, because either one alone blocks the package and a
/// Driver who passed one and failed the other had no way to tell which.
class _TourReadiness extends StatelessWidget {
  const _TourReadiness({required this.vehicle});

  final LiveVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final score = vehicle.mountainReadinessScore;
    final required = vehicle.tourReadinessRequired;
    final ready = vehicle.meetsTourReadiness;
    final missing = vehicle.tourReadinessMissing;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: vehicle.canCarryTour ? AppColors.brandWash : AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.tile),
        border: Border.all(
          color: vehicle.canCarryTour ? AppTint.successBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Tour readiness',
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.secondary,
                  ),
                ),
              ),
              Text(
                '$score',
                style: AppType.h2.copyWith(
                  height: 1,
                  color: ready ? AppColors.brandInk : AppText.primary,
                ),
              ),
              Text(
                ' / $required needed',
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppText.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // The bar is drawn against 100, with a mark where the requirement
          // sits — so the gap is a distance the Driver can see rather than a
          // subtraction they have to do.
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: AppRadii.all(999),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (score / 100).clamp(0.0, 1.0),
                      child: Container(
                        height: 9,
                        decoration: BoxDecoration(
                          color: ready ? AppColors.brand : AppTint.warningText,
                          borderRadius: AppRadii.all(999),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: constraints.maxWidth * (required / 100).clamp(0.0, 1.0),
                    top: 0,
                    child: Container(
                      width: 2,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: AppRadii.all(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          if (!ready && missing.isNotEmpty)
            Text(
              'Add ${_sentence(missing.map((item) => item.label.toLowerCase()))} '
              'to reach $required.',
              style: AppType.small.copyWith(
                height: 1.45,
                color: AppTint.warningText,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (!ready)
            Text(
              'This vehicle cannot reach $required with the equipment UDrive '
              'scores. A different vehicle would be needed for tours.',
              style: AppType.small.copyWith(
                height: 1.45,
                color: AppTint.warningText,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (!vehicle.availableForTour)
            Text(
              'Score is enough, but "Available for tour" is off for this '
              'vehicle — turn it on under Tour rates before creating a package.',
              style: AppType.small.copyWith(
                height: 1.45,
                color: AppTint.warningText,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              'Ready for tour packages.',
              style: AppType.small.copyWith(
                height: 1.45,
                color: AppColors.brandInk,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  /// "a first-aid kit, a spare tyre and snow chains" — a list a person reads,
  /// not three bullet points for three objects.
  static String _sentence(Iterable<String> parts) {
    final list = parts.toList();
    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
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
