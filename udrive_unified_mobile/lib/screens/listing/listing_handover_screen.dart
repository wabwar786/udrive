import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/money.dart';
import '../../core/network/api_config.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'rent_tour_kit.dart';

/// R3 — handing the car over, or taking it back.
///
/// [phase] is `handover` or `return`. Both take the same four photos, the
/// odometer and the fuel; handover also checks the person and the deposit.
/// Both sets stay with the booking, side by side, as proof of the car's
/// condition. Pops `true` once the server has accepted it.
class ListingHandoverScreen extends StatefulWidget {
  const ListingHandoverScreen({
    required this.booking,
    required this.phase,
    super.key,
  });

  final RentalBooking booking;

  /// `handover` or `return`.
  final String phase;

  @override
  State<ListingHandoverScreen> createState() => _ListingHandoverScreenState();
}

class _ListingHandoverScreenState extends State<ListingHandoverScreen> {
  RentalRepository? _repository;

  late RentalConditionPhotos _photos = _isReturn
      ? widget.booking.returnPhotos
      : widget.booking.handoverPhotos;

  /// What was picked on this phone, so the thumbnail shows at once.
  final Map<String, Uint8List> _local = {};
  final Set<String> _uploading = {};

  final TextEditingController _km = TextEditingController();
  String? _fuel;

  bool _identity = false;
  bool _licence = false;
  bool _deposit = false;

  bool _busy = false;
  String? _error;

  static const _fuels = <(String, String)>[
    ('Quarter', '¼'),
    ('Half', '½'),
    ('ThreeQuarters', '¾'),
    ('Full', 'Full'),
  ];

  static const _sideLabels = <String, String>{
    'front': 'Front',
    'back': 'Back',
    'left': 'Left',
    'right': 'Right',
  };

  bool get _isReturn => widget.phase == 'return';

  /// Licence and deposit only matter when the customer drives themselves.
  bool get _asksLicence => widget.booking.isSelfDrive;
  bool get _asksDeposit => widget.booking.securityDeposit > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository ??= RentalRepository(AppControllerScope.of(context).apiClient);
  }

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  int? get _kmValue => int.tryParse(_km.text.trim());

  bool get _checksDone =>
      _isReturn ||
      (_identity && (!_asksLicence || _licence) && (!_asksDeposit || _deposit));

  bool get _ready =>
      _photos.complete &&
      _uploading.isEmpty &&
      (_kmValue ?? 0) > 0 &&
      _fuel != null &&
      _checksDone &&
      !_busy;

  Future<void> _pickPhoto(String side) async {
    final repository = _repository;
    if (repository == null || _uploading.contains(side)) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    final file = files.first;

    setState(() {
      _uploading.add(side);
      _error = null;
      final bytes = file.bytes;
      if (bytes != null) _local[side] = bytes;
    });
    try {
      final url = await repository.uploadConditionPhoto(
        widget.booking.id,
        widget.phase,
        side,
        file,
      );
      if (!mounted) return;
      setState(() {
        _photos = _photos.withSide(side, url);
        _uploading.remove(side);
      });
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _local.remove(side);
        _uploading.remove(side);
        _error = refusal.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _local.remove(side);
        _uploading.remove(side);
        _error = '$error';
      });
    }
  }

  Future<void> _submit() async {
    final repository = _repository;
    final km = _kmValue;
    final fuel = _fuel;
    if (repository == null || km == null || fuel == null || !_ready) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isReturn) {
        await repository.markReturned(widget.booking.id,
            odometerKm: km, fuel: fuel);
      } else {
        await repository.handOver(
          widget.booking.id,
          odometerKm: km,
          fuel: fuel,
          identityChecked: _identity,
          licenceSeen: _asksLicence && _licence,
          depositReceived: _asksDeposit && _deposit,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = refusal.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final overline = AppType.caption.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      letterSpacing: .4,
      color: AppText.secondary,
    );
    final handover = b.handover;
    final km = _kmValue;
    final kmBelow = _isReturn &&
        handover != null &&
        km != null &&
        km > 0 &&
        km < handover.odometerKm;

    var step = 0;
    String heading(String text) {
      step += 1;
      return '$step · $text';
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          RentNavyHeader(
            title: _isReturn ? 'Take the car back' : 'Hand over the car',
            subtitle:
                '${b.counterpartName} · ${rentRange(b.startDate, b.endDate)}',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (_error != null) ...[
                  UdBanner(tone: UdTone.err, text: _error),
                  const SizedBox(height: 14),
                ],
                if (!_isReturn) ...[
                  Text(heading('CHECK THE PERSON'), style: overline),
                  const SizedBox(height: 8),
                  _CheckRow(
                    value: _identity,
                    text: 'Face matches the selfie and CNIC',
                    onChanged: (v) => setState(() => _identity = v),
                  ),
                  if (_asksLicence)
                    _CheckRow(
                      value: _licence,
                      text: 'Original licence seen',
                      onChanged: (v) => setState(() => _licence = v),
                    ),
                  if (_asksDeposit)
                    _CheckRow(
                      value: _deposit,
                      text:
                          'Deposit ${Money.amount(b.securityDeposit)} received',
                      onChanged: (v) => setState(() => _deposit = v),
                    ),
                  const SizedBox(height: 16),
                ],
                Text(heading('CAR PHOTOS (4 SIDES)'), style: overline),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.4,
                  children: [
                    for (final side in RentalConditionPhotos.sides)
                      _PhotoSlot(
                        label: _sideLabels[side] ?? side,
                        url: _photos[side],
                        bytes: _local[side],
                        uploading: _uploading.contains(side),
                        onTap: _busy ? null : () => _pickPhoto(side),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved with the booking — proof of the car\'s condition.',
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(heading('METER & FUEL'), style: overline),
                const SizedBox(height: 8),
                if (_isReturn && handover != null) ...[
                  UdBanner(
                    tone: UdTone.info,
                    icon: Icons.compare_arrows_rounded,
                    text: 'At handover: '
                        '${Money.plain(handover.odometerKm)} km · fuel '
                        '${handover.fuelLabel}',
                  ),
                  const SizedBox(height: 10),
                ],
                UdTextField(
                  controller: _km,
                  label: 'Odometer km',
                  hint: 'e.g. 45210',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  helper: kmBelow
                      ? 'Lower than at handover — check the reading.'
                      : (_isReturn && handover != null && km != null &&
                              km >= handover.odometerKm)
                          ? '${Money.plain(km - handover.odometerKm)} km '
                              'driven'
                          : null,
                ),
                const SizedBox(height: 12),
                const UdLabel('Fuel'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < _fuels.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _FuelOption(
                          label: _fuels[i].$2,
                          selected: _fuel == _fuels[i].$1,
                          onTap: () => setState(() => _fuel = _fuels[i].$1),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!_isReturn) ...[
                  const SizedBox(height: 12),
                  Text(
                    'At return the same steps run again — photos, km and '
                    'fuel — and both sets sit side by side in the booking.',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: UdButton.primary(
                label: _isReturn ? 'Car returned' : 'Car handed over',
                busy: _busy,
                onPressed: _ready ? _submit : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.value,
    required this.text,
    required this.onChanged,
  });

  final bool value;
  final String text;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: UdCheckboxRow(
          value: value,
          onChanged: onChanged,
          semanticLabel: text,
          child: Text(
            text,
            style: AppType.body2.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.primary,
            ),
          ),
        ),
      );
}

/// One side of the car: dashed to add, the picture once taken.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.label,
    required this.url,
    required this.bytes,
    required this.uploading,
    required this.onTap,
  });

  final String label;
  final String? url;
  final Uint8List? bytes;
  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final done = url != null;
    final link = ApiConfig.absoluteUrl(url);
    final Widget placeholder = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.photo_camera_outlined,
            size: 26,
            color: done ? AppColors.brandInk : AppColors.navy,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
        ],
      ),
    );

    Widget picture;
    if (bytes != null) {
      picture = Image.memory(bytes!, fit: BoxFit.cover, cacheWidth: 400);
    } else if (link.isNotEmpty) {
      picture = Image.network(
        link,
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } else {
      picture = placeholder;
    }

    return Semantics(
      button: true,
      label: done ? '$label photo taken. Tap to retake' : 'Add $label photo',
      child: Material(
        color: done ? AppColors.brandWash : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(14),
          side: BorderSide(
            color: done ? AppColors.limeLine : AppColors.borderStrong,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: uploading ? null : onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              if (done || bytes != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: RentTag(
                    label,
                    background: AppColors.background,
                    ink: AppText.primary,
                  ),
                ),
              if (uploading)
                const ColoredBox(
                  color: AppTint.inkVeil,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.brand,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FuelOption extends StatelessWidget {
  const _FuelOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Fuel $label',
      child: Material(
        color: selected ? AppColors.navy : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(12),
          side: BorderSide(
            color: selected ? AppColors.navy : AppColors.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppType.listTitle.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: selected ? AppText.onInk : AppText.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
