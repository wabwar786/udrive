import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/media/image_compressor.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';

/// Driver sign-up, in four steps.
///
/// It used to be two long screens — every document on one, every vehicle field
/// on another — and people abandoned them. A form that shows twenty questions
/// at once reads as an hour of work whether it is or not, and there is no way
/// to tell how far through you are.
///
/// Four steps with a progress bar is the same work, and looks finishable:
/// yourself, your licence, your CNIC, your vehicle. Each is one subject, and a
/// person who has their licence in hand can do step two and come back.
///
/// Nothing is submitted until the last step. A half-filled profile in the
/// reviewers' queue wastes their time and the driver's.
class DriverSignUpScreen extends StatefulWidget {
  const DriverSignUpScreen({required this.vehicleCategory, super.key});

  /// Car, Motorcycle or Rickshaw, chosen before this screen opens.
  ///
  /// It decides what the vehicle step asks for, and it is a decision people can
  /// make instantly — so it is asked first, on its own, rather than buried at
  /// step four next to the number plate.
  final String vehicleCategory;

  @override
  State<DriverSignUpScreen> createState() => _DriverSignUpScreenState();
}

class _DriverSignUpScreenState extends State<DriverSignUpScreen> {
  final _page = PageController();
  int _step = 0;
  bool _busy = false;
  String? _error;

  // Step 1 — who you are.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  DateTime? _dateOfBirth;

  // Step 2 — your licence.
  final _licenceNumber = TextEditingController();
  DateTime? _licenceExpiry;

  // Step 3 — your CNIC.
  final _cnic = TextEditingController();

  // Step 4 — your vehicle.
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();

  /// Photographs taken so far, by document type.
  ///
  /// Held in memory until the last step rather than uploaded as they are
  /// picked. Someone who abandons at step three should not leave three
  /// orphaned files and a half-made profile behind them.
  final Map<String, PlatformFile> _files = {};

  @override
  void dispose() {
    _page.dispose();
    for (final controller in [
      _firstName, _lastName, _licenceNumber, _cnic,
      _make, _model, _colour, _plate, _year,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // --------------------------------------------------------------- steps

  static const _titles = [
    'Personal information',
    'Driver licence',
    'CNIC',
    'Vehicle information',
  ];

  /// Whether the current step has everything it needs.
  ///
  /// Checked per step rather than only at the end, so nobody reaches step four
  /// and is sent back to step one for a missing date.
  bool get _stepComplete => switch (_step) {
        0 => _firstName.text.trim().isNotEmpty &&
            _lastName.text.trim().isNotEmpty &&
            _dateOfBirth != null &&
            _files.containsKey('SELFIE'),
        1 => _licenceNumber.text.trim().isNotEmpty &&
            _licenceExpiry != null &&
            _files.containsKey('DRIVING_LICENCE') &&
            _files.containsKey('DRIVING_LICENCE_BACK'),
        2 => _cnic.text.trim().length >= 13 &&
            _files.containsKey('CNIC_FRONT') &&
            _files.containsKey('CNIC_BACK') &&
            _files.containsKey('SELFIE_WITH_CNIC'),
        _ => _make.text.trim().isNotEmpty &&
            _model.text.trim().isNotEmpty &&
            _colour.text.trim().isNotEmpty &&
            _plate.text.trim().isNotEmpty &&
            (int.tryParse(_year.text.trim()) ?? 0) >= 1980 &&
            _files.containsKey('VEHICLE_FRONT') &&
            _files.containsKey('REGISTRATION_BOOK'),
      };

  Future<void> _pick(String type) async {
    // `FilePicker.pickFiles`, not `FilePicker.platform.pickFiles`.
    //
    // This project's file_picker exposes the static form. The instance form
    // has now broken the build twice — once in rev 73 and again here — so
    // `tool/check_imports.py` fails on it rather than leaving the note to be
    // read by whoever happens to open the right file.
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    // Shrunk here, once, rather than at upload time. A driver who replaces a
    // photograph three times should not be re-compressing the first two.
    final file = await ImageCompressor.shrink(picked.files.single);
    if (!mounted) return;
    setState(() => _files[type] = file);
  }

  Future<void> _pickDate({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onPicked(picked);
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step < 3) {
      setState(() => _step++);
      _page.animateToPage(
        _step,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _submit();
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step--);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// Sends everything, in the order the server needs it.
  ///
  /// Profile first, because documents attach to it; then the driver's
  /// photographs; then the vehicle, then its papers. A failure part-way leaves
  /// what succeeded in place — the driver reopens the flow and finishes rather
  /// than starting again.
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final controller = AppControllerScope.of(context);

    try {
      await controller.saveDriverProfile({
        'fullName': '${_firstName.text.trim()} ${_lastName.text.trim()}',
        'cnicNumber': _cnic.text.trim(),
        'drivingLicenceNumber': _licenceNumber.text.trim(),
        'drivingLicenceExpiry': _iso(_licenceExpiry),
        'dateOfBirth': _iso(_dateOfBirth),
        // Address and emergency contact are not sent at all.
        //
        // They are not asked for in these four steps, and empty strings were
        // worse than omitting them: the endpoint had them as `[Required]`,
        // which rejects "" exactly as it rejects null, so every submission
        // failed. They are optional server-side now and collected in profile
        // settings.
      });

      for (final entry in _files.entries) {
        if (entry.key.startsWith('VEHICLE') ||
            entry.key.startsWith('REGISTRATION')) {
          continue;
        }
        await controller.uploadDriverDocument(entry.key, entry.value);
      }

      final vehicle = await controller.createLiveVehicle({
        'category': widget.vehicleCategory,
        'make': _make.text.trim(),
        'model': _model.text.trim(),
        'year': int.parse(_year.text.trim()),
        'registrationNumber': _plate.text.trim().toUpperCase(),
        'colour': _colour.text.trim(),
        // Sensible for the category, and editable later. Asking a motorcycle
        // rider how many suitcases it takes is a question with no useful
        // answer, and five more fields is how a four-step form becomes six.
        'passengerCapacity': _defaultSeats,
        'luggageCapacity': 0,
        'hasAirConditioning': widget.vehicleCategory == 'Car',
        'hasHeating': false,
        'isFourByFour': false,
        'hasFirstAidKit': false,
        'hasFireExtinguisher': false,
        'hasSpareTyre': false,
        'hasSnowChains': false,
        'hasChildSeat': false,
      });
      final vehicleId = vehicle.id;

      for (final entry in _files.entries) {
        if (!entry.key.startsWith('VEHICLE') &&
            !entry.key.startsWith('REGISTRATION')) {
          continue;
        }
        await controller.uploadLiveVehicleDocument(
            vehicleId, entry.key, entry.value);
      }

      await controller.submitDriverProfile();
      if (!mounted) return;

      // Say what happens next, and how long it takes.
      //
      // It used to close the screen and return to a menu, which looks
      // identical to the screen having crashed — there was nothing to tell a
      // driver whether an hour of photographing documents had worked. People
      // were closing and reopening the app to find out.
      await showUdDialog<void>(
        context: context,
        barrierDismissible: false,
        title: 'Sent for review',
        message: 'Our team checks new registrations within 24 hours. You will '
            'see the result here, and we will tell you if anything needs to '
            'be sent again.\n\n'
            'You can close the app — nothing is lost.',
        content: const Center(
          child: UdIconTile(
            icon: Icons.check_circle_rounded,
            tone: UdIconTone.soft,
            size: UdIconTileSize.lg,
          ),
        ),
        actions: [
          Builder(
            builder: (dialogContext) => UdButton.primary(
              label: 'Done',
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
        ],
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // A pushed page, so it keeps its own Scaffold and draws its own bar.
      //
      // The two controls now match what they do: the arrow goes back a step
      // (and out of the form from step one), the cross leaves the form. Both
      // existed before; the leading one was a cross that behaved like a back
      // arrow.
      appBar: UdTopBar(
        title: _titles[_step],
        onBack: _busy ? null : _back,
        divider: true,
        actions: [
          UdIconButton(
            icon: Icons.close_rounded,
            variant: UdIconButtonVariant.soft,
            tooltip: 'Leave sign-up',
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _personalStep(),
                _licenceStep(),
                _cnicStep(),
                _vehicleStep(),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 0, AppSizes.sidePadding, 12),
              child: UdBanner(
                tone: UdTone.err,
                icon: Icons.error_outline_rounded,
                text: _error!,
              ),
            ),
          _footer(),
        ],
      ),
    );
  }

  Widget _footer() {
    return UdBottomBar(
      children: [
        Row(
          children: [
            Text(
              'Step ${_step + 1} of 4',
              style: AppType.listTitle.copyWith(
                fontSize: 16,
                color: AppText.primary,
              ),
            ),
            const Spacer(),
            Text(
              _titles[_step],
              style: AppType.small.copyWith(color: AppText.secondary),
            ),
          ],
        ),
        // Segments, not a number alone. "3 of 4" says where you are; the bar
        // says how much is left, which is the part that decides whether
        // someone carries on.
        UdSteps(total: 4, current: _step),
        UdButtonRow(
          children: [
            if (_step > 0)
              UdButton.outline(
                label: 'Back',
                icon: Icons.chevron_left_rounded,
                onPressed: _busy ? null : _back,
              ),
            UdButton.primary(
              label: _step == 3 ? 'Submit' : 'Next',
              trailingIcon: Icons.chevron_right_rounded,
              busy: _busy,
              // Disabled until the step is complete, rather than allowing Next
              // and complaining afterwards. The person can see what is missing
              // on the screen in front of them.
              onPressed: _stepComplete ? _next : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _page1Body(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 18, AppSizes.sidePadding, 24),
        children: children,
      );

  Widget _personalStep() => _page1Body([
        _StepIntro(
          icon: Icons.person_rounded,
          title: 'Who are you?',
          text: 'Your name and a clear picture of your face. This is what a '
              'customer sees before they get in.',
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 160,
          child: _PhotoSlot(
            label: 'Personal picture',
            file: _files['SELFIE'],
            onTap: () => _pick('SELFIE'),
            onClear: () => setState(() => _files.remove('SELFIE')),
          ),
        ),
        const SizedBox(height: 22),
        _Field(label: 'First name', controller: _firstName, onChanged: _touch),
        _Field(label: 'Last name', controller: _lastName, onChanged: _touch),
        _DateField(
          label: 'Date of birth',
          value: _dateOfBirth,
          onTap: () => _pickDate(
            // Opens at eighteen years ago rather than today: nobody signing up
            // to drive was born this morning, and scrolling back through two
            // hundred months is a reason to give up.
            initial: _dateOfBirth ??
                DateTime.now().subtract(const Duration(days: 365 * 25)),
            first: DateTime(1940),
            last: DateTime.now().subtract(const Duration(days: 365 * 18)),
            onPicked: (date) => setState(() => _dateOfBirth = date),
          ),
        ),
      ]);

  Widget _licenceStep() => _page1Body([
        _StepIntro(
          icon: Icons.badge_rounded,
          title: 'Your driving licence',
          text: 'Both sides, and the number and expiry exactly as printed.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _PhotoSlot(
                label: 'Driver licence',
                file: _files['DRIVING_LICENCE'],
                onTap: () => _pick('DRIVING_LICENCE'),
                onClear: () =>
                    setState(() => _files.remove('DRIVING_LICENCE')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PhotoSlot(
                label: 'Driver licence (back)',
                file: _files['DRIVING_LICENCE_BACK'],
                onTap: () => _pick('DRIVING_LICENCE_BACK'),
                onClear: () =>
                    setState(() => _files.remove('DRIVING_LICENCE_BACK')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Field(
          label: 'Licence number',
          controller: _licenceNumber,
          onChanged: _touch,
          capitals: true,
        ),
        _DateField(
          label: 'Expiration date',
          value: _licenceExpiry,
          onTap: () => _pickDate(
            initial: _licenceExpiry ??
                DateTime.now().add(const Duration(days: 365)),
            // Never in the past. An expired licence is not a date to record,
            // it is a reason the person cannot drive yet.
            first: DateTime.now(),
            last: DateTime.now().add(const Duration(days: 365 * 20)),
            onPicked: (date) => setState(() => _licenceExpiry = date),
          ),
        ),
      ]);

  Widget _cnicStep() => _page1Body([
        _StepIntro(
          icon: Icons.credit_card_rounded,
          title: 'Your CNIC',
          text: 'Front, back, and one photo of you holding it. All three are '
              'needed before an account can be approved.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _PhotoSlot(
                label: 'CNIC (front side)',
                file: _files['CNIC_FRONT'],
                onTap: () => _pick('CNIC_FRONT'),
                onClear: () => setState(() => _files.remove('CNIC_FRONT')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PhotoSlot(
                label: 'CNIC (back side)',
                file: _files['CNIC_BACK'],
                onTap: () => _pick('CNIC_BACK'),
                onClear: () => setState(() => _files.remove('CNIC_BACK')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PhotoSlot(
                label: 'Selfie with CNIC',
                file: _files['SELFIE_WITH_CNIC'],
                onTap: () => _pick('SELFIE_WITH_CNIC'),
                onClear: () =>
                    setState(() => _files.remove('SELFIE_WITH_CNIC')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Field(
          label: 'ID number',
          controller: _cnic,
          onChanged: _touch,
          keyboard: TextInputType.number,
          helper: '13 digits, no dashes.',
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
        ),
      ]);

  Widget _vehicleStep() => _page1Body([
        _StepIntro(
          icon: Icons.directions_car_rounded,
          title: 'Your ${widget.vehicleCategory.toLowerCase()}',
          text: 'The vehicle itself, its registration book, and the details on '
              'the number plate.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _PhotoSlot(
                label: 'Photo of your vehicle',
                file: _files['VEHICLE_FRONT'],
                onTap: () => _pick('VEHICLE_FRONT'),
                onClear: () => setState(() => _files.remove('VEHICLE_FRONT')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PhotoSlot(
                label: 'Registration certificate',
                file: _files['REGISTRATION_BOOK'],
                onTap: () => _pick('REGISTRATION_BOOK'),
                onClear: () =>
                    setState(() => _files.remove('REGISTRATION_BOOK')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PhotoSlot(
                label: 'Registration (back)',
                file: _files['REGISTRATION_BOOK_BACK'],
                onTap: () => _pick('REGISTRATION_BOOK_BACK'),
                onClear: () =>
                    setState(() => _files.remove('REGISTRATION_BOOK_BACK')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Field(label: 'Vehicle brand', controller: _make, onChanged: _touch),
        _Field(label: 'Vehicle model', controller: _model, onChanged: _touch),
        _Field(label: 'Vehicle colour', controller: _colour, onChanged: _touch),
        _Field(
          label: 'Number plate',
          controller: _plate,
          onChanged: _touch,
          capitals: true,
        ),
        _Field(
          label: 'Production year',
          controller: _year,
          onChanged: _touch,
          keyboard: TextInputType.number,
          helper: '1980 or later.',
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
        ),
      ]);

  /// Rebuilds so the Next button can enable itself as fields are filled.
  void _touch(String _) => setState(() {});

  /// Seats the category implies, rather than a question nobody needs asked.
  int get _defaultSeats => switch (widget.vehicleCategory) {
        'Motorcycle' => 1,
        'Rickshaw' => 3,
        'Coster' => 22,
        _ => 4,
      };

  static String? _iso(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';
}

/// What this step is for, in one line, before the fields.
class _StepIntro extends StatelessWidget {
  const _StepIntro({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UdIconTile(icon: icon, tone: UdIconTone.soft),
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
                const SizedBox(height: 4),
                Text(
                  text,
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
              ],
            ),
          ),
        ],
      );
}

/// A photograph slot: tap to add, cross to remove.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.label,
    required this.file,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final PlatformFile? file;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bytes = file?.bytes;
    final filled = bytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: onTap,
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: filled ? AppColors.background : AppColors.surface,
                    borderRadius: AppRadii.all(AppRadii.field),
                    // A dashed-looking empty slot reads as "put something
                    // here"; a filled one is just the photograph.
                    border: Border.all(
                      color: filled
                          ? AppColors.border
                          : AppColors.borderStrong,
                      width: 1.5,
                    ),
                  ),
                  child: filled
                      ? Image.memory(bytes, fit: BoxFit.cover)
                      : const Icon(Icons.add_a_photo_outlined,
                          size: 26, color: AppText.secondary),
                ),
              ),
            ),
            if (filled)
              Positioned(
                top: -8,
                right: -8,
                child: GestureDetector(
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.background, width: 2.5),
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: AppColors.brand),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          label,
          maxLines: 2,
          style: AppType.caption.copyWith(
            fontSize: 13,
            color: filled ? AppText.primary : AppText.secondary,
          ),
        ),
      ],
    );
  }
}

/// A labelled field. The label sits above the box, where it stays readable
/// once something has been typed — which matters on a form somebody may come
/// back to after a day.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.keyboard,
    this.formatters,
    this.helper,
    this.capitals = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final String? helper;
  final bool capitals;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: UdTextField(
          controller: controller,
          label: label,
          helper: helper,
          onChanged: onChanged,
          keyboardType: keyboard,
          inputFormatters: formatters,
          textCapitalization: capitals
              ? TextCapitalization.characters
              : TextCapitalization.words,
        ),
      );
}

/// A date, in the same shape as a field so the form reads as one thing.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            UdLabel(label),
            const SizedBox(height: 8),
            Material(
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
                    border: Border.all(
                        color: AppColors.borderStrong, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 22, color: AppText.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          value == null
                              ? 'Select'
                              : '${value!.day.toString().padLeft(2, '0')}'
                                  '.${value!.month.toString().padLeft(2, '0')}'
                                  '.${value!.year}',
                          style: AppType.body.copyWith(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: value == null
                                ? AppText.caption
                                : AppText.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.chevron_right_rounded,
                          size: 22, color: AppText.caption),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
