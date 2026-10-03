import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/vehicles/vehicle_usage_repository.dart';
import '../../core/widgets/ud_kit.dart';
import 'live_create_package_screen.dart';
import 'live_rent_settings_screen.dart';

/// D-33 — what one approved vehicle is used for.
///
/// This is not a second way to register a vehicle, and there is no such thing.
/// A Driver registers the vehicle once, an Admin verifies it, and that road is
/// untouched. What was missing was the step after it: saying what the vehicle
/// is *for*.
///
/// Until now that was decided by absence. Every verified vehicle took city
/// rides because nothing ever asked. Tour was a single switch with no
/// requirement behind it, buried in the price screen. And renting could not be
/// expressed at all, so the one thing a Driver most wanted to say — "this car
/// goes out on rent, stop sending me city requests for it" — had nowhere to go.
///
/// Every switch carries its own condition, and a switch whose condition is not
/// met does not move. Tapping it opens the screen where the condition is met
/// instead, because a switch that silently refuses, or throws an error on save,
/// is the worst of the three possible behaviours.
class LiveVehicleUsageScreen extends StatefulWidget {
  const LiveVehicleUsageScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  State<LiveVehicleUsageScreen> createState() => _LiveVehicleUsageScreenState();
}

class _LiveVehicleUsageScreenState extends State<LiveVehicleUsageScreen> {
  late final VehicleUsageRepository _repository =
      VehicleUsageRepository(AppControllerScope.of(context).apiClient);

  List<VehicleUsage> _all = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  VehicleUsage? get _vehicle {
    for (final vehicle in _all) {
      if (vehicle.vehicleId == widget.vehicleId) return vehicle;
    }
    return null;
  }

  /// The Driver's other vehicles that would still take city rides.
  ///
  /// Shown before renting is switched on, because "city rides stop" means
  /// something very different to a Driver with three cars and a Driver with
  /// one, and only they know which they are.
  List<VehicleUsage> get _othersOnCity => _all
      .where((v) => v.vehicleId != widget.vehicleId && v.availableForCity)
      .toList(growable: false);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repository.list();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _apply(Future<VehicleUsage> Function() write) async {
    setState(() => _saving = true);
    try {
      await write();
      await _load();
    } on VehicleUsageRefused catch (refusal) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say(refusal.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say('$error');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── the three switches ────────────────────────────────────────────────────

  Future<void> _toggleCity(bool value) async {
    final vehicle = _vehicle;
    if (vehicle == null) return;

    // Switching city on takes the vehicle off rent, which is the same rule
    // read the other way round. Said out loud rather than done quietly.
    if (value && vehicle.availableForRent) {
      final go = await _confirm(
        title: _t('This vehicle will come off rent',
            'یہ گاڑی کرائے سے ہٹ جائے گی'),
        body: _t(
          'A car cannot be out on rent and taking city rides at the same time. '
          'Turning city rides on takes this vehicle off the rental list.',
          'ایک گاڑی بیک وقت کرائے پر اور سٹی رائیڈز پر نہیں ہو سکتی۔ سٹی '
              'رائیڈز چالو کرنے سے یہ گاڑی کرائے کی فہرست سے ہٹ جائے گی۔',
        ),
        confirm: _t('Yes, city rides', 'ہاں، سٹی رائیڈز'),
      );
      if (go != true) return;
    }

    await _apply(() => _repository.setUsage(vehicle.vehicleId, city: value));
  }

  Future<void> _toggleTour(bool value) async {
    final vehicle = _vehicle;
    if (vehicle == null) return;
    await _apply(() => _repository.setUsage(vehicle.vehicleId, tour: value));
  }

  Future<void> _toggleRent(bool value) async {
    final vehicle = _vehicle;
    if (vehicle == null) return;

    if (value) {
      final others = _othersOnCity;
      final go = await _confirm(
        title: _t('City rides will stop', 'سٹی رائیڈز بند ہو جائیں گی'),
        body: others.isEmpty
            ? _t(
                'A car out on rent is with somebody else, so it cannot take '
                'city rides. This is your only vehicle on city rides, so ride '
                'requests will stop reaching you altogether.',
                'کرائے پر گئی گاڑی کسی اور کے پاس ہوتی ہے، اس لیے وہ سٹی '
                    'رائیڈ نہیں لے سکتی۔ سٹی رائیڈز پر آپ کی یہی ایک گاڑی ہے، '
                    'تو رائیڈ ریکوئسٹ آنا بالکل بند ہو جائے گا۔',
              )
            : _t(
                'A car out on rent is with somebody else, so it cannot take '
                'city rides. Ride requests for this vehicle will stop.',
                'کرائے پر گئی گاڑی کسی اور کے پاس ہوتی ہے، اس لیے وہ سٹی '
                    'رائیڈ نہیں لے سکتی۔ اس گاڑی پر ریکوئسٹ آنا بند ہو جائے گا۔',
              ),
        confirm: _t('Yes, put it on rent', 'ہاں، کرائے پر لگائیں'),
        extra: others.isEmpty
            ? null
            : others
                .map((other) => UdListRow(
                      title: other.name.isEmpty
                          ? other.registrationNumber
                          : '${other.name} · ${other.registrationNumber}',
                      subtitle: _t('Stays on city rides',
                          'سٹی رائیڈز پر رہے گی'),
                      trailing: UdBadge(
                        label: _t('CITY', 'سٹی'),
                        tone: UdTone.ok,
                      ),
                    ))
                .toList(growable: false),
      );
      if (go != true) return;
    }

    await _apply(() => _repository.setUsage(vehicle.vehicleId, rent: value));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirm,
    List<Widget>? extra,
  }) =>
      showUdSheet<bool>(
        context: context,
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  const UdIconTile(
                    icon: Icons.warning_amber_rounded,
                    tone: UdIconTone.soft,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: AppType.h3.copyWith(color: AppTint.warningText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              if (extra != null && extra.isNotEmpty) ...[
                const SizedBox(height: 16),
                UdSectionHeader(
                  title: _t('Your other vehicles', 'آپ کی دوسری گاڑیاں'),
                ),
                const SizedBox(height: 10),
                UdListGroup(children: extra),
              ],
              const SizedBox(height: 20),
              UdButton.primary(
                label: confirm,
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 10),
              UdButton.ghost(
                label: _t('Leave it as it is', 'ایسے ہی رہنے دیں'),
                onPressed: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      );

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicle;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: vehicle == null
            ? _t('Vehicle usage', 'گاڑی کا استعمال')
            : '${vehicle.name} · ${vehicle.registrationNumber}',
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 12, AppSizes.sidePadding, 40),
                children: [
                  if (_error != null)
                    UdBanner(tone: UdTone.err, text: _error),
                  if (vehicle == null)
                    UdEmptyState(
                      icon: Icons.directions_car_outlined,
                      title: _t('Vehicle not found', 'گاڑی نہیں ملی'),
                      text: _t(
                        'This vehicle is no longer on your account.',
                        'یہ گاڑی اب آپ کے اکاؤنٹ پر نہیں ہے۔',
                      ),
                    )
                  else ...[
                    ..._content(vehicle),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _content(VehicleUsage vehicle) {
    if (!vehicle.isVerified) {
      return [
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.schedule_rounded,
          text: _t(
            'An Admin has not verified this vehicle yet. Once it is verified '
            'you choose here what it is used for.',
            'ایڈمن نے ابھی یہ گاڑی تصدیق نہیں کی۔ تصدیق کے بعد آپ یہاں سے '
                'منتخب کریں گے کہ یہ کس کام پر لگے گی۔',
          ),
        ),
      ];
    }

    return [
      UdBanner(
        tone: UdTone.ok,
        icon: Icons.verified_rounded,
        text: _t(
          'Verified. Now choose what this vehicle is used for.',
          'تصدیق شدہ۔ اب منتخب کریں کہ یہ گاڑی کس کام پر لگے گی۔',
        ),
      ),
      const SizedBox(height: 16),

      // ── city rides
      _Usage(
        icon: Icons.local_taxi_rounded,
        title: _t('City rides', 'سٹی رائیڈز'),
        state: vehicle.availableForCity
            ? _t('On — requests reach you', 'چالو — ریکوئسٹ آ رہی ہیں')
            : _t('Off — no ride requests', 'بند — کوئی رائیڈ ریکوئسٹ نہیں'),
        on: vehicle.availableForCity,
        onChanged: _saving ? null : _toggleCity,
      ),
      const SizedBox(height: 12),

      // ── tour
      _Usage(
        icon: Icons.landscape_rounded,
        title: _t('Tour', 'ٹور'),
        state: vehicle.availableForTour
            ? _t('On — ${vehicle.livePackageCount} package(s) live',
                'چالو — ${vehicle.livePackageCount} پیکج لائیو')
            : _tourOffReason(vehicle),
        on: vehicle.availableForTour,
        // Both gates, and either one alone blocks it. A Driver whose vehicle
        // scored 82 and was still refused had hit the second one, with nothing
        // anywhere saying it existed.
        onChanged: _saving
            ? null
            : (vehicle.availableForTour || vehicle.canCarryTour
                ? _toggleTour
                : null),
        requirement: vehicle.canCarryTour && vehicle.availableForTour
            ? _Requirement(
                met: true,
                text: _t(
                  'Readiness ${vehicle.tourReadinessScore}/'
                  '${vehicle.tourReadinessRequired} · '
                  '${vehicle.livePackageCount} package(s)',
                  'ریڈینس ${vehicle.tourReadinessScore}/'
                      '${vehicle.tourReadinessRequired} · '
                      '${vehicle.livePackageCount} پیکج',
                ),
                action: _t('Packages', 'پیکج'),
                onTap: _openPackages,
              )
            : (!vehicle.meetsReadiness
                ? _Requirement(
                    met: false,
                    text: _t('Add the missing equipment',
                        'کمی والا سامان شامل کریں'),
                    action: _t('Open', 'کھولیں'),
                    onTap: () => _editEquipment(vehicle),
                  )
                : _Requirement(
                    met: false,
                    text: _t('Publish a package first',
                        'پہلے ایک پیکج شائع کریں'),
                    action: _t('Create', 'بنائیں'),
                    onTap: _openPackages,
                  )),
      ),
      const SizedBox(height: 12),

      // ── rent
      _Usage(
        icon: Icons.vpn_key_rounded,
        title: _t('Rent a car', 'کرائے پر گاڑی'),
        state: vehicle.availableForRent
            ? _t('On — listed for rent', 'چالو — کرائے کی فہرست میں')
            : (!vehicle.hasRentRate
                ? _t('Off — no daily rate set', 'بند — روزانہ کرایہ مقرر نہیں')
                : (!vehicle.hasPhoto
                    ? _t('Off — no photo of this car',
                        'بند — اس گاڑی کی تصویر نہیں')
                    : _t('Off — ready when you are', 'بند — تیار ہے'))),
        on: vehicle.availableForRent,
        onChanged: _saving
            ? null
            : (vehicle.availableForRent || vehicle.canBeRented
                ? _toggleRent
                : null),
        requirement: _Requirement(
          met: vehicle.hasRentRate,
          text: vehicle.hasRentRate
              ? _rentSummary(vehicle)
              : _t('Set a per-day rent', 'روزانہ کرایہ مقرر کریں'),
          action: vehicle.hasRentRate
              ? _t('Change', 'تبدیل کریں')
              : _t('Set', 'مقرر کریں'),
          onTap: () => _openRentSettings(vehicle),
        ),
        // The second thing renting needs. A listing of names and prices is a
        // listing nobody books from, and the only other picture this platform
        // could show is a stock photograph of the model — a different car.
        extra: _Requirement(
          met: vehicle.hasPhoto,
          text: vehicle.hasPhoto
              ? _t('Photo of this car added', 'اس گاڑی کی تصویر موجود')
              : _t('Add a photo of this car', 'اس گاڑی کی تصویر لگائیں'),
          action: vehicle.hasPhoto
              ? _t('Replace', 'بدلیں')
              : _t('Add', 'لگائیں'),
          onTap: () => _uploadPhoto(vehicle),
        ),
      ),

      const SizedBox(height: 18),
      UdBanner(
        tone: UdTone.info,
        icon: Icons.info_outline_rounded,
        text: _t(
          'One vehicle can do two jobs — city rides and tour. Rent is the '
          'third, and it closes city rides. A tour vehicle still receives ride '
          'requests and offers for any destination, not only where its package '
          'goes.',
          'ایک گاڑی دو کام کر سکتی ہے — سٹی رائیڈز اور ٹور۔ کرایہ تیسرا راستہ '
              'ہے جو سٹی رائیڈز بند کر دیتا ہے۔ ٹور والی گاڑی کو ہر منزل کے '
              'لیے ریکوئسٹ اور آفر ملتی رہیں گی، صرف پیکج کی منزل تک محدود '
              'نہیں۔',
        ),
      ),

      if (!vehicle.availableForCity &&
          !vehicle.availableForTour &&
          !vehicle.availableForRent) ...[
        const SizedBox(height: 12),
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.pause_circle_outline_rounded,
          text: _t(
            'Nothing is switched on, so no work will come to this vehicle. '
            'That is allowed — a car off the road for a month belongs here.',
            'کچھ بھی چالو نہیں ہے، تو اس گاڑی پر کوئی کام نہیں آئے گا۔ یہ '
                'اجازت ہے — ایک ماہ کے لیے بند گاڑی یہیں رکھی جاتی ہے۔',
          ),
        ),
      ],
    ];
  }

  String _tourOffReason(VehicleUsage vehicle) {
    if (!vehicle.meetsReadiness) {
      final missing = vehicle.tourReadinessMissing
          .map((item) => item.label.toLowerCase())
          .toList(growable: false);
      final needs = missing.isEmpty
          ? ''
          : ' — ${_t('needs', 'ضرورت')} ${missing.take(2).join(', ')}';
      return _t(
        'Readiness ${vehicle.tourReadinessScore}/'
        '${vehicle.tourReadinessRequired}$needs',
        'ریڈینس ${vehicle.tourReadinessScore}/'
            '${vehicle.tourReadinessRequired}$needs',
      );
    }
    if (vehicle.livePackageCount == 0) {
      return _t('No package published yet', 'ابھی کوئی پیکج شائع نہیں');
    }
    return _t('Off — not offered for tours', 'بند — ٹور کے لیے پیش نہیں');
  }

  String _rentSummary(VehicleUsage vehicle) {
    final parts = <String>[];
    if ((vehicle.rentWithDriverDaily ?? 0) > 0) {
      parts.add('${_t('With driver', 'ڈرائیور کے ساتھ')} '
          'PKR ${vehicle.rentWithDriverDaily!.round()}');
    }
    if ((vehicle.rentSelfDriveDaily ?? 0) > 0) {
      parts.add('${_t('Self-drive', 'خود چلائیں')} '
          'PKR ${vehicle.rentSelfDriveDaily!.round()}');
    }
    return parts.join(' · ');
  }

  Future<void> _openPackages() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LiveCreatePackageScreen()),
    );
    if (mounted) await _load();
  }

  /// One photograph of this car, replacing whatever was there.
  ///
  /// Nobody reviews it. That is the Driver's own responsibility, and a faster
  /// correction than a queue: a bad photograph costs them the booking.
  Future<void> _uploadPhoto(VehicleUsage vehicle) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;

    await _apply(() => _repository.uploadPhoto(vehicle.vehicleId, files.first));
  }

  Future<void> _openRentSettings(VehicleUsage vehicle) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRentSettingsScreen(vehicle: vehicle),
      ),
    );
    if (!mounted) return;
    if (changed == true) await _load();
  }

  /// The missing-equipment sheet.
  ///
  /// This exists because the vehicle edit refuses once an Admin has verified
  /// the vehicle, which left the readiness bar with no door at all: a Driver
  /// told "45, you need 60" could buy a first-aid kit and a spare tyre and
  /// nothing on the platform would ever record it. Only the equipment is
  /// editable here — make, model, registration and capacity are what was
  /// verified and stay locked.
  Future<void> _editEquipment(VehicleUsage vehicle) async {
    final chosen = <String, bool>{};
    for (final item in vehicle.tourReadinessMissing) {
      chosen[item.key] = false;
    }
    if (chosen.isEmpty) return;

    final saved = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                _t('What this vehicle carries', 'گاڑی میں کیا موجود ہے'),
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Tick what is actually in the vehicle. Readiness '
                  '${vehicle.tourReadinessScore} of '
                  '${vehicle.tourReadinessRequired} — the cheapest items are '
                  'listed first.',
                  'جو واقعی گاڑی میں موجود ہے اس پر نشان لگائیں۔ ریڈینس '
                      '${vehicle.tourReadinessScore} از '
                      '${vehicle.tourReadinessRequired} — سستی چیزیں پہلے۔',
                ),
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 16),
              UdListGroup(
                children: vehicle.tourReadinessMissing
                    .map((item) => UdListRow(
                          title: item.label,
                          subtitle: '+${item.points}',
                          trailing: UdSwitch(
                            value: chosen[item.key] ?? false,
                            onChanged: (value) => setSheetState(
                                () => chosen[item.key] = value),
                            semanticLabel: item.label,
                          ),
                        ))
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              UdButton.primary(
                label: _t('Save', 'محفوظ کریں'),
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 10),
              Text(
                _t(
                  'Only this equipment can change after verification. Make, '
                  'model, registration and capacity are what an Admin checked, '
                  'so they stay as they are.',
                  'تصدیق کے بعد صرف یہ سامان تبدیل ہو سکتا ہے۔ میک، ماڈل، '
                      'رجسٹریشن اور گنجائش ایڈمن نے جانچی ہے، وہ ویسی ہی '
                      'رہیں گی۔',
                ),
                style: AppType.caption.copyWith(color: AppText.caption),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;

    // Everything already on the vehicle stays on: the sheet only offers what
    // was missing, so anything not listed is already there.
    bool has(String key) =>
        chosen[key] ??
        !vehicle.tourReadinessMissing.any((item) => item.key == key);

    await _apply(() => _repository.setEquipment(
          vehicle.vehicleId,
          fourByFour: has('fourByFour'),
          firstAidKit: has('firstAidKit'),
          spareTyre: has('spareTyre'),
          fireExtinguisher: has('fireExtinguisher'),
          snowChains: has('snowChains'),
          heating: has('heating'),
          airConditioning: has('airConditioning'),
          childSeat: has('childSeat'),
        ));
  }
}

/// A requirement line under a switch: what it needs, and where to go.
class _Requirement {
  const _Requirement({
    required this.met,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final bool met;
  final String text;
  final String action;
  final VoidCallback onTap;
}

/// One usage: what it is, whether it is on, and the condition behind it.
class _Usage extends StatelessWidget {
  const _Usage({
    required this.icon,
    required this.title,
    required this.state,
    required this.on,
    required this.onChanged,
    this.requirement,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String state;
  final bool on;

  /// Null means the condition is not met, so the switch does not move. The
  /// requirement line below it is the way forward.
  final ValueChanged<bool>? onChanged;

  final _Requirement? requirement;

  /// A second condition, shown under the first. Renting has two.
  final _Requirement? extra;

  @override
  Widget build(BuildContext context) {
    final locked = onChanged == null;

    return UdCard(
      selected: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UdIconTile(
                icon: icon,
                tone: on ? UdIconTone.soft : UdIconTone.neutral,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.h3.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      state,
                      style: AppType.small.copyWith(
                        color: on
                            ? AppTint.successText
                            : (locked
                                ? AppTint.warningText
                                : AppText.secondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (locked)
                Icon(Icons.lock_outline_rounded,
                    size: 20, color: AppText.caption)
              else
                UdSwitch(
                  value: on,
                  onChanged: onChanged,
                  semanticLabel: title,
                ),
            ],
          ),
          if (requirement != null) ...[
            const SizedBox(height: 12),
            _RequirementBanner(requirement: requirement!),
          ],
          if (extra != null) ...[
            const SizedBox(height: 8),
            _RequirementBanner(requirement: extra!),
          ],
        ],
      ),
    );
  }
}


/// One condition under a switch: whether it is met, and where to go.
class _RequirementBanner extends StatelessWidget {
  const _RequirementBanner({required this.requirement});

  final _Requirement requirement;

  @override
  Widget build(BuildContext context) => UdBanner(
        tone: requirement.met ? UdTone.ok : UdTone.warn,
        icon: requirement.met
            ? Icons.check_circle_outline_rounded
            : Icons.lock_outline_rounded,
        text: requirement.text,
        onTap: requirement.onTap,
        trailing: Text(
          requirement.action,
          style: AppType.buttonSm.copyWith(color: AppColors.navy),
        ),
      );
}
