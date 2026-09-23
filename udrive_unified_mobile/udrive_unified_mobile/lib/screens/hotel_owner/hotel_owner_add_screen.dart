import 'package:flutter/material.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';

class HotelOwnerAddScreen extends StatefulWidget {
  const HotelOwnerAddScreen({this.standalone = false, super.key});

  final bool standalone;

  @override
  State<HotelOwnerAddScreen> createState() => _HotelOwnerAddScreenState();
}

class _HotelOwnerAddScreenState extends State<HotelOwnerAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _imageUrl = TextEditingController();
  final _amenities = TextEditingController();
  final _latitude = TextEditingController(text: '34.3700');
  final _longitude = TextEditingController(text: '73.4700');
  bool _transportAvailable = true;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _city,
      _district,
      _phone,
      _description,
      _imageUrl,
      _amenities,
      _latitude,
      _longitude,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      top: !widget.standalone,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (!widget.standalone) ...[
              const Text('Add Hotel', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF5EF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: Color(0xFF315239)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your hotel will stay hidden until the UDrive admin reviews and approves it. After approval it will automatically appear in Hotels & Stays.',
                      style: TextStyle(fontSize: 11, height: 1.45, color: Color(0xFF315239), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _field('Hotel name', _name),
            _field('Full address', _address, maxLines: 2),
            Row(
              children: [
                Expanded(child: _field('City', _city)),
                const SizedBox(width: 10),
                Expanded(child: _field('District', _district)),
              ],
            ),
            _field('Contact phone', _phone, keyboardType: TextInputType.phone),
            _field('Hotel description', _description, maxLines: 4),
            _field('Main hotel image URL (optional)', _imageUrl, isRequired: false, keyboardType: TextInputType.url),
            _field('Amenities, separated by commas', _amenities, isRequired: false),
            const SizedBox(height: 2),
            const Text('Map location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('Latitude', _latitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                const SizedBox(width: 10),
                Expanded(child: _field('Longitude', _longitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
              ],
            ),
            SwitchListTile.adaptive(
              value: _transportAvailable,
              onChanged: (value) => setState(() => _transportAvailable = value),
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              title: const Text('Transport available', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              subtitle: const Text('Customers can book a ride to this hotel.', style: TextStyle(fontSize: 10.5)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(_busy ? 'Submitting…' : 'Submit for admin approval'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Add your hotel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
      body: body,
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    bool isRequired = true,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 12.5),
        validator: isRequired
            ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          alignLabelWithHint: maxLines > 1,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    if (latitude == null || longitude == null || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid latitude and longitude.')));
      return;
    }

    setState(() => _busy = true);
    try {
      final amenities = _amenities.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      await HotelRepository(AppControllerScope.of(context).apiClient).createHotel({
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'district': _district.text.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'contactPhone': _phone.text.trim(),
        'mainImageUrl': _imageUrl.text.trim(),
        'amenities': amenities,
        'transportAvailable': _transportAvailable,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.hourglass_top_rounded, color: Color(0xFF315239), size: 36),
          title: const Text('Submitted for approval'),
          content: const Text('Your hotel is pending admin review. It will become visible to customers only after approval.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
        ),
      );
      if (widget.standalone && mounted) {
        Navigator.pop(context, true);
      } else {
        _formKey.currentState!.reset();
        for (final controller in [_name, _address, _city, _district, _phone, _description, _imageUrl, _amenities]) {
          controller.clear();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hotel could not be submitted: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
