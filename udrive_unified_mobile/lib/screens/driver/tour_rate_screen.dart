import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// Where a Driver names their own price for touring.
///
/// The admin sets a rate per kilometre for city rides, and that is right for a
/// metered trip. A multi-day run through the mountains is not one: the driver
/// is away from home, feeding and housing themselves, on roads that punish a
/// vehicle. What that is worth is a judgement only the person driving can make,
/// so the platform does not make it for them.
///
/// Nothing here is charged automatically. It is what the driver publishes, so a
/// customer naming an offer starts from something real instead of guessing.
class TourRateScreen extends StatefulWidget {
  const TourRateScreen({super.key});

  @override
  State<TourRateScreen> createState() => _TourRateScreenState();
}

class _TourRateScreenState extends State<TourRateScreen> {
  List<Map<String, dynamic>> _vehicles = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final controller = AppControllerScope.of(context);
      final response = await controller.apiClient
          .getJson('/api/v1/driver/marketplace/tour-rates');
      final data = response['data'];
      if (!mounted) return;
      setState(() {
        _vehicles = data is List
            ? data
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : const [];
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

  /// D-34's editor — one vehicle's tour price.
  Future<void> _edit(Map<String, dynamic> vehicle) async {
    final perDay = TextEditingController(text: _text(vehicle['perDayRate']));
    final perKm = TextEditingController(text: _text(vehicle['perKmRate']));
    final minimum = TextEditingController(text: _text(vehicle['minimumFare']));
    final notes = TextEditingController(text: '${vehicle['notes'] ?? ''}');
    var available = vehicle['availableForTour'] == true;

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
                '${vehicle['label'] ?? vehicle['category'] ?? ''}',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 16),

              // Was a `SwitchListTile`. Its subtitle is the important half —
              // it says what turning this off actually does — so it keeps it.
              UdListGroup(
                children: [
                  UdListRow(
                    title: _t('Available for tours', 'ٹور کے لیے دستیاب'),
                    subtitle: _t(
                      'Turn this off and this vehicle never appears in a tour '
                      'search.',
                      'یہ بند کریں تو یہ گاڑی ٹور تلاش میں نظر نہیں آئے گی۔',
                    ),
                    trailing: UdSwitch(
                      value: available,
                      onChanged: (value) =>
                          setSheetState(() => available = value),
                      semanticLabel: 'Available for tours',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _MoneyInput(
                controller: perDay,
                label: _t('Your price per day', 'فی دن آپ کی قیمت'),
              ),
              const SizedBox(height: 14),
              _MoneyInput(
                controller: minimum,
                label: _t(
                  'Least you will accept for a tour',
                  'ٹور کے لیے کم از کم قابلِ قبول رقم',
                ),
              ),
              const SizedBox(height: 14),
              _MoneyInput(
                controller: perKm,
                label: _t('Per kilometre', 'فی کلومیٹر'),
                suffix: _t(
                  '(optional — if you price long transfers that way)',
                  '(اختیاری)',
                ),
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: notes,
                label: _t(
                  'What your price includes',
                  'آپ کی قیمت میں کیا شامل ہے',
                ),
                hint: _t(
                  'e.g. fuel and driver food included, tolls extra',
                  'مثلاً پٹرول اور ڈرائیور کا کھانا شامل، ٹول الگ',
                ),
                icon: Icons.notes_rounded,
                minLines: 3,
                maxLines: 4,
                maxLength: 400,
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: _t('Save', 'محفوظ کریں'),
                icon: Icons.save_rounded,
                onPressed: () async {
                  final ok = await _save(
                    vehicleId: '${vehicle['vehicleId']}',
                    perDay: _number(perDay.text),
                    perKm: _number(perKm.text),
                    minimum: _number(minimum.text),
                    notes: notes.text.trim(),
                    available: available,
                  );
                  if (ok && sheetContext.mounted) {
                    Navigator.pop(sheetContext, true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    perDay.dispose();
    perKm.dispose();
    minimum.dispose();
    notes.dispose();

    if (saved == true) await _load();
  }

  Future<bool> _save({
    required String vehicleId,
    required double? perDay,
    required double? perKm,
    required double? minimum,
    required String notes,
    required bool available,
  }) async {
    try {
      final controller = AppControllerScope.of(context);
      await controller.apiClient.putJson(
        '/api/v1/driver/marketplace/tour-rates/$vehicleId',
        {
          'perDayRate': perDay,
          'perKmRate': perKm,
          'minimumFare': minimum,
          'notes': notes.isEmpty ? null : notes,
          'availableForTour': available,
        },
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
      return false;
    }
  }

  static String _text(Object? value) {
    if (value is num && value > 0) return value.toStringAsFixed(0);
    return '';
  }

  static double? _number(String value) {
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: _t('Tour rate', 'ٹور کا کرایہ'),
        onBack: () => Navigator.pop(context),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
          children: [
            // The whole reason this screen exists, said once at the top.
            UdBanner(
              tone: UdTone.info,
              icon: Icons.price_change_outlined,
              text: _t(
                'You set your own tour price. UDrive does not set it for you — '
                'the city rate per kilometre does not apply to tours. '
                'Customers see what drivers like you are asking, then make '
                'their offer, and you answer with yours.',
                'ٹور کی قیمت آپ خود مقرر کرتے ہیں۔ یوڈرائیو یہ آپ کے لیے طے نہیں '
                'کرتا — شہر کا فی کلومیٹر ریٹ ٹور پر لاگو نہیں ہوتا۔ کسٹمر دیکھتے '
                'ہیں کہ آپ جیسے ڈرائیور کیا مانگ رہے ہیں، پھر اپنی پیشکش کرتے ہیں، '
                'اور آپ اپنی قیمت بتاتے ہیں۔',
              ),
            ),
            const SizedBox(height: 22),
            UdSectionHeader(title: _t('Your vehicles', 'آپ کی گاڑیاں')),
            const SizedBox(height: 12),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.navy),
                ),
              )
            else if (_error != null)
              UdEmptyState(
                icon: Icons.cloud_off_rounded,
                tone: UdTone.err,
                title: _t('Could not load rates', 'ریٹ لوڈ نہیں ہو سکے'),
                text: _error,
                action: UdButton.outline(
                  label: _t('Retry', 'دوبارہ کوشش'),
                  icon: Icons.refresh_rounded,
                  expand: false,
                  onPressed: _load,
                ),
              )
            else if (_vehicles.isEmpty)
              UdEmptyState(
                icon: Icons.directions_car_outlined,
                title: _t('No vehicle yet', 'ابھی کوئی گاڑی نہیں'),
                text: _t(
                  'Register a vehicle first, then set what you charge for '
                  'tours.',
                  'پہلے گاڑی رجسٹر کریں، پھر ٹور کا کرایہ مقرر کریں۔',
                ),
              )
            else
              UdListGroup(
                children: [
                  for (final vehicle in _vehicles)
                    _rateRow(vehicle),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// One vehicle's row: its name, and what it is asking.
  ///
  /// "Not set" and "Not offered for tours" are two different states and used
  /// to share one grey; the first is unfinished work, the second a choice.
  Widget _rateRow(Map<String, dynamic> vehicle) {
    final available = vehicle['availableForTour'] == true;
    final perDay = vehicle['perDayRate'];
    final hasRate = perDay is num && perDay > 0;

    final label = '${vehicle['label'] ?? ''}'.trim().isEmpty
        ? '${vehicle['category'] ?? ''}'
        : '${vehicle['label']}';

    return UdListRow(
      title: label,
      subtitle: !available
          ? _t('Not offered for tours', 'ٹور کے لیے پیش نہیں')
          : hasRate
              ? 'PKR ${(perDay as num).toStringAsFixed(0)} / day'
              : _t('Not set', 'مقرر نہیں'),
      leading: UdIconTile(
        icon: Icons.directions_car_filled_rounded,
        tone: available && hasRate ? UdIconTone.soft : UdIconTone.neutral,
      ),
      trailing: !available
          ? UdBadge(label: _t('Off', 'بند'), tone: UdTone.gray)
          : hasRate
              ? null
              : UdBadge(label: _t('Not set', 'مقرر نہیں'), tone: UdTone.warn),
      showChevron: available && hasRate,
      onTap: () => _edit(vehicle),
    );
  }
}

/// A PKR amount. Was a `TextField` with Material's `prefixText`, which the
/// kit's field does not have — the currency goes in the label instead, where
/// it is readable before the field has anything in it.
class _MoneyInput extends StatelessWidget {
  const _MoneyInput({
    required this.controller,
    required this.label,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) => UdTextField(
        controller: controller,
        label: label,
        labelSuffix: suffix ?? 'PKR',
        icon: Icons.payments_rounded,
        hint: '0',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );
}
