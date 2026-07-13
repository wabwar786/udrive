import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';

class CreatePackageScreen extends StatefulWidget {
  const CreatePackageScreen({super.key});

  @override
  State<CreatePackageScreen> createState() => _CreatePackageScreenState();
}

class _CreatePackageScreenState extends State<CreatePackageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _route = TextEditingController();
  final _price = TextEditingController();
  final _itinerary = TextEditingController();

  int _days = 3;
  bool _customerOffers = true;
  bool _fuel = true;
  bool _tolls = true;
  bool _hotel = false;

  @override
  void dispose() {
    _title.dispose();
    _route.dispose();
    _price.dispose();
    _itinerary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context, 'createPackage'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Container(
              height: 165,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 44),
                  SizedBox(height: 8),
                  Text(
                    'Add package cover image',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Package title'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _route,
              decoration: const InputDecoration(labelText: 'Route and destinations'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _days,
              decoration: const InputDecoration(labelText: 'Duration'),
              items: List.generate(
                10,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1} day${index == 0 ? '' : 's'}'),
                ),
              ),
              onChanged: (value) => setState(() => _days = value ?? 3),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Package price',
                prefixText: 'PKR ',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _itinerary,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Day-by-day itinerary',
                alignLabelWithHint: true,
              ),
              validator: _required,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Allow customer price offers',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      value: _customerOffers,
                      onChanged: (value) => setState(() => _customerOffers = value),
                    ),
                    const Divider(),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fuel included'),
                      value: _fuel,
                      onChanged: (value) => setState(() => _fuel = value ?? false),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tolls included'),
                      value: _tolls,
                      onChanged: (value) => setState(() => _tolls = value ?? false),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hotel included'),
                      value: _hotel,
                      onChanged: (value) => setState(() => _hotel = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _finish('Package saved as draft'),
                    child: Text(S.of(context, 'saveDraft')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        _finish('Package submitted for admin approval');
                      }
                    },
                    child: Text(S.of(context, 'submitApproval')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  void _finish(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    Navigator.pop(context);
  }
}
