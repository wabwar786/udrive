import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/areas/area_picker.dart';
import '../../core/areas/area_repository.dart';
import '../../core/listings/listing_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'driver_invite_screen.dart';
import 'listing_departures_screen.dart' show ListingDeparturesScreen;
import 'listing_owner_parts.dart';
import 'listing_rent_screen.dart' show ListingRentScreen;
import 'listing_rent_settings_screen.dart' show ListingRentSettingsScreen;
import 'listing_wizard_screen.dart';
import '../driver/onboarding/live_vehicle_registration_screen.dart';
import '../driver/onboarding/vehicle_register_choice_screen.dart';

/// My vehicles — every vehicle this account has listed, and its drivers.
///
/// Draft and Rejected vehicles open the wizard again; live ones lead to the
/// rent calendar and the tour departures.
class MyVehiclesScreen extends StatefulWidget {
  const MyVehiclesScreen({super.key});

  @override
  State<MyVehiclesScreen> createState() => _MyVehiclesScreenState();
}

class _MyVehiclesScreenState extends State<MyVehiclesScreen> {
  ListingRepository? _repo;
  ListingHome? _home;
  bool _loading = true;
  String? _error;

  /// "vehicleId:purpose" while that use is being sent to UDrive.
  String? _sending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = ListingRepository(AppControllerScope.of(context).apiClient);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  static String _message(Object error) =>
      '$error'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      if (_home == null) _loading = true;
      _error = null;
    });
    try {
      final home = await repo.home();
      if (!mounted) return;
      setState(() {
        _home = home;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) await _load();
  }

  Future<void> _addLocation(ListingVehicle vehicle) async {
    final repo = _repo;
    if (repo == null) return;
    final saved = await showUdSheet<bool>(
      context: context,
      builder: (_) => _LocationSheet(repository: repo, vehicle: vehicle),
    );
    if (saved == true && mounted) await _load();
  }

  static bool _hasRentRate(ListingVehicle vehicle) =>
      (vehicle.withDriverDaily ?? 0) > 0 || (vehicle.selfDriveDaily ?? 0) > 0;

  /// purpose: `rent` or `tour`.
  Future<void> _submitPurpose(ListingVehicle vehicle, String purpose) async {
    final repo = _repo;
    if (repo == null || _sending != null) return;
    if (purpose == 'rent' && !_hasRentRate(vehicle)) {
      await showUdDialog<void>(
        context: context,
        title: 'Set the daily rate first',
        message: 'Open Rent settings and enter a daily rate, then send it '
            'for rent.',
        actions: [
          Builder(
            builder: (dialogContext) => UdButton.primary(
              label: 'Open Rent settings',
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _open(ListingRentSettingsScreen(vehicle: vehicle));
              },
            ),
          ),
          Builder(
            builder: (dialogContext) => UdButton.outline(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      );
      return;
    }
    setState(() {
      _sending = '${vehicle.id}:$purpose';
      _error = null;
    });
    try {
      await repo.submitPurpose(vehicle.id, purpose);
      if (!mounted) return;
      setState(() => _sending = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent. UDrive will check it soon.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = null;
        _error = _message(error);
      });
    }
  }

  Future<void> _invite() async {
    final repo = _repo;
    if (repo == null) return;
    final driver = await showUdSheet<FleetDriver>(
      context: context,
      builder: (_) => _InviteSheet(repository: repo),
    );
    if (driver == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${driver.name} has been sent a WhatsApp invite.')),
    );
    await _load();
  }

  Future<void> _remove(FleetDriver driver) async {
    final repo = _repo;
    if (repo == null || driver.isOwner) return;
    final confirmed = await showUdDialog<bool>(
      context: context,
      title: 'Remove ${driver.name}?',
      message: 'They will no longer be given your bookings. You can invite '
          'them again later.',
      actions: [
        Builder(
          builder: (dialogContext) => UdButton.dark(
            label: 'Remove driver',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ),
        Builder(
          builder: (dialogContext) => UdButton.outline(
            label: 'Keep',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    try {
      await repo.removeDriver(driver.id);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    String? subtitle;
    if (home != null) {
      final count = home.vehicles.length;
      final live = home.vehicles.where((v) => v.isLive).length;
      subtitle = '$count ${count == 1 ? 'vehicle' : 'vehicles'} · $live live';
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerNavyHeader(
            title: 'My vehicles',
            subtitle: subtitle,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                      children: _content(home),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(ListingHome? home) {
    final error = _error;
    final out = <Widget>[];
    if (error != null) {
      out.addAll([
        UdBanner(
          tone: UdTone.err,
          icon: Icons.error_outline_rounded,
          text: error,
          trailing: UdButton.outline(
            label: 'Retry',
            size: UdButtonSize.small,
            expand: false,
            onPressed: _load,
          ),
        ),
        const SizedBox(height: 10),
      ]);
    }
    if (home == null) return out;

    if (home.invites > 0) {
      out.addAll([
        UdBanner(
          tone: UdTone.info,
          icon: Icons.mail_outline_rounded,
          onTap: () => _open(const DriverInviteScreen()),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppTint.infoText),
          child: Text(
            home.invites == 1
                ? 'You have a driver invite'
                : 'You have ${home.invites} driver invites',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
      ]);
    }

    if (home.vehicles.isEmpty) {
      out.add(
        UdEmptyState(
          icon: Icons.directions_car_rounded,
          tone: UdTone.lime,
          title: 'Earn with your vehicle',
          text: 'Rent it out or run tours. List it in 3 quick steps — UDrive '
              'checks it once, then it goes live.',
          action: UdButton.primary(
            label: 'List your vehicle',
            icon: Icons.add_rounded,
            onPressed: () => _open(_registerChoice()),
          ),
        ),
      );
      return out;
    }

    for (final vehicle in home.vehicles.where((v) => v.inReview)) {
      out.addAll([
        _ReviewBanner(vehicle: vehicle),
        const SizedBox(height: 10),
      ]);
    }

    for (final vehicle in home.vehicles) {
      out.addAll([
        _VehicleCard(
          vehicle: vehicle,
          onEdit: vehicle.status == 'Draft' || vehicle.status == 'Rejected'
              ? () => _open(ListingWizardScreen(existing: vehicle))
              : null,
          onRent: vehicle.isLive &&
                  _VehicleCard._shownLive(vehicle.wantsRent, vehicle.rentReview)
              ? () => _open(
                  ListingRentScreen(vehicle: vehicle, drivers: home.drivers))
              : null,
          onDepartures: vehicle.isLive &&
                  _VehicleCard._shownLive(vehicle.wantsTour, vehicle.tourReview)
              ? () => _open(ListingDeparturesScreen(
                  vehicle: vehicle, drivers: home.drivers))
              : null,
          onAddLocation: () => _addLocation(vehicle),
          onSubmitPurpose: _sending == null
              ? (purpose) => _submitPurpose(vehicle, purpose)
              : null,
          sending: _sending != null &&
                  _sending!.startsWith('${vehicle.id}:')
              ? _sending!.substring(vehicle.id.length + 1)
              : null,
        ),
        const SizedBox(height: 10),
      ]);
    }

    out.addAll([
      _DriversCard(
        drivers: home.drivers,
        onInvite: _invite,
        onRemove: _remove,
      ),
      const SizedBox(height: 14),
      _AddVehicleButton(onTap: () => _open(_registerChoice())),
      if (home.owner.identityDone) ...[
        const SizedBox(height: 8),
        Text(
          'Next vehicle: 2 steps — your CNIC is already on file.',
          textAlign: TextAlign.center,
          style: AppType.small.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppText.secondary,
          ),
        ),
      ],
    ]);
    return out;
  }
}

/// Every new vehicle is first asked what it is for (Driver mode). City rides
/// / city to city go to the driver's vehicle form; tours and rent to the
/// three-step form below.
Widget _registerChoice() => VehicleRegisterChoiceScreen(
      ridesScreen: (choice) => LiveVehicleRegistrationScreen(choice: choice),
    );

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.vehicle});

  final ListingVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final name = [
      vehicle.name.isEmpty ? '${vehicle.make} ${vehicle.model}' : vehicle.name,
      if (vehicle.year > 0) '${vehicle.year}',
    ].join(' ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTint.warning,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppTint.warningBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadii.all(12),
            ),
            child: const Icon(Icons.schedule_rounded,
                size: 20, color: AppTint.warningText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name is in review',
                  style: AppType.body2.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTint.warningText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Usually within 24 hours. It goes live by itself once '
                  'approved.',
                  style: AppType.small.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTint.warningText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.onEdit,
    required this.onRent,
    required this.onDepartures,
    required this.onAddLocation,
    required this.onSubmitPurpose,
    required this.sending,
  });

  final ListingVehicle vehicle;
  final VoidCallback? onEdit;
  final VoidCallback? onRent;
  final VoidCallback? onDepartures;
  final VoidCallback onAddLocation;

  /// `rent` or `tour`. Null while another use is being sent.
  final ValueChanged<String>? onSubmitPurpose;

  /// The use being sent for this vehicle right now, if any.
  final String? sending;

  /// A use that is live or was never reviewed separately shows as before.
  static bool _shownLive(bool wants, PurposeReview review) =>
      wants && (review.status == 'Approved' || review.status == 'None');

  @override
  Widget build(BuildContext context) {
    final title = [
      vehicle.name.isEmpty ? '${vehicle.make} ${vehicle.model}' : vehicle.name,
      if (vehicle.year > 0) '${vehicle.year}',
    ].join(' ');
    final photo = vehicle.photoUrl;
    final fallback = Container(
      width: 84,
      height: 64,
      color: AppColors.surfaceAlt,
      child: const Icon(Icons.directions_car_rounded,
          color: AppText.caption, size: 28),
    );

    final rent = vehicle.rentReview;
    final tour = vehicle.tourReview;
    final tags = <Widget>[];
    if (vehicle.isLive) {
      if (_shownLive(vehicle.wantsRent, rent)) {
        tags.add(OwnerTag(
          label: vehicle.availableForRent ? 'Rent · live' : 'Rent · off',
          tone: vehicle.availableForRent ? OwnerTagTone.ok : OwnerTagTone.gray,
        ));
      } else if (rent.status == 'Pending') {
        tags.add(const OwnerTag(
          label: 'Rent · Waiting for UDrive',
          tone: OwnerTagTone.warn,
        ));
      }
      if (_shownLive(vehicle.wantsTour, tour)) {
        tags.add(OwnerTag(
          label: vehicle.availableForTour ? 'Tour · live' : 'Tour · off',
          tone: vehicle.availableForTour ? OwnerTagTone.ok : OwnerTagTone.gray,
        ));
      } else if (tour.status == 'Pending') {
        tags.add(const OwnerTag(
          label: 'Tour · Waiting for UDrive',
          tone: OwnerTagTone.warn,
        ));
      }
    } else {
      tags.add(switch (vehicle.status) {
        'PendingReview' =>
          const OwnerTag(label: 'In review', tone: OwnerTagTone.warn),
        'Rejected' => const OwnerTag(label: 'Rejected', tone: OwnerTagTone.err),
        _ => const OwnerTag(label: 'Draft', tone: OwnerTagTone.gray),
      });
    }

    final actions = <Widget>[
      if (onRent != null)
        Expanded(
          child: _ActionButton(
            label: 'Rent',
            icon: Icons.event_available_rounded,
            badge: vehicle.pendingRentals > 0
                ? '${vehicle.pendingRentals} to confirm'
                : null,
            onTap: onRent!,
          ),
        ),
      if (onRent != null && onDepartures != null) const SizedBox(width: 8),
      if (onDepartures != null)
        Expanded(
          child: _ActionButton(
            label: 'Departures',
            icon: Icons.route_rounded,
            onTap: onDepartures!,
          ),
        ),
    ];

    // UDrive's answer on one use, once the vehicle itself has been sent.
    final reviewed = vehicle.status != 'Draft' && vehicle.status != 'Rejected';
    Widget? purposeNote(String purpose, String label, PurposeReview review) {
      if (!reviewed) return null;
      if (review.status != 'Info' && review.status != 'Rejected') return null;
      final asked = review.status == 'Info';
      final said = review.note ?? '';
      return _PurposeNote(
        text: asked
            ? (said.isEmpty
                ? '$label — UDrive asked for more details.'
                : '$label — UDrive asked: $said')
            : (said.isEmpty
                ? '$label — Not approved.'
                : '$label — Not approved: $said'),
        tone: asked ? OwnerTagTone.warn : OwnerTagTone.err,
        busy: sending == purpose,
        onSendAgain:
            onSubmitPurpose == null ? null : () => onSubmitPurpose!(purpose),
      );
    }

    final purposeNotes = [
      purposeNote('rent', 'Rent', rent),
      purposeNote('tour', 'Tour', tour),
    ].whereType<Widget>().toList();

    final offers = <Widget>[
      if (vehicle.isLive && rent.status == 'None' && !vehicle.wantsRent)
        Expanded(
          child: UdButton.outline(
            label: 'Also offer for rent',
            size: UdButtonSize.small,
            busy: sending == 'rent',
            onPressed: onSubmitPurpose == null
                ? null
                : () => onSubmitPurpose!('rent'),
          ),
        ),
      if (vehicle.isLive && tour.status == 'None' && !vehicle.wantsTour)
        Expanded(
          child: UdButton.outline(
            label: 'Also offer for tours',
            size: UdButtonSize.small,
            busy: sending == 'tour',
            onPressed: onSubmitPurpose == null
                ? null
                : () => onSubmitPurpose!('tour'),
          ),
        ),
    ];

    final location = vehicle.locationLabel;
    final note = vehicle.reviewNote;
    return Opacity(
      opacity: vehicle.inReview ? 0.85 : 1.0,
      child: Material(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        child: InkWell(
          onTap: onEdit,
          borderRadius: AppRadii.all(18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadii.all(12),
                      child: photo == null
                          ? fallback
                          : Image.network(
                              ApiConfig.absoluteUrl(photo),
                              width: 84,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => fallback,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                          Text(
                            '${vehicle.registrationNumber} · '
                            '${vehicle.seats} seats',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.small.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppText.secondary,
                            ),
                          ),
                          if (location != null)
                            Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 14, color: AppText.secondary),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.small.copyWith(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppText.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: tags),
                        ],
                      ),
                    ),
                    if (onEdit != null)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.chevron_right_rounded,
                            color: AppText.caption, size: 24),
                      ),
                  ],
                ),
                if (vehicle.status == 'Rejected' &&
                    note != null &&
                    note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    note,
                    style: AppType.small.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTint.dangerText,
                    ),
                  ),
                ],
                if (location == null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _AddLocationChip(onTap: onAddLocation),
                  ),
                ],
                for (final purposeNote in purposeNotes) ...[
                  const SizedBox(height: 8),
                  purposeNote,
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: actions),
                ],
                if (offers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < offers.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        offers[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Add location" — a warning chip on a vehicle with no area yet.
class _AddLocationChip extends StatelessWidget {
  const _AddLocationChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add location',
      child: Material(
        color: AppTint.warning,
        borderRadius: AppRadii.all(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(12),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(12),
              border: Border.all(color: AppTint.warningBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_location_alt_outlined,
                    size: 18, color: AppTint.warningText),
                const SizedBox(width: 6),
                Text(
                  'Add location',
                  style: AppType.small.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTint.warningText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UDrive's question or refusal on one use, with "Send again".
class _PurposeNote extends StatelessWidget {
  const _PurposeNote({
    required this.text,
    required this.tone,
    required this.busy,
    required this.onSendAgain,
  });

  final String text;
  final OwnerTagTone tone;
  final bool busy;
  final VoidCallback? onSendAgain;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color ink, Color border) = tone == OwnerTagTone.err
        ? (AppTint.danger, AppTint.dangerText, AppTint.dangerBorder)
        : (AppTint.warning, AppTint.warningText, AppTint.warningBorder);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppType.small.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          UdButton.outline(
            label: 'Send again',
            size: UdButtonSize.small,
            expand: false,
            busy: busy,
            onPressed: onSendAgain,
          ),
        ],
      ),
    );
  }
}

/// The "Add location" sheet: the area picker and Save.
class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.repository, required this.vehicle});

  final ListingRepository repository;
  final ListingVehicle vehicle;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  AreaSelection? _selection;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final selection = _selection;
    if (selection == null) {
      setState(() => _error =
          'Choose the district and tehsil where the vehicle is based.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository
          .setLocation(widget.vehicle.id, selection.tehsilId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text('Vehicle location',
              style: AppType.h2.copyWith(color: AppText.primary)),
          const SizedBox(height: 14),
          AreaPicker(
            api: widget.repository.api,
            initialTehsilId: widget.vehicle.tehsilId,
            onChanged: (selection) => setState(() {
              _selection = selection;
              _error = null;
            }),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.error_outline_rounded,
              text: _error,
            ),
          ],
          const SizedBox(height: 16),
          UdButton.primary(
            label: 'Save',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navy,
      borderRadius: AppRadii.all(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(14),
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppText.onInk),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.buttonSm.copyWith(color: AppText.onInk),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: AppRadii.all(AppRadii.chip),
                  ),
                  child: Text(
                    badge!,
                    style: AppType.small.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppText.onInk,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DriversCard extends StatelessWidget {
  const _DriversCard({
    required this.drivers,
    required this.onInvite,
    required this.onRemove,
  });

  final List<FleetDriver> drivers;
  final VoidCallback onInvite;
  final ValueChanged<FleetDriver> onRemove;

  static (String, OwnerTagTone) _tag(FleetDriver driver) {
    switch (driver.status) {
      case 'Approved':
        final days = driver.expiresInDays;
        final expiry = driver.licenceExpiry;
        if (!driver.licenceValid || (days != null && days < 0)) {
          return ('Licence expired', OwnerTagTone.err);
        }
        if (days != null && days <= 30) {
          return (
            days == 1
                ? 'Licence expires in 1 day'
                : 'Licence expires in $days days',
            OwnerTagTone.warn,
          );
        }
        if (expiry != null) {
          return ('Verified · till ${ownerMonthLabel(expiry)}', OwnerTagTone.ok);
        }
        return ('Verified', OwnerTagTone.ok);
      case 'Submitted':
        return ('In review', OwnerTagTone.info);
      case 'Rejected':
        return ('Rejected', OwnerTagTone.err);
      default:
        return ('Invited', OwnerTagTone.warn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Drivers',
                  style: AppType.listTitle.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: UdButton.dark(
                  label: '+ Invite',
                  size: UdButtonSize.small,
                  expand: false,
                  onPressed: onInvite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (drivers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4),
              child: Text(
                'No drivers yet. Invite the people who will drive your '
                'customers — each one uploads his own documents.',
                style: AppType.small.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppText.secondary,
                ),
              ),
            ),
          for (final driver in drivers) _row(driver),
        ],
      ),
    );
  }

  Widget _row(FleetDriver driver) {
    final (label, tone) = _tag(driver);
    final note = driver.reviewNote;
    return InkWell(
      onLongPress: driver.isOwner ? null : () => onRemove(driver),
      borderRadius: AppRadii.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    driver.isOwner ? 'You' : driver.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body2.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppText.primary,
                    ),
                  ),
                  if (driver.status == 'Rejected' &&
                      note != null &&
                      note.isNotEmpty)
                    Text(
                      note,
                      style: AppType.small.copyWith(
                        fontSize: 12.5,
                        color: AppTint.dangerText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: OwnerTag(label: label, tone: tone)),
            if (driver.isOwner)
              const SizedBox(width: 44)
            else
              IconButton(
                tooltip: 'Remove ${driver.name}',
                onPressed: () => onRemove(driver),
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppText.secondary, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddVehicleButton extends StatelessWidget {
  const _AddVehicleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: AppRadii.all(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(18),
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                '+ Add another vehicle',
                style: AppType.button.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.limeLine
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    ).deflate(1);
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 7), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The "+ Invite" sheet: a name and a phone number.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.repository});

  final ListingRepository repository;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Enter the driver\'s name and mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final driver =
          await widget.repository.inviteDriver(name: name, phone: phone);
      if (!mounted) return;
      Navigator.of(context).pop(driver);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text('Invite a driver',
              style: AppType.h2.copyWith(color: AppText.primary)),
          const SizedBox(height: 6),
          Text(
            'He gets a WhatsApp link, opens UDrive on his own phone and '
            'uploads his CNIC, licence and selfie.',
            style: AppType.body2.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 16),
          UdTextField(
            controller: _name,
            label: 'Driver\'s name',
            hint: 'Full name',
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          UdTextField(
            controller: _phone,
            label: 'Driver\'s phone',
            hint: '03xx xxxxxxx',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            onSubmitted: (_) => _send(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.error_outline_rounded,
              text: _error,
            ),
          ],
          const SizedBox(height: 16),
          UdButton.primary(
            label: 'Send invite',
            busy: _busy,
            onPressed: _busy ? null : _send,
          ),
        ],
      ),
    );
  }
}
