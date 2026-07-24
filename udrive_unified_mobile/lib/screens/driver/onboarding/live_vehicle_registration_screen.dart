import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../models/auth_models.dart';

class LiveVehicleRegistrationScreen extends StatefulWidget {
  const LiveVehicleRegistrationScreen({super.key});
  @override
  State<LiveVehicleRegistrationScreen> createState() => _LiveVehicleRegistrationScreenState();
}

class _LiveVehicleRegistrationScreenState extends State<LiveVehicleRegistrationScreen> {
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

  @override
  void dispose() {
    for (final c in [_make, _model, _year, _registration, _colour]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Live vehicle registration', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(25), gradient: const LinearGradient(colors: [Color(0xFF063F32), AppColors.primary])),
              child: const Row(children: [
                CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark, size: 32)),
                SizedBox(width: 13),
                Expanded(child: Text('Register a tourism-ready vehicle with real backend verification.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.4))),
              ]),
            ),
            const SizedBox(height: 16),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            if (_created == null) _detailsForm() else _documentUpload(),
          ],
        ),
      );

  Widget _detailsForm() => PremiumCard(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Vehicle details and safety equipment', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Vehicle category', prefixIcon: Icon(Icons.category_outlined)),
              items: const ['Economy', 'Sedan', 'SUV', '7-Seater', 'Hiace', 'Coaster', '4×4 Jeep', 'Luxury'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 11),
            _field(_make, 'Manufacturer', Icons.factory_outlined),
            _field(_model, 'Model', Icons.directions_car_outlined),
            _field(_year, 'Year', Icons.calendar_month_outlined, keyboard: TextInputType.number),
            _field(_registration, 'Registration number', Icons.confirmation_number_outlined),
            _field(_colour, 'Vehicle colour', Icons.palette_outlined),
            const SizedBox(height: 8),
            _counter('Passenger capacity', _seats, 1, 60, (v) => setState(() => _seats = v)),
            _counter('Luggage capacity', _luggage, 0, 100, (v) => setState(() => _luggage = v)),
            _switch('Air conditioning', _ac, (v) => setState(() => _ac = v)),
            _switch('Heating', _heating, (v) => setState(() => _heating = v)),
            _switch('4×4 capability', _fourByFour, (v) => setState(() => _fourByFour = v)),
            _switch('First-aid kit', _firstAid, (v) => setState(() => _firstAid = v)),
            _switch('Fire extinguisher', _fireExtinguisher, (v) => setState(() => _fireExtinguisher = v)),
            _switch('Spare tyre and tools', _spareTyre, (v) => setState(() => _spareTyre = v)),
            _switch('Snow chains', _snowChains, (v) => setState(() => _snowChains = v)),
            _switch('Child seat', _childSeat, (v) => setState(() => _childSeat = v)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _createVehicle,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Save vehicle in live database'),
            ),
          ]),
        ),
      );

  Widget _documentUpload() => Column(children: [
        PremiumCard(
          color: const Color(0xFFE9F7EF),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 31),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_created!.make} ${_created!.model}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text('${_created!.registrationNumber} · readiness ${_created!.mountainReadinessScore}%', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
        PremiumCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Required documents and photographs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final item in _requiredDocuments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _uploaded.contains(item.$1) ? const Color(0xFFE4F7EC) : const Color(0xFFF1F4F3),
                  child: Icon(_uploaded.contains(item.$1) ? Icons.check_rounded : Icons.upload_file_rounded, color: AppColors.primaryDark),
                ),
                title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(_uploaded.contains(item.$1) ? 'Uploaded' : 'Tap to select JPG, PNG, WebP or PDF'),
                onTap: _busy ? null : () => _upload(item.$1),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy || _uploaded.length < _requiredDocuments.length ? null : _submitVehicle,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Submit vehicle for admin review'),
            ),
          ]),
        ),
      ]);

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextFormField(
          controller: c,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
          validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
        ),
      );

  Widget _counter(String label, int value, int min, int max, ValueChanged<int> changed) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton.filledTonal(onPressed: value > min ? () => changed(value - 1) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
          IconButton.filledTonal(onPressed: value < max ? () => changed(value + 1) : null, icon: const Icon(Icons.add)),
        ]),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> changed) => SwitchListTile(
        value: value,
        onChanged: changed,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      );

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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    await _run(() async {
      await AppControllerScope.of(context).uploadLiveVehicleDocument(_created!.id, type, result.files.single);
      _uploaded.add(type);
    });
  }

  Future<void> _submitVehicle() async {
    await _run(() async {
      _created = await AppControllerScope.of(context).submitLiveVehicle(_created!.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.fact_check_rounded, size: 52, color: AppColors.success),
          title: const Text('Vehicle submitted'),
          content: Text('Current status: ${_created!.status}. The Admin verification team can now review it.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The request could not be completed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
