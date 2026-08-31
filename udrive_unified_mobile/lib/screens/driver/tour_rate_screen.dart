import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

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

  Future<void> _edit(Map<String, dynamic> vehicle) async {
    final perDay = TextEditingController(
      text: _text(vehicle['perDayRate']),
    );
    final perKm = TextEditingController(text: _text(vehicle['perKmRate']));
    final minimum = TextEditingController(text: _text(vehicle['minimumFare']));
    final notes = TextEditingController(text: '${vehicle['notes'] ?? ''}');
    var available = vehicle['availableForTour'] == true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${vehicle['label'] ?? vehicle['category'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: available,
                  onChanged: (value) =>
                      setSheetState(() => available = value),
                  title: Text(
                    _t('Available for tours', 'ٹور کے لیے دستیاب'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    _t(
                      'Turn this off and this vehicle never appears in a tour search.',
                      'یہ بند کریں تو یہ گاڑی ٹور تلاش میں نظر نہیں آئے گی۔',
                    ),
                    style: const TextStyle(fontSize: 11.5, height: 1.4),
                  ),
                ),
                const SizedBox(height: 6),
                _MoneyInput(
                  controller: perDay,
                  label: _t('Your price per day (PKR)', 'فی دن آپ کی قیمت'),
                ),
                const SizedBox(height: 10),
                _MoneyInput(
                  controller: minimum,
                  label: _t(
                    'Least you will accept for a tour (PKR)',
                    'ٹور کے لیے کم از کم قابلِ قبول رقم',
                  ),
                ),
                const SizedBox(height: 10),
                _MoneyInput(
                  controller: perKm,
                  label: _t(
                    'Per kilometre, if you price long transfers that way (optional)',
                    'فی کلومیٹر — اگر آپ لمبے سفر ایسے لگاتے ہیں (اختیاری)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  maxLength: 400,
                  decoration: InputDecoration(
                    labelText: _t(
                      'What your price includes',
                      'آپ کی قیمت میں کیا شامل ہے',
                    ),
                    hintText: _t(
                      'e.g. fuel and driver food included, tolls extra',
                      'مثلاً پٹرول اور ڈرائیور کا کھانا شامل، ٹول الگ',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton(
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
                  child: Text(_t('Save', 'محفوظ کریں')),
                ),
              ],
            ),
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
      appBar: AppBar(title: Text(_t('Tour rate', 'ٹور کا کرایہ'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: AppRadii.all(AppRadii.row),
              ),
              child: Text(
                _t(
                  'You set your own tour price. UDrive does not set it for you — '
                  'the city rate per kilometre does not apply to tours. '
                  'Customers see what drivers like you are asking, then make '
                  'their offer, and you answer with yours.',
                  'ٹور کی قیمت آپ خود مقرر کرتے ہیں۔ یوڈرائیو یہ آپ کے لیے طے نہیں '
                  'کرتا — شہر کا فی کلومیٹر ریٹ ٹور پر لاگو نہیں ہوتا۔ کسٹمر دیکھتے '
                  'ہیں کہ آپ جیسے ڈرائیور کیا مانگ رہے ہیں، پھر اپنی پیشکش کرتے ہیں، '
                  'اور آپ اپنی قیمت بتاتے ہیں۔',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppText.secondary,
                ),
              ),
            ),
            const SizedBox(height: 14),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
              )
            else if (_vehicles.isEmpty)
              Text(
                _t(
                  'Register a vehicle first, then set what you charge for tours.',
                  'پہلے گاڑی رجسٹر کریں، پھر ٹور کا کرایہ مقرر کریں۔',
                ),
                style: const TextStyle(color: AppText.secondary, height: 1.5),
              )
            else
              ..._vehicles.map(
                (vehicle) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RateCard(
                    vehicle: vehicle,
                    unsetLabel: _t('Not set', 'مقرر نہیں'),
                    offLabel: _t('Not offered for tours', 'ٹور کے لیے پیش نہیں'),
                    onTap: () => _edit(vehicle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoneyInput extends StatelessWidget {
  const _MoneyInput({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, prefixText: 'PKR '),
      );
}

class _RateCard extends StatelessWidget {
  const _RateCard({
    required this.vehicle,
    required this.unsetLabel,
    required this.offLabel,
    required this.onTap,
  });

  final Map<String, dynamic> vehicle;
  final String unsetLabel;
  final String offLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = vehicle['availableForTour'] == true;
    final perDay = vehicle['perDayRate'];
    final hasRate = perDay is num && perDay > 0;

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.all(AppRadii.panel),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.panel),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vehicle['label'] ?? ''}'.trim().isEmpty
                          ? '${vehicle['category'] ?? ''}'
                          : '${vehicle['label']}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      !available
                          ? offLabel
                          : hasRate
                              ? 'PKR ${(perDay as num).toStringAsFixed(0)} / day'
                              : unsetLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: available && hasRate
                            ? AppColors.secondary
                            : AppText.disabled,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppText.disabled),
            ],
          ),
        ),
      ),
    );
  }
}
