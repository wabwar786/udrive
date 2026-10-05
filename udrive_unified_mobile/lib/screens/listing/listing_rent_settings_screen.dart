import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/listings/listing_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/vehicles/vehicle_usage_repository.dart';
import '../../core/widgets/ud_kit.dart';
import 'rent_tour_kit.dart';

/// R4 — the rent rates and rules for one vehicle, and the rent switch.
///
/// Reads and writes through the existing vehicle-usage routes. Pops with the
/// saved [VehicleUsage] so the rent screen can refresh its header line.
class ListingRentSettingsScreen extends StatefulWidget {
  const ListingRentSettingsScreen({required this.vehicle, super.key});

  final ListingVehicle vehicle;

  @override
  State<ListingRentSettingsScreen> createState() =>
      _ListingRentSettingsScreenState();
}

class _ListingRentSettingsScreenState extends State<ListingRentSettingsScreen> {
  VehicleUsageRepository? _repository;

  final TextEditingController _withDriver = TextEditingController();
  final TextEditingController _selfDrive = TextEditingController();
  final TextEditingController _deposit = TextEditingController();
  final TextEditingController _pickup = TextEditingController();

  int _minimumDays = 1;

  /// Null = no limit.
  int? _kmPerDay = 250;
  bool _fuelIncluded = false;
  bool _rentOn = false;

  VehicleUsage? _usage;
  bool _loading = true;
  bool _saving = false;
  bool _switching = false;
  String? _error;

  static const _minimumOptions = [1, 2, 3, 7];
  static const _kmOptions = <int?>[150, 250, 400, null];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository =
          VehicleUsageRepository(AppControllerScope.of(context).apiClient);
      _prefill(null);
      _load();
    }
  }

  @override
  void dispose() {
    _withDriver.dispose();
    _selfDrive.dispose();
    _deposit.dispose();
    _pickup.dispose();
    super.dispose();
  }

  static String _money(double? value) =>
      value == null || value <= 0 ? '' : value.round().toString();

  /// From the server's usage when there is one, else from the listing.
  void _prefill(VehicleUsage? usage) {
    final v = widget.vehicle;
    _withDriver.text = _money(usage?.rentWithDriverDaily ?? v.withDriverDaily);
    _selfDrive.text = _money(usage?.rentSelfDriveDaily ?? v.selfDriveDaily);
    _deposit.text = _money(usage?.rentSecurityDeposit);
    _pickup.text = usage?.rentPickupPoint ?? v.pickupPoint ?? '';
    if (usage != null) {
      _minimumDays = usage.rentMinimumDays;
      _kmPerDay = usage.rentKmPerDay;
      _fuelIncluded = usage.rentFuelIncluded;
      _rentOn = usage.availableForRent;
    } else {
      _rentOn = v.availableForRent;
    }
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await repository.list();
      if (!mounted) return;
      VehicleUsage? mine;
      for (final usage in all) {
        if (usage.vehicleId == widget.vehicle.id) mine = usage;
      }
      setState(() {
        _usage = mine;
        if (mine != null) _prefill(mine);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  double? _number(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  bool get _hasRate =>
      _number(_withDriver) != null || _number(_selfDrive) != null;

  Future<void> _toggleRent(bool value) async {
    final repository = _repository;
    if (repository == null || _switching) return;
    setState(() {
      _switching = true;
      _error = null;
    });
    try {
      final usage = await repository.setUsage(widget.vehicle.id, rent: value);
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _rentOn = usage.availableForRent;
        _switching = false;
      });
    } on VehicleUsageRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _error = refusal.message;
        _switching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _switching = false;
      });
    }
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _saving) return;
    if (!_hasRate) {
      setState(() => _error = 'Set at least one daily rate.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pickup = _pickup.text.trim();
      final usage = await repository.setRentSettings(
        widget.vehicle.id,
        withDriverDaily: _number(_withDriver),
        selfDriveDaily: _number(_selfDrive),
        securityDeposit: _number(_deposit),
        minimumDays: _minimumDays,
        kmPerDay: _kmPerDay,
        fuelIncluded: _fuelIncluded,
        pickupPoint: pickup.isEmpty ? null : pickup,
      );
      if (!mounted) return;
      Navigator.pop(context, usage);
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

  Widget _overline(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppType.caption.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
            color: AppText.secondary,
          ),
        ),
      );

  /// A wrap of chips: (label, selected, onPick).
  Widget _pills(List<(String, bool, VoidCallback)> options) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            UdChip(
              label: option.$1,
              selected: option.$2,
              onTap: () => setState(option.$3),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final money = [FilteringTextInputFormatter.digitsOnly];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          RentNavyHeader(
            title: 'Rates & rules',
            subtitle: v.year > 0 ? '${v.name} ${v.year}' : v.name,
            onBack: () => Navigator.pop(context, _usage),
          ),
          Expanded(
            child: _loading && _usage == null
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.navy),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      if (_error != null) ...[
                        UdBanner(tone: UdTone.err, text: _error),
                        const SizedBox(height: 12),
                      ],
                      UdListGroup(
                        children: [
                          UdListRow(
                            title: 'Open for rent',
                            subtitle: _rentOn
                                ? 'Customers can book this car'
                                : 'Hidden from the rental list',
                            trailing: UdSwitch(
                              value: _rentOn,
                              semanticLabel: 'Open for rent',
                              onChanged:
                                  _switching || _usage == null
                                      ? null
                                      : _toggleRent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _overline('WITH DRIVER / DAY'),
                      UdTextField(
                        controller: _withDriver,
                        hint: 'PKR — leave empty if you don\'t offer it',
                        keyboardType: TextInputType.number,
                        inputFormatters: money,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _overline('SELF-DRIVE / DAY'),
                      UdTextField(
                        controller: _selfDrive,
                        hint: 'PKR — leave empty if you don\'t offer it',
                        keyboardType: TextInputType.number,
                        inputFormatters: money,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _overline('DEPOSIT (SELF-DRIVE)'),
                      UdTextField(
                        controller: _deposit,
                        hint: 'PKR — paid to you in cash at pickup',
                        keyboardType: TextInputType.number,
                        inputFormatters: money,
                      ),
                      const SizedBox(height: 18),
                      _overline('MINIMUM DAYS'),
                      _pills([
                        for (final d in _minimumOptions)
                          ('$d', _minimumDays == d, () => _minimumDays = d),
                      ]),
                      const SizedBox(height: 18),
                      _overline('KM PER DAY'),
                      _pills([
                        for (final km in _kmOptions)
                          (
                            km == null ? 'No limit' : '$km',
                            _kmPerDay == km,
                            () => _kmPerDay = km,
                          ),
                      ]),
                      const SizedBox(height: 18),
                      _overline('FUEL'),
                      _pills([
                        (
                          'Customer pays',
                          !_fuelIncluded,
                          () => _fuelIncluded = false,
                        ),
                        ('Included', _fuelIncluded, () => _fuelIncluded = true),
                      ]),
                      const SizedBox(height: 18),
                      _overline('PICKUP POINT'),
                      UdTextField(
                        controller: _pickup,
                        hint: 'e.g. Chattar Klas, near the petrol pump',
                        textCapitalization: TextCapitalization.sentences,
                      ),
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
                label: 'Save',
                busy: _saving,
                onPressed: _loading || !_hasRate ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
