import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/vehicles/vehicle_usage_repository.dart';
import '../../core/widgets/ud_controls.dart';
import '../../core/widgets/ud_kit.dart';

/// D-52 — what renting this vehicle costs and requires.
///
/// Two rates, because renting a car here means one of two different things and
/// an owner may offer either or both:
///
///   * **with a driver** — the owner's own man drives. The customer hands over
///     nothing but money, and no identity documents are needed.
///   * **self-drive** — the customer drives, which is the path that asks for a
///     CNIC and a licence.
///
/// At least one must be set. An owner who will not hand the keys to a stranger
/// fills in "with driver" and leaves self-drive empty, and self-drive simply
/// never appears to the customer.
///
/// Deposit, minimum days and the daily kilometre limit are here because they are
/// exactly what gets argued about afterwards, and the time to agree them is
/// before the car leaves the yard.
///
/// Saving this does **not** put the vehicle out on rent. That is the switch on
/// the usage screen, deliberately a separate act: a Driver may want to work out
/// their pricing over a few days first.
class LiveRentSettingsScreen extends StatefulWidget {
  const LiveRentSettingsScreen({required this.vehicle, super.key});

  final VehicleUsage vehicle;

  @override
  State<LiveRentSettingsScreen> createState() => _LiveRentSettingsScreenState();
}

class _LiveRentSettingsScreenState extends State<LiveRentSettingsScreen> {
  late final VehicleUsageRepository _repository =
      VehicleUsageRepository(AppControllerScope.of(context).apiClient);

  late final TextEditingController _withDriver =
      TextEditingController(text: _money(widget.vehicle.rentWithDriverDaily));
  late final TextEditingController _selfDrive =
      TextEditingController(text: _money(widget.vehicle.rentSelfDriveDaily));
  late final TextEditingController _deposit =
      TextEditingController(text: _money(widget.vehicle.rentSecurityDeposit));
  late final TextEditingController _kmPerDay = TextEditingController(
      text: widget.vehicle.rentKmPerDay?.toString() ?? '');
  late final TextEditingController _pickup =
      TextEditingController(text: widget.vehicle.rentPickupPoint ?? '');

  late bool _withDriverOn = (widget.vehicle.rentWithDriverDaily ?? 0) > 0;
  late bool _selfDriveOn = (widget.vehicle.rentSelfDriveDaily ?? 0) > 0;
  late int _minimumDays = widget.vehicle.rentMinimumDays;
  late bool _fuelIncluded = widget.vehicle.rentFuelIncluded;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _withDriver.dispose();
    _selfDrive.dispose();
    _deposit.dispose();
    _kmPerDay.dispose();
    _pickup.dispose();
    super.dispose();
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  static String _money(double? value) =>
      value == null || value <= 0 ? '' : value.round().toString();

  double? _read(TextEditingController controller, bool enabled) {
    if (!enabled) return null;
    final value = double.tryParse(controller.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  Future<void> _save() async {
    final withDriver = _read(_withDriver, _withDriverOn);
    final selfDrive = _read(_selfDrive, _selfDriveOn);

    // Checked here as well as on the server, so the Driver is told before the
    // round trip rather than after it. The server still decides.
    if (withDriver == null && selfDrive == null) {
      setState(() => _error = _t(
            'Set at least one daily rate — with a driver, self-drive, or both.',
            'کم از کم ایک روزانہ کرایہ مقرر کریں — ڈرائیور کے ساتھ، خود '
                'چلائیں، یا دونوں۔',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _repository.setRentSettings(
        widget.vehicle.vehicleId,
        withDriverDaily: withDriver,
        selfDriveDaily: selfDrive,
        securityDeposit: _read(_deposit, true),
        minimumDays: _minimumDays,
        kmPerDay: int.tryParse(_kmPerDay.text.trim()),
        fuelIncluded: _fuelIncluded,
        pickupPoint: _pickup.text.trim().isEmpty ? null : _pickup.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on VehicleUsageRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _error = refusal.message;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('Rent settings', 'کرائے کی سیٹنگ'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 12, AppSizes.sidePadding, 40),
        children: [
          Text(
            '${widget.vehicle.name} · ${widget.vehicle.registrationNumber}',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            UdBanner(tone: UdTone.err, text: _error),
            const SizedBox(height: 14),
          ],

          UdSectionHeader(title: _t('How it goes out', 'کیسے جائے گی')),
          const SizedBox(height: 10),

          UdListGroup(
            children: [
              UdListRow(
                title: _t('With a driver', 'ڈرائیور کے ساتھ'),
                subtitle: _t(
                  'You or your driver drives. No customer documents needed.',
                  'آپ یا آپ کا ڈرائیور چلائے گا۔ کسٹمر کے کاغذات کی ضرورت نہیں۔',
                ),
                trailing: UdSwitch(
                  value: _withDriverOn,
                  onChanged: (value) => setState(() => _withDriverOn = value),
                  semanticLabel: 'With a driver',
                ),
              ),
              UdListRow(
                title: _t('Self-drive', 'خود چلائیں'),
                subtitle: _t(
                  'The customer drives, so their CNIC and licence are required.',
                  'کسٹمر خود چلائے گا، اس لیے اس کا شناختی کارڈ اور لائسنس '
                      'لازمی ہے۔',
                ),
                trailing: UdSwitch(
                  value: _selfDriveOn,
                  onChanged: (value) => setState(() => _selfDriveOn = value),
                  semanticLabel: 'Self-drive',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_withDriverOn) ...[
            _Money(
              controller: _withDriver,
              label: _t('With a driver, per day', 'ڈرائیور کے ساتھ، فی دن'),
            ),
            const SizedBox(height: 14),
          ],
          if (_selfDriveOn) ...[
            _Money(
              controller: _selfDrive,
              label: _t('Self-drive, per day', 'خود چلائیں، فی دن'),
            ),
            const SizedBox(height: 14),
          ],
          if (!_withDriverOn && !_selfDriveOn)
            UdBanner(
              tone: UdTone.warn,
              icon: Icons.info_outline_rounded,
              text: _t(
                'Both cannot be off — at least one way of renting has to stay.',
                'دونوں بند نہیں ہو سکتے — کرائے کا کم از کم ایک طریقہ رکھنا '
                    'ہوگا۔',
              ),
            ),

          const SizedBox(height: 10),
          UdSectionHeader(title: _t('Terms', 'شرائط')),
          const SizedBox(height: 10),

          _Money(
            controller: _deposit,
            label: _t('Security deposit', 'سیکیورٹی ڈیپازٹ'),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'Refundable. The customer sees it beside the price, not after '
              'booking.',
              'واپس ہونے والی رقم۔ کسٹمر کو قیمت کے ساتھ ہی دکھتی ہے، بکنگ کے '
                  'بعد نہیں۔',
            ),
            style: AppType.caption.copyWith(color: AppText.caption),
          ),
          const SizedBox(height: 16),

          UdStepper(
            label: _t('Minimum days', 'کم از کم دن'),
            value: _minimumDays,
            min: 1,
            max: 30,
            onChanged: (value) => setState(() => _minimumDays = value),
          ),
          const SizedBox(height: 16),

          UdTextField(
            controller: _kmPerDay,
            label: _t('Kilometres included per day', 'فی دن شامل کلومیٹر'),
            labelSuffix: 'km',
            icon: Icons.speed_rounded,
            hint: _t('Leave empty for unlimited', 'بے حد کے لیے خالی چھوڑیں'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 14),

          UdListGroup(
            children: [
              UdListRow(
                title: _t('Fuel included', 'پٹرول شامل'),
                subtitle: _fuelIncluded
                    ? _t('Included in the rent', 'کرائے میں شامل')
                    : _t("The customer's own", 'کسٹمر کا اپنا'),
                trailing: UdSwitch(
                  value: _fuelIncluded,
                  onChanged: (value) => setState(() => _fuelIncluded = value),
                  semanticLabel: 'Fuel included',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          UdTextField(
            controller: _pickup,
            label: _t('Where the car is collected', 'گاڑی کہاں سے ملے گی'),
            icon: Icons.place_outlined,
            hint: _t('Muzaffarabad bus stand', 'مظفرآباد بس اسٹینڈ'),
            maxLength: 200,
          ),
          const SizedBox(height: 20),

          UdButton.primary(
            label: _saving
                ? _t('Saving…', 'محفوظ ہو رہا ہے…')
                : _t('Save', 'محفوظ کریں'),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Saving does not put the vehicle out on rent. That is the switch '
              'on the usage screen.',
              'محفوظ کرنے سے گاڑی کرائے پر نہیں لگتی۔ وہ استعمال کی اسکرین کا '
                  'سوئچ ہے۔',
            ),
            style: AppType.caption.copyWith(color: AppText.caption),
          ),
        ],
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => UdTextField(
        controller: controller,
        label: label,
        labelSuffix: 'PKR',
        icon: Icons.payments_rounded,
        hint: '0',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );
}
