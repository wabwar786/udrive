import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';

class VehicleListScreen extends StatelessWidget {
  const VehicleListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VehicleRegistrationScreen())),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.tr('addVehicle')),
        ),
        const SizedBox(height: 16),
        ...controller.vehicles.map((vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PremiumCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VehicleRegistrationScreen(existing: vehicle))),
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Container(
                      height: 145,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
                        gradient: LinearGradient(colors: [Color(0xFFE6F5EE), Color(0xFFDDEAF5)]),
                      ),
                      child: Stack(children: [
                        const Center(child: Icon(Icons.directions_car_filled_rounded, size: 95, color: AppColors.primaryDark)),
                        Positioned(top: 12, right: 12, child: StatusPill(label: verificationLabel(context, vehicle.status), color: verificationColor(vehicle.status))),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Expanded(child: Text('${vehicle.make} ${vehicle.model} ${vehicle.year}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))), const Icon(Icons.edit_outlined, color: AppColors.muted)]),
                          const SizedBox(height: 6),
                          Text('${vehicle.registration} · ${vehicle.category} · ${vehicle.color}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          const Divider(height: 24),
                          Row(children: [
                            _VehicleSpec(icon: Icons.people_alt_rounded, label: '${vehicle.seats} seats'),
                            const SizedBox(width: 16),
                            _VehicleSpec(icon: Icons.luggage_rounded, label: '${vehicle.luggage} bags'),
                            const SizedBox(width: 16),
                            _VehicleSpec(icon: vehicle.airConditioning ? Icons.ac_unit_rounded : Icons.air_rounded, label: vehicle.airConditioning ? 'A/C' : 'No A/C'),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )),
        PremiumCard(
          color: const Color(0xFFFFF9E9),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline_rounded, color: AppColors.warning), SizedBox(width: 10), Expanded(child: Text('Every vehicle is reviewed before it can receive bookings. Expired compulsory documents automatically restrict the vehicle.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)))]),
        ),
      ],
    );
  }
}

class _VehicleSpec extends StatelessWidget {
  const _VehicleSpec({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 17, color: AppColors.primaryDark), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]);
}

class VehicleRegistrationScreen extends StatefulWidget {
  const VehicleRegistrationScreen({this.existing, super.key});
  final VehicleRecord? existing;
  @override
  State<VehicleRegistrationScreen> createState() => _VehicleRegistrationScreenState();
}

class _VehicleRegistrationScreenState extends State<VehicleRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  late final TextEditingController _make = TextEditingController(text: widget.existing?.make ?? 'Toyota');
  late final TextEditingController _model = TextEditingController(text: widget.existing?.model ?? 'Fortuner');
  late final TextEditingController _year = TextEditingController(text: '${widget.existing?.year ?? 2022}');
  late final TextEditingController _color = TextEditingController(text: widget.existing?.color ?? 'Pearl White');
  late final TextEditingController _registration = TextEditingController(text: widget.existing?.registration ?? 'AJK-2026');
  late String _category = widget.existing?.category ?? 'SUV';
  late int _seats = widget.existing?.seats ?? 6;
  late int _luggage = widget.existing?.luggage ?? 4;
  late bool _ac = widget.existing?.airConditioning ?? true;
  late bool _fourByFour = widget.existing?.fourWheelDrive ?? true;
  bool _declarationAccepted = true;
  late final Map<String, bool> _uploads = Map<String, bool>.from(widget.existing?.documents ?? {
    'Registration document': false,
    'Insurance document': false,
    'Fitness certificate': false,
    'Front vehicle photo': false,
    'Rear vehicle photo': false,
    'Interior photo': false,
  });

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _color.dispose();
    _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? context.tr('registerVehicle') : context.tr('editVehicle'))),
        body: Form(
          key: _formKey,
          child: Stepper(
            currentStep: _step,
            type: StepperType.horizontal,
            elevation: 0,
            controlsBuilder: (_, details) => const SizedBox.shrink(),
            onStepTapped: (value) => setState(() => _step = value),
            steps: [
              Step(title: const Text('1'), isActive: _step >= 0, state: _step > 0 ? StepState.complete : StepState.indexed, content: _detailsStep()),
              Step(title: const Text('2'), isActive: _step >= 1, state: _step > 1 ? StepState.complete : StepState.indexed, content: _capacityStep()),
              Step(title: const Text('3'), isActive: _step >= 2, state: _step > 2 ? StepState.complete : StepState.indexed, content: _documentsStep()),
              Step(title: const Text('4'), isActive: _step >= 3, content: _reviewStep()),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              if (_step > 0) Expanded(child: OutlinedButton(onPressed: () => setState(() => _step--), child: Text(context.tr('back')))),
              if (_step > 0) const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: _step == 3 ? _submit : _next, child: Text(_step == 3 ? context.tr('submitVerification') : context.tr('next')))),
            ]),
          ),
        ),
      );

  Widget _detailsStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepTitle(title: context.tr('vehicleDetails'), subtitle: 'Enter the details exactly as shown on the registration document.'),
        TextFormField(controller: _make, decoration: InputDecoration(labelText: context.tr('make'), prefixIcon: const Icon(Icons.factory_rounded)), validator: _required),
        const SizedBox(height: 12),
        TextFormField(controller: _model, decoration: InputDecoration(labelText: context.tr('model'), prefixIcon: const Icon(Icons.directions_car_rounded)), validator: _required),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _year, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('year')), validator: (value) { final year = int.tryParse(value ?? ''); return year == null || year < 1990 || year > DateTime.now().year + 1 ? 'Enter a valid year' : null; })),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _color, decoration: InputDecoration(labelText: context.tr('color')), validator: _required)),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: _registration, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: context.tr('registrationNo'), prefixIcon: const Icon(Icons.pin_rounded)), validator: _required),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: InputDecoration(labelText: context.tr('category'), prefixIcon: const Icon(Icons.category_rounded)),
          items: const ['Economy', 'Comfort', 'Sedan', 'SUV', '7-Seater', '4×4 Jeep', 'Hiace', 'Coaster', 'Luxury'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (value) => setState(() => _category = value!),
        ),
      ]);

  Widget _capacityStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepTitle(title: context.tr('capabilities'), subtitle: 'These details control which routes and bookings the vehicle can receive.'),
        _ValueSelector(label: context.tr('seats'), icon: Icons.people_alt_rounded, value: _seats, min: 1, max: 30, onChanged: (v) => setState(() => _seats = v)),
        const SizedBox(height: 12),
        _ValueSelector(label: context.tr('luggageCapacity'), icon: Icons.luggage_rounded, value: _luggage, min: 0, max: 20, onChanged: (v) => setState(() => _luggage = v)),
        const SizedBox(height: 12),
        PremiumCard(child: Column(children: [
          SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.ac_unit_rounded, color: AppColors.secondary), value: _ac, onChanged: (v) => setState(() => _ac = v), title: Text(context.tr('airConditioning'), style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: const Text('Working air conditioning for passenger comfort.')),
          const Divider(),
          SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.terrain_rounded, color: AppColors.primaryDark), value: _fourByFour, onChanged: (v) => setState(() => _fourByFour = v), title: Text(context.tr('fourWheelDrive'), style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: const Text('Eligible for approved mountain and rough-road routes.')),
        ])),
        const SizedBox(height: 12),
        PremiumCard(color: const Color(0xFFEAF4FF), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.route_rounded, color: AppColors.info), SizedBox(width: 10), Expanded(child: Text('Route eligibility is finalized by an administrator after vehicle and document inspection.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)))])),
      ]);

  Widget _documentsStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepTitle(title: context.tr('uploadDocuments'), subtitle: 'Tap each item to simulate selecting a clear file or photograph.'),
        ..._uploads.entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 10), child: UploadTile(label: entry.key, uploaded: entry.value, icon: entry.key.contains('photo') ? Icons.add_a_photo_rounded : Icons.upload_file_rounded, onTap: () => setState(() => _uploads[entry.key] = !entry.value)))),
        PremiumCard(color: const Color(0xFFFFF9E9), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.security_rounded, color: AppColors.warning), SizedBox(width: 10), Expanded(child: Text('In the live version files will be securely uploaded to cloud storage. This frontend currently stores only dummy upload status.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)))])),
      ]);

  Widget _reviewStep() {
    final completed = _uploads.values.where((e) => e).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle(title: context.tr('reviewSubmit'), subtitle: 'Review the information before submitting it for verification.'),
      Container(height: 150, decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFFE6F5EE), Color(0xFFDDEAF5)])), child: const Icon(Icons.directions_car_filled_rounded, size: 96, color: AppColors.primaryDark)),
      const SizedBox(height: 14),
      PremiumCard(child: Column(children: [
        _ReviewRow(label: 'Vehicle', value: '${_make.text} ${_model.text} ${_year.text}'),
        _ReviewRow(label: context.tr('registrationNo'), value: _registration.text.toUpperCase()),
        _ReviewRow(label: context.tr('category'), value: _category),
        _ReviewRow(label: 'Capacity', value: '$_seats seats · $_luggage bags'),
        _ReviewRow(label: context.tr('fourWheelDrive'), value: _fourByFour ? 'Yes' : 'No'),
        _ReviewRow(label: context.tr('uploadDocuments'), value: '$completed/${_uploads.length} completed', last: true),
      ])),
      const SizedBox(height: 14),
      CheckboxListTile(value: _declarationAccepted, onChanged: (value) => setState(() => _declarationAccepted = value ?? false), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('I confirm that all submitted information is accurate.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
    ]);
  }

  String? _required(String? value) => (value ?? '').trim().isEmpty ? context.tr('required') : null;

  void _next() {
    if (_step == 0 && !_formKey.currentState!.validate()) return;
    if (_step == 2 && _uploads.values.where((v) => v).length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload at least four required documents or photos.')));
      return;
    }
    setState(() => _step++);
  }

  void _submit() {
    if (!_declarationAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please accept the declaration before submitting.')));
      return;
    }
    if (widget.existing == null) {
      AppControllerScope.of(context).addVehicle(VehicleRecord(
        id: 'V-${DateTime.now().millisecondsSinceEpoch}',
        make: _make.text.trim(),
        model: _model.text.trim(),
        year: int.parse(_year.text),
        color: _color.text.trim(),
        registration: _registration.text.trim().toUpperCase(),
        category: _category,
        seats: _seats,
        luggage: _luggage,
        airConditioning: _ac,
        fourWheelDrive: _fourByFour,
        status: VerificationStatus.pending,
        documents: _uploads,
      ));
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.fact_check_rounded, color: AppColors.success, size: 54),
        title: const Text('Vehicle submitted'),
        content: const Text('The vehicle has been saved with Pending review status. An administrator can approve it in the live system.'),
        actions: [FilledButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: Text(context.tr('done')))],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 12))]));
}

class _ValueSelector extends StatelessWidget {
  const _ValueSelector({required this.label, required this.icon, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final IconData icon;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => PremiumCard(child: Row(children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(width: 11), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove, size: 18)), SizedBox(width: 42, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add, size: 18))]));
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value, this.last = false});
  final String label;
  final String value;
  final bool last;
  @override
  Widget build(BuildContext context) => Column(children: [Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))), Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)))])), if (!last) const Divider(height: 1)]);
}
