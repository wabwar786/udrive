import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/media/image_compressor.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';
import '../../../models/auth_models.dart';

/// D-08 — register a vehicle against the live backend.
///
/// Two states in one screen: the details form, and — once the record exists —
/// the four documents that have to hang off it. They are one screen because
/// they are one job, and because a vehicle saved but never documented is a row
/// nobody will ever approve.
///
/// This one keeps its own `Scaffold`. It is pushed from the vehicle list, not
/// rendered by `main_shell`, so there is no bar above it to collide with.
class LiveVehicleRegistrationScreen extends StatefulWidget {
  const LiveVehicleRegistrationScreen({super.key});
  @override
  State<LiveVehicleRegistrationScreen> createState() =>
      _LiveVehicleRegistrationScreenState();
}

class _LiveVehicleRegistrationScreenState
    extends State<LiveVehicleRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _make = TextEditingController(text: 'Toyota');
  final _model = TextEditingController(text: 'Fortuner');
  final _year = TextEditingController(text: '2022');
  final _registration = TextEditingController();
  final _colour = TextEditingController(text: 'White');
  String _category = 'SUV';
  int _seats = 7;
  int _luggage = 4;
  bool _ac = true;
  bool _heating = true;
  bool _fourByFour = true;
  bool _firstAid = true;
  bool _fireExtinguisher = true;
  bool _spareTyre = true;
  bool _snowChains = false;
  bool _childSeat = false;
  bool _busy = false;
  String? _error;
  LiveVehicle? _created;
  final Set<String> _uploaded = {};

  static const _requiredDocuments = <(String, String)>[
    ('REGISTRATION_BOOK', 'Registration book/document'),
    ('VEHICLE_FRONT', 'Vehicle front photograph'),
    ('VEHICLE_REAR', 'Vehicle rear photograph'),
    ('VEHICLE_INTERIOR', 'Vehicle interior photograph'),
  ];

  static const _categories = <String>[
    'Motorcycle',
    'Scooter',
    'Auto Rickshaw',
    'Tuk Tuk',
    'Economy Car',
    'Sedan',
    'SUV',
    '7-Seater',
    'Hiace',
    'Coaster',
    '4×4 Jeep',
    'Luxury Car',
  ];

  bool get _isTwoWheel => _category == 'Motorcycle' || _category == 'Scooter';
  bool get _isThreeWheel =>
      _category == 'Auto Rickshaw' || _category == 'Tuk Tuk';
  String get _wheelLabel =>
      _isTwoWheel ? '2-wheel' : (_isThreeWheel ? '3-wheel' : '4-wheel');
  IconData get _wheelIcon => _isTwoWheel
      ? Icons.two_wheeler_rounded
      : (_isThreeWheel
          ? Icons.electric_rickshaw_rounded
          : Icons.directions_car_filled_rounded);

  void _applyCategory(String value) {
    setState(() {
      _category = value;
      if (_isTwoWheel) {
        _seats = 1;
        _luggage = 0;
        _ac = false;
        _heating = false;
        _fourByFour = false;
        _fireExtinguisher = false;
        _spareTyre = true;
        _snowChains = false;
        _childSeat = false;
      } else if (_isThreeWheel) {
        _seats = 3;
        _luggage = 1;
        _ac = false;
        _heating = false;
        _fourByFour = false;
        _fireExtinguisher = false;
        _spareTyre = true;
        _snowChains = false;
        _childSeat = false;
      } else {
        if (_seats < 4) _seats = 4;
        if (_luggage < 2) _luggage = 2;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_make, _model, _year, _registration, _colour]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: UdTopBar(
          title: 'Live vehicle registration',
          onBack: () => Navigator.pop(context),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
          children: [
            // The navy strip the artboard opens with. It was a two-colour
            // gradient built out of `inkDeep`; flat navy is what the design
            // shows, and it is the last screen in the app that held those
            // tokens.
            UdCard(
              tone: UdCardTone.navy,
              child: Row(
                children: [
                  const UdIconTile(
                    icon: Icons.directions_car_filled_rounded,
                    tone: UdIconTone.lime,
                    size: UdIconTileSize.lg,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Register a tourism-ready vehicle with real backend '
                      'verification.',
                      style: AppType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                        color: AppText.onInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              UdBanner(
                tone: UdTone.err,
                icon: Icons.error_outline_rounded,
                text: _error,
              ),
            ],
            const SizedBox(height: 16),
            if (_created == null) _detailsForm() else _documentUpload(),
          ],
        ),
      );

  // --------------------------------------------------------------- the form

  Widget _detailsForm() => UdCard(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Vehicle details and safety equipment',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 16),

              // Was a `DropdownButtonFormField`. Twelve categories in a menu
              // that opens over the field and paints itself in Material's
              // colours, not ours — so it is a field that opens a sheet now,
              // and `_applyCategory` is called with exactly the same string.
              const UdLabel('Vehicle category'),
              const SizedBox(height: 8),
              _PickerField(
                icon: Icons.category_outlined,
                value: _category,
                onTap: _busy ? null : _pickCategory,
              ),
              const SizedBox(height: 12),

              // What picking a category just did to the rest of the form.
              // Without it, choosing "Motorcycle" silently drops the seat
              // count to 1 and switches six toggles off.
              UdBanner(
                tone: UdTone.gray,
                icon: _wheelIcon,
                text: '$_wheelLabel vehicle · Register it here, complete '
                    'verification, then go online to receive matching '
                    'Customer requests.',
              ),
              const SizedBox(height: 16),

              _field(_make, 'Manufacturer', Icons.factory_outlined),
              _field(_model, 'Model', Icons.directions_car_outlined),
              _field(_year, 'Year', Icons.calendar_month_outlined,
                  keyboard: TextInputType.number),
              _field(_registration, 'Registration number',
                  Icons.confirmation_number_outlined,
                  hint: 'e.g. AJK-2234'),
              _field(_colour, 'Vehicle colour', Icons.palette_outlined),

              const SizedBox(height: 4),

              // Counters and toggles share one bordered group, because on the
              // artboard they share one column of hairlines.
              UdListGroup(
                bordered: false,
                children: [
                  _counter('Passenger capacity', _seats, 1, 60,
                      (v) => setState(() => _seats = v)),
                  _counter('Luggage capacity', _luggage, 0, 100,
                      (v) => setState(() => _luggage = v)),
                  _switch('Air conditioning', _ac,
                      (v) => setState(() => _ac = v)),
                  _switch('Heating', _heating,
                      (v) => setState(() => _heating = v)),
                  _switch('4×4 capability', _fourByFour,
                      (v) => setState(() => _fourByFour = v)),
                  _switch('First-aid kit', _firstAid,
                      (v) => setState(() => _firstAid = v)),
                  _switch('Fire extinguisher', _fireExtinguisher,
                      (v) => setState(() => _fireExtinguisher = v)),
                  _switch('Spare tyre and tools', _spareTyre,
                      (v) => setState(() => _spareTyre = v)),
                  _switch('Snow chains', _snowChains,
                      (v) => setState(() => _snowChains = v)),
                  _switch('Child seat', _childSeat,
                      (v) => setState(() => _childSeat = v)),
                ],
              ),

              const SizedBox(height: 18),
              UdButton.dark(
                label: 'Save vehicle in live database',
                trailingIcon: Icons.file_upload_outlined,
                busy: _busy,
                onPressed: _busy ? null : _createVehicle,
              ),
            ],
          ),
        ),
      );

  /// The category sheet — twelve rows, the current one ticked.
  Future<void> _pickCategory() async {
    final picked = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              'Vehicle category',
              style: AppType.h2.copyWith(color: AppText.primary),
            ),
            const SizedBox(height: 14),
            UdListGroup(
              children: [
                for (final option in _categories)
                  UdListRow(
                    title: option,
                    onTap: () => Navigator.pop(sheetContext, option),
                    trailing: option == _category
                        ? const Icon(Icons.check_rounded,
                            size: 22, color: AppColors.brandInk)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) _applyCategory(picked);
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: UdTextField(
          controller: c,
          label: label,
          hint: hint,
          icon: icon,
          keyboardType: keyboard,
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Required' : null,
        ),
      );

  Widget _counter(String label, int value, int min, int max,
          ValueChanged<int> changed) =>
      UdListRow(
        title: label,
        trailing: _Counter(
          value: value,
          onDecrease: value > min ? () => changed(value - 1) : null,
          onIncrease: value < max ? () => changed(value + 1) : null,
          label: label,
        ),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> changed) =>
      UdListRow(
        title: label,
        trailing: UdSwitch(
          value: value,
          onChanged: changed,
          semanticLabel: label,
        ),
      );

  // ---------------------------------------------------------- the documents

  Widget _documentUpload() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UdBanner(
            tone: UdTone.ok,
            icon: Icons.check_circle_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_created!.make} ${_created!.model}',
                  style: AppType.listTitle.copyWith(color: AppText.primary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_created!.registrationNumber} · readiness '
                  '${_created!.mountainReadinessScore}%',
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const UdSectionHeader(
            title: 'Required documents and photographs',
            caption: 'JPG, PNG, WebP or PDF. Photographs are shrunk before '
                'they leave your phone.',
          ),
          const SizedBox(height: 12),
          UdListGroup(
            children: [
              for (final item in _requiredDocuments)
                UdListRow(
                  title: item.$2,
                  subtitle: _uploaded.contains(item.$1)
                      ? 'Uploaded'
                      : 'Tap to select a file',
                  leading: UdIconTile(
                    icon: _uploaded.contains(item.$1)
                        ? Icons.check_rounded
                        : Icons.upload_file_rounded,
                    tone: _uploaded.contains(item.$1)
                        ? UdIconTone.soft
                        : UdIconTone.neutral,
                  ),
                  trailing: _uploaded.contains(item.$1)
                      ? const UdBadge(label: 'Done', tone: UdTone.ok)
                      : null,
                  showChevron: !_uploaded.contains(item.$1),
                  onTap: _busy ? null : () => _upload(item.$1),
                ),
            ],
          ),
          const SizedBox(height: 18),
          UdButton(
            label: 'Submit vehicle for admin review',
            icon: Icons.fact_check_outlined,
            busy: _busy,
            onPressed: _busy || _uploaded.length < _requiredDocuments.length
                ? null
                : _submitVehicle,
          ),
          if (_uploaded.length < _requiredDocuments.length) ...[
            const SizedBox(height: 10),
            Text(
              '${_requiredDocuments.length - _uploaded.length} still to '
              'upload.',
              textAlign: TextAlign.center,
              style: AppType.small.copyWith(color: AppText.caption),
            ),
          ],
        ],
      );

  // ----------------------------------------------------------------- wiring

  Future<void> _createVehicle() async {
    if (!_formKey.currentState!.validate()) return;
    final year = int.tryParse(_year.text);
    if (year == null || year < 1980 || year > 2100) {
      setState(() => _error = 'Enter a valid vehicle year.');
      return;
    }
    await _run(() async {
      _created = await AppControllerScope.of(context).createLiveVehicle({
        'category': _category,
        'make': _make.text.trim(),
        'model': _model.text.trim(),
        'year': year,
        'registrationNumber': _registration.text.trim(),
        'colour': _colour.text.trim(),
        'passengerCapacity': _seats,
        'luggageCapacity': _luggage,
        'hasAirConditioning': _ac,
        'hasHeating': _heating,
        'isFourByFour': _fourByFour,
        'hasFirstAidKit': _firstAid,
        'hasFireExtinguisher': _fireExtinguisher,
        'hasSpareTyre': _spareTyre,
        'hasSnowChains': _snowChains,
        'hasChildSeat': _childSeat,
      });
    });
  }

  Future<void> _upload(String type) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    await _run(() async {
      // Vehicle photographs are the biggest files a Driver sends — four of
      // them, straight from the camera. Shrunk before they leave the phone.
      final file = await ImageCompressor.shrink(result.files.single);
      if (!mounted) return;
      await AppControllerScope.of(context)
          .uploadLiveVehicleDocument(_created!.id, type, file);
      _uploaded.add(type);
    });
  }

  Future<void> _submitVehicle() async {
    await _run(() async {
      _created =
          await AppControllerScope.of(context).submitLiveVehicle(_created!.id);
      if (!mounted) return;
      await showUdDialog<void>(
        context: context,
        title: 'Vehicle submitted',
        message: 'Current status: ${_created!.status}. The Admin verification '
            'team can now review it.',
        actions: [
          UdButton(
            label: 'Done',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The request could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A field-shaped button that opens a sheet — 58px, same border and radius as
/// [UdTextField], so it lines up with the five real fields under it.
///
/// It is not a read-only `UdTextField`: the value there would be a hint, and a
/// hint is painted in caption grey. "SUV" is an answer, not a placeholder.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.field),
        child: Container(
          height: AppSizes.field,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadii.all(AppRadii.field),
            border:
                Border.all(color: AppColors.borderStrong, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppText.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: AppType.body.copyWith(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: AppText.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.expand_more_rounded,
                  size: 22, color: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// A −/value/+ control small enough to sit at the right edge of a list row.
///
/// `UdStepper` is the full-width version — its own bordered box with the label
/// inside it. On this screen the label belongs to the row, so only the control
/// is wanted.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.label,
  });

  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Step(
          icon: Icons.remove_rounded,
          onTap: onDecrease,
          semanticLabel: 'Decrease $label',
        ),
        SizedBox(
          width: 42,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppType.listTitle.copyWith(
              fontSize: 17,
              color: AppText.primary,
            ),
          ),
        ),
        _Step(
          icon: Icons.add_rounded,
          onTap: onIncrease,
          semanticLabel: 'Increase $label',
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: AppRadii.all(12),
            border: Border.all(
              color: enabled ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? AppColors.navy : AppText.disabled,
          ),
        ),
      ),
    );
  }
}
