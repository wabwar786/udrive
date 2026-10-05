import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/listings/listing_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'listing_owner_parts.dart';
import 'my_vehicles_screen.dart';

/// "Earn with your vehicle" — the owner lists a vehicle in three steps.
///
/// 1. Your vehicle: type, make, model, year, plate, seats and three photos.
///    The first "Save" creates the draft on the server, because a photo can
///    only be uploaded against a vehicle id; the photo slots wake up then.
/// 2. What is it for: Rent and/or Tour, prices, kit, and who drives.
/// 3. About you: CNIC and selfie (asked once), the owner's licence when the
///    owner drives, and the agreement. Submit sends it for review.
///
/// Opening it with [existing] continues a Draft or a Rejected vehicle.
class ListingWizardScreen extends StatefulWidget {
  const ListingWizardScreen({this.existing, super.key});

  final ListingVehicle? existing;

  @override
  State<ListingWizardScreen> createState() => _ListingWizardScreenState();
}

const _seatDefaults = <String, int>{
  'Car': 4,
  'Jeep': 6,
  'Hiace': 14,
  'Coster': 29,
};

const _typeLabels = <String, String>{
  'Car': 'Car',
  'Jeep': 'Jeep (4x4)',
  'Hiace': 'Hiace',
  'Coster': 'Coster',
};

const _typeIcons = <String, IconData>{
  'Car': Icons.directions_car_rounded,
  'Jeep': Icons.landscape_rounded,
  'Hiace': Icons.airport_shuttle_rounded,
  'Coster': Icons.directions_bus_rounded,
};

const _ownerAgreementFallback =
    'The vehicle\'s papers, fitness and insurance, and the conduct of anyone '
    'I let drive it, are my responsibility. UDrive introduces customers to '
    'vehicle owners and checks the documents sent here; it does not inspect '
    'the vehicle.';

class _ListingWizardScreenState extends State<ListingWizardScreen> {
  ListingRepository? _repo;

  final _vehicleForm = GlobalKey<FormState>();
  final _scroll = ScrollController();

  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _plate = TextEditingController();
  final _seats = TextEditingController();
  final _withDriver = TextEditingController();
  final _selfDrive = TextEditingController();
  final _pickup = TextEditingController();
  final _inviteName = TextEditingController();
  final _invitePhone = TextEditingController();
  final _licenceNumber = TextEditingController();

  bool _loading = true;
  String? _loadError;

  int _step = 0;
  ListingVehicle? _vehicle;
  ListingOwner? _owner;
  List<FleetDriver> _fleet = const [];

  String _category = 'Car';
  bool _wantsRent = true;
  bool _wantsTour = false;
  ListingKit _kit = const ListingKit();

  /// "Self", "Drivers" or "Both".
  String _drivers = 'Self';
  DateTime? _licenceExpiry;
  bool _agree = false;
  String _agreementText = _ownerAgreementFallback;

  bool _busy = false;
  bool _inviting = false;
  String? _uploading;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _vehicle = existing;
    if (existing != null) {
      _category = _seatDefaults.containsKey(existing.pickerCategory)
          ? existing.pickerCategory
          : 'Car';
      _make.text = existing.make;
      _model.text = existing.model;
      _year.text = existing.year > 0 ? '${existing.year}' : '';
      _plate.text = existing.registrationNumber;
      _seats.text = '${existing.seats}';
      _wantsRent = existing.wantsRent;
      _wantsTour = existing.wantsTour;
      _kit = existing.kit;
      _withDriver.text = _rateText(existing.withDriverDaily);
      _selfDrive.text = _rateText(existing.selfDriveDaily);
      _pickup.text = existing.pickupPoint ?? '';
    } else {
      _seats.text = '${_seatDefaults[_category]}';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = ListingRepository(AppControllerScope.of(context).apiClient);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
        _loadAgreement();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [
      _make,
      _model,
      _year,
      _plate,
      _seats,
      _withDriver,
      _selfDrive,
      _pickup,
      _inviteName,
      _invitePhone,
      _licenceNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _rateText(double? value) =>
      value == null || value <= 0 ? '' : value.round().toString();

  static double? _rate(TextEditingController controller) {
    final value = double.tryParse(controller.text.replaceAll(',', '').trim());
    return value == null || value <= 0 ? null : value;
  }

  static String _message(Object error) =>
      '$error'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final home = await repo.home();
      if (!mounted) return;
      final owner = home.owner;
      final others = home.drivers.any((d) => !d.isOwner);
      setState(() {
        _owner = owner;
        _fleet = home.drivers;
        if (owner.hasProfile) {
          _drivers = owner.drivesSelf
              ? (others ? 'Both' : 'Self')
              : 'Drivers';
        }
        if (_licenceNumber.text.isEmpty) {
          _licenceNumber.text = owner.licenceNumber ?? '';
        }
        _licenceExpiry ??= owner.licenceExpiry;
        _agree = owner.agreementAccepted;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadAgreement() async {
    final repo = _repo;
    if (repo == null) return;
    final text =
        await loadOwnerPublicText(repo.api, 'listing.owner_agreement_en');
    if (!mounted || text == null) return;
    setState(() => _agreementText = text);
  }

  // ─────────────────────────────────────────────────────────── actions

  void _pickCategory(String category) {
    setState(() {
      _category = category;
      _seats.text = '${_seatDefaults[category]}';
      if (category == 'Jeep' && !_kit.fourByFour) {
        _kit = _kit.toggled('fourByFour');
      }
    });
  }

  Future<bool> _save() async {
    final repo = _repo;
    if (repo == null) return false;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final saved = await repo.saveVehicle(
        vehicleId: _vehicle?.id,
        category: _category,
        make: _make.text,
        model: _model.text,
        year: int.tryParse(_year.text.trim()) ?? 0,
        registrationNumber: _plate.text.toUpperCase(),
        seats: int.tryParse(_seats.text.trim()) ?? 0,
        wantsRent: _wantsRent,
        wantsTour: _wantsTour,
        drivers: _drivers,
        withDriverDaily: _wantsRent ? _rate(_withDriver) : null,
        selfDriveDaily: _wantsRent ? _rate(_selfDrive) : null,
        pickupPoint: _wantsRent ? _pickup.text : null,
        kit: _kit,
      );
      if (!mounted) return false;
      setState(() {
        _vehicle = saved;
        _busy = false;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _error = _message(error);
        _busy = false;
      });
      return false;
    }
  }

  Future<void> _uploadPhoto(String kind) async {
    final repo = _repo;
    final vehicle = _vehicle;
    if (repo == null || vehicle == null) return;
    final file = await pickOwnerImage();
    if (file == null || !mounted) return;
    setState(() {
      _uploading = kind;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await repo.uploadVehiclePhoto(vehicle.id, kind, file);
      if (!mounted) return;
      setState(() {
        _vehicle = updated;
        _uploading = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = null;
        _error = 'The photo did not upload: ${_message(error)} '
            'Tap the slot to try again.';
      });
    }
  }

  Future<void> _uploadOwnerDoc(String kind) async {
    final repo = _repo;
    if (repo == null) return;
    final file = await pickOwnerImage();
    if (file == null || !mounted) return;
    setState(() {
      _uploading = kind;
      _error = null;
    });
    try {
      final owner = await repo.uploadOwnerDocument(kind, file);
      if (!mounted) return;
      setState(() {
        _owner = owner;
        _uploading = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = null;
        _error = 'The photo did not upload: ${_message(error)} '
            'Tap the slot to try again.';
      });
    }
  }

  Future<void> _invite() async {
    final repo = _repo;
    if (repo == null) return;
    final name = _inviteName.text.trim();
    final phone = _invitePhone.text.trim();
    if (name.isEmpty || phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Enter the driver\'s name and mobile number.');
      return;
    }
    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      final driver = await repo.inviteDriver(name: name, phone: phone);
      if (!mounted) return;
      setState(() {
        _fleet = [..._fleet, driver];
        _inviting = false;
        _inviteName.clear();
        _invitePhone.clear();
        _notice = '$name has been sent a WhatsApp invite.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inviting = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _licenceExpiry != null && _licenceExpiry!.isAfter(today)
        ? _licenceExpiry!
        : today.add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 20)),
    );
    if (picked == null || !mounted) return;
    setState(() => _licenceExpiry = picked);
  }

  void _goTo(int step) {
    setState(() {
      _step = step;
      _error = null;
      _notice = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_busy) return;
    if (_step > 0) {
      _goTo(_step - 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _next() async {
    if (_busy || _uploading != null) return;
    switch (_step) {
      case 0:
        await _nextFromVehicle();
      case 1:
        await _nextFromUse();
      default:
        await _submit();
    }
  }

  Future<void> _nextFromVehicle() async {
    if (!(_vehicleForm.currentState?.validate() ?? false)) {
      setState(() => _error = 'Check the highlighted fields.');
      return;
    }
    final hadDraft = _vehicle != null;
    if (!await _save()) return;
    if (!mounted) return;
    if (!hadDraft) {
      setState(() => _notice = 'Saved. Now add the 3 photos below.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      return;
    }
    if (!(_vehicle?.photosDone ?? false)) {
      setState(() => _error = 'Add the 3 photos to continue.');
      return;
    }
    _goTo(1);
  }

  Future<void> _nextFromUse() async {
    if (!_wantsRent && !_wantsTour) {
      setState(() => _error = 'Pick Rent, Tour or both.');
      return;
    }
    if (_wantsRent) {
      if (_rate(_withDriver) == null && _rate(_selfDrive) == null) {
        setState(() => _error = 'Enter at least one daily price for Rent.');
        return;
      }
      if (_pickup.text.trim().isEmpty) {
        setState(() => _error = 'Enter the pickup city for Rent.');
        return;
      }
    }
    if (!await _save()) return;
    if (!mounted) return;
    _goTo(2);
  }

  bool get _ownerDrives => _drivers != 'Drivers';

  Future<void> _submit() async {
    final repo = _repo;
    final vehicle = _vehicle;
    final owner = _owner;
    if (repo == null || vehicle == null || owner == null) return;

    String? problem;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!owner.identityDone) {
      problem = 'Add your CNIC front, back and a selfie.';
    } else if (_ownerDrives && !(owner.licenceFront && owner.licenceBack)) {
      problem = 'Add both sides of your driving licence.';
    } else if (_ownerDrives && _licenceNumber.text.trim().isEmpty) {
      problem = 'Enter your licence number.';
    } else if (_ownerDrives &&
        (_licenceExpiry == null || _licenceExpiry!.isBefore(today))) {
      problem = 'Pick a licence expiry date that is still ahead.';
    } else if (!_agree) {
      problem = 'Accept the vehicle owner agreement to submit.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.submit(
        vehicle.id,
        licenceNumber: _ownerDrives ? _licenceNumber.text : null,
        licenceExpiry: _ownerDrives ? _licenceExpiry : null,
        acceptAgreement: true,
        agreementVersion: owner.agreementVersion,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MyVehiclesScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    }
  }

  // ─────────────────────────────────────────────────────────── build

  static const _titles = ['Your vehicle', 'What is it for?', 'About you'];

  String get _buttonLabel => switch (_step) {
        0 => _vehicle == null ? 'Save and add photos' : 'Next — Rent or Tour',
        1 => 'Next — About you',
        _ => 'Submit for review',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0 && !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_step > 0 && !_busy) _goTo(_step - 1);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerNavyHeader(
              overline: 'STEP ${_step + 1} OF 3',
              title: _titles[_step],
              steps: 3,
              current: _step + 1,
              onBack: _back,
            ),
            Expanded(child: _body()),
            if (!_loading && _loadError == null)
              UdBottomBar(
                children: [
                  if (_error != null)
                    UdBanner(
                      tone: UdTone.err,
                      icon: Icons.error_outline_rounded,
                      text: _error,
                    ),
                  if (_error == null && _notice != null)
                    UdBanner(
                      tone: UdTone.ok,
                      icon: Icons.check_circle_outline_rounded,
                      text: _notice,
                    ),
                  UdButton.primary(
                    label: _buttonLabel,
                    trailingIcon:
                        _step < 2 ? Icons.chevron_right_rounded : null,
                    busy: _busy,
                    onPressed: _busy || _uploading != null ? null : _next,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.sidePadding),
        children: [
          UdBanner(
            tone: UdTone.err,
            icon: Icons.error_outline_rounded,
            text: _loadError,
          ),
          const SizedBox(height: 14),
          UdButton.outline(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: _load,
          ),
        ],
      );
    }
    final children = switch (_step) {
      0 => _vehicleStep(),
      1 => _useStep(),
      _ => _ownerStep(),
    };
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: children,
    );
  }

  // ── step 1 ──────────────────────────────────────────────────────────────

  List<Widget> _vehicleStep() {
    final vehicle = _vehicle;
    final note = vehicle?.reviewNote;
    final draftExists = vehicle != null;
    return [
      if (note != null && note.isNotEmpty) ...[
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.info_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vehicle?.status == 'Rejected'
                    ? 'Not approved'
                    : 'UDrive asked for changes',
                style: AppType.body2.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTint.warningText,
                ),
              ),
              const SizedBox(height: 2),
              Text(note),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
      Form(
        key: _vehicleForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OwnerCaps('Type'),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final type in _seatDefaults.keys) ...[
                  if (type != 'Car') const SizedBox(width: 8),
                  Expanded(child: _typeTile(type)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: UdTextField(
                    controller: _make,
                    label: 'Make',
                    hint: 'Toyota',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter the make' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: UdTextField(
                    controller: _model,
                    label: 'Model',
                    hint: 'Corolla',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter the model' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: UdTextField(
                    controller: _year,
                    label: 'Year',
                    hint: '2019',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: (v) {
                      final year = int.tryParse((v ?? '').trim());
                      final max = DateTime.now().year + 1;
                      return year == null || year < 1970 || year > max
                          ? 'Enter a real year'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: UdTextField(
                    controller: _seats,
                    label: 'Seats',
                    hint: '${_seatDefaults[_category]}',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    validator: (v) {
                      final seats = int.tryParse((v ?? '').trim());
                      return seats == null || seats < 1 || seats > 60
                          ? 'Enter the seats'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            UdTextField(
              controller: _plate,
              label: 'Number plate',
              hint: 'MRD-1234',
              textCapitalization: TextCapitalization.characters,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the number plate' : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const OwnerCaps('3 photos'),
      const SizedBox(height: 8),
      if (!draftExists) ...[
        const UdBanner(
          tone: UdTone.info,
          icon: Icons.info_outline_rounded,
          text: 'Save details to add photos. The photo slots open once your '
              'vehicle is saved.',
        ),
        const SizedBox(height: 10),
      ],
      Row(
        children: [
          Expanded(
            child: OwnerPhotoSlot(
              label: 'Car front',
              caption: 'shown to customers',
              icon: Icons.photo_camera_outlined,
              done: vehicle?.docFront ?? false,
              busy: _uploading == 'front',
              imageUrl: vehicle?.photoUrl == null
                  ? null
                  : ApiConfig.absoluteUrl(vehicle!.photoUrl),
              onTap: draftExists ? () => _uploadPhoto('front') : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OwnerPhotoSlot(
              label: 'Registration book',
              caption: 'front',
              icon: Icons.description_outlined,
              done: vehicle?.docRegistrationFront ?? false,
              busy: _uploading == 'registration-front',
              onTap: draftExists
                  ? () => _uploadPhoto('registration-front')
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OwnerPhotoSlot(
              label: 'Registration book',
              caption: 'back',
              icon: Icons.description_outlined,
              done: vehicle?.docRegistrationBack ?? false,
              busy: _uploading == 'registration-back',
              onTap: draftExists
                  ? () => _uploadPhoto('registration-back')
                  : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Only these. More photos can be added later from My vehicles.',
        style: AppType.small.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppText.secondary,
          height: 1.45,
        ),
      ),
    ];
  }

  Widget _typeTile(String type) {
    final selected = _category == type;
    final ink = selected ? AppText.onInk : AppText.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: _typeLabels[type],
      child: Material(
        color: selected ? AppColors.navy : AppColors.background,
        borderRadius: AppRadii.all(16),
        child: InkWell(
          onTap: () => _pickCategory(type),
          borderRadius: AppRadii.all(16),
          child: Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(16),
              border: Border.all(
                color: selected ? AppColors.navy : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_typeIcons[type], size: 24, color: ink),
                const SizedBox(height: 4),
                Text(
                  _typeLabels[type] ?? type,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── step 2 ──────────────────────────────────────────────────────────────

  List<Widget> _useStep() {
    final others = _fleet.where((d) => !d.isOwner).toList();
    return [
      Row(
        children: [
          Expanded(
            child: _useToggle('Rent', _wantsRent,
                () => setState(() => _wantsRent = !_wantsRent)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _useToggle('Tour', _wantsTour,
                () => setState(() => _wantsTour = !_wantsTour)),
          ),
        ],
      ),
      if (_wantsRent) ...[
        const SizedBox(height: 12),
        _box(
          children: [
            _boxTitle('Rent'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: UdTextField(
                    controller: _withDriver,
                    label: 'With driver / day',
                    hint: 'PKR 9,000',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: UdTextField(
                    controller: _selfDrive,
                    label: 'Self-drive / day',
                    hint: 'PKR 6,500',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            UdTextField(
              controller: _pickup,
              label: 'Pickup city',
              hint: 'Muzaffarabad',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            _note('Leave a price empty to not offer it. Self-drive customers '
                'show their own CNIC and licence before taking the car.'),
          ],
        ),
      ],
      if (_wantsTour) ...[
        const SizedBox(height: 12),
        _box(
          children: [
            _boxTitle('Tour'),
            const SizedBox(height: 10),
            const OwnerCaps('The vehicle has'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in ListingKit.labels.entries)
                  UdChip(
                    label: entry.value,
                    selected: _kit[entry.key],
                    icon: _kit[entry.key] ? Icons.check_rounded : null,
                    onTap: () =>
                        setState(() => _kit = _kit.toggled(entry.key)),
                  ),
              ],
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _box(
        strong: true,
        children: [
          _boxTitle('Who drives the customers?'),
          const SizedBox(height: 4),
          _note('For tours and rent with driver. Everyone who drives needs a '
              'verified licence.'),
          const SizedBox(height: 10),
          UdSegmented(
            options: const ['I drive', 'My drivers', 'Both'],
            index: switch (_drivers) {
              'Drivers' => 1,
              'Both' => 2,
              _ => 0,
            },
            onChanged: (i) => setState(
                () => _drivers = const ['Self', 'Drivers', 'Both'][i]),
          ),
          if (_ownerDrives) ...[
            const SizedBox(height: 10),
            const UdBanner(
              tone: UdTone.info,
              text: 'Your licence is asked in the next step.',
            ),
          ],
          if (_drivers != 'Self') ...[
            const SizedBox(height: 12),
            UdTextField(
              controller: _inviteName,
              label: 'Driver\'s name',
              hint: 'Full name',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: UdTextField(
                    controller: _invitePhone,
                    label: 'Driver\'s phone',
                    hint: '03xx xxxxxxx',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                UdButton.dark(
                  label: 'Invite',
                  expand: false,
                  busy: _inviting,
                  onPressed: _inviting ? null : _invite,
                ),
              ],
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final driver in others) ...[
                _invitedRow(driver),
                const SizedBox(height: 6),
              ],
            ],
            const SizedBox(height: 6),
            _note('The driver gets a WhatsApp link, opens UDrive on his own '
                'phone and uploads his CNIC, licence and selfie. Tours and '
                'rent-with-driver stay off until at least one driver is '
                'approved.'),
          ],
        ],
      ),
    ];
  }

  Widget _useToggle(String label, bool on, VoidCallback onTap) {
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: Material(
        color: on ? AppTint.success : AppColors.background,
        borderRadius: AppRadii.all(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(18),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(18),
              border: Border.all(
                color: on ? AppColors.limeLine : AppColors.border,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? AppColors.brand : AppColors.background,
                    borderRadius: AppRadii.all(6),
                    border: Border.all(color: AppColors.navy, width: 2),
                  ),
                  child: on
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: AppColors.navy)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: AppType.listTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _invitedRow(FleetDriver driver) {
    final (String label, OwnerTagTone tone) = switch (driver.status) {
      'Approved' => ('Verified', OwnerTagTone.ok),
      'Submitted' => ('In review', OwnerTagTone.info),
      'Rejected' => ('Rejected', OwnerTagTone.err),
      _ => ('Invited', OwnerTagTone.warn),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.name,
                  style: AppType.body2.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                Text(
                  driver.phone,
                  style: AppType.small.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          OwnerTag(label: label, tone: tone),
        ],
      ),
    );
  }

  // ── step 3 ──────────────────────────────────────────────────────────────

  List<Widget> _ownerStep() {
    final owner = _owner;
    if (owner == null) return const [];
    return [
      if (owner.identityDone)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTint.success,
            borderRadius: AppRadii.all(16),
            border: Border.all(color: AppTint.successBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: AppTint.successText, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'CNIC and selfie on file',
                  style: AppType.body2.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTint.successText,
                  ),
                ),
              ),
            ],
          ),
        )
      else ...[
        _note('Asked once. Your next vehicles skip this step.'),
        const SizedBox(height: 12),
        const OwnerCaps('CNIC'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OwnerPhotoSlot(
                label: 'Front',
                icon: Icons.badge_outlined,
                done: owner.cnicFront,
                busy: _uploading == 'cnic-front',
                onTap: () => _uploadOwnerDoc('cnic-front'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OwnerPhotoSlot(
                label: 'Back',
                icon: Icons.badge_outlined,
                done: owner.cnicBack,
                busy: _uploading == 'cnic-back',
                onTap: () => _uploadOwnerDoc('cnic-back'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const OwnerCaps('A selfie'),
        const SizedBox(height: 8),
        OwnerPhotoSlot(
          label: owner.selfie ? 'Selfie' : 'Take a selfie',
          icon: Icons.face_rounded,
          height: 72,
          done: owner.selfie,
          busy: _uploading == 'selfie',
          onTap: () => _uploadOwnerDoc('selfie'),
        ),
      ],
      if (_ownerDrives) ...[
        const SizedBox(height: 14),
        _box(
          strong: true,
          children: [
            Row(
              children: [
                Expanded(child: _boxTitle('Your driving licence')),
                const OwnerTag(label: 'Required', tone: OwnerTagTone.warn),
              ],
            ),
            const SizedBox(height: 4),
            _note('Because you will drive customers yourself. Not asked if '
                'only your drivers drive.'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OwnerPhotoSlot(
                    label: 'Licence front',
                    icon: Icons.credit_card_rounded,
                    height: 88,
                    done: owner.licenceFront,
                    busy: _uploading == 'licence-front',
                    onTap: () => _uploadOwnerDoc('licence-front'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OwnerPhotoSlot(
                    label: 'Licence back',
                    icon: Icons.credit_card_rounded,
                    height: 88,
                    done: owner.licenceBack,
                    busy: _uploading == 'licence-back',
                    onTap: () => _uploadOwnerDoc('licence-back'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            UdTextField(
              controller: _licenceNumber,
              label: 'Licence no.',
              hint: 'As printed on the card',
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            OwnerDateField(
              label: 'Expires on',
              value: _licenceExpiry,
              onTap: _pickExpiry,
            ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UdCheckbox(
            value: _agree,
            onChanged: (v) => setState(() => _agree = v),
            semanticLabel: 'I accept the vehicle owner agreement',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _agree = !_agree),
                  child: Text(
                    'I accept the ',
                    style: AppType.body2.copyWith(color: AppText.primary),
                  ),
                ),
                InkWell(
                  onTap: () => showOwnerAgreementSheet(
                    context,
                    title: 'Vehicle owner agreement',
                    text: _agreementText,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Vehicle owner agreement',
                      style: AppType.body2.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // ── small pieces ────────────────────────────────────────────────────────

  Widget _box({required List<Widget> children, bool strong = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(
          color: strong ? AppColors.navy : AppColors.border,
          width: strong ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _boxTitle(String text) => Text(
        text,
        style: AppType.listTitle.copyWith(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          color: AppText.primary,
        ),
      );

  Widget _note(String text) => Text(
        text,
        style: AppType.small.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppText.secondary,
          height: 1.45,
        ),
      );
}
