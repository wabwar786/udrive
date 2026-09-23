import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/businesses/business_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/business_models.dart';

/// Registration form a local business owner uses to list themselves in Near Me.
///
/// Deliberately mirrors the hotel owner "add" flow: the submission is created
/// as pending and only appears to customers once a UDrive admin approves it.
class BusinessOwnerAddScreen extends StatefulWidget {
  const BusinessOwnerAddScreen({this.existing, super.key});

  /// When supplied the form edits an existing listing instead of creating one.
  final BusinessListing? existing;

  @override
  State<BusinessOwnerAddScreen> createState() => _BusinessOwnerAddScreenState();
}

class _BusinessOwnerAddScreenState extends State<BusinessOwnerAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();

  BusinessCategory _category = BusinessCategory.restaurant;
  double? _latitude;
  double? _longitude;
  bool _saving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.name;
      _address.text = existing.address;
      _phone.text = existing.phone ?? '';
      _description.text = existing.description ?? '';
      _category = existing.category ?? BusinessCategory.restaurant;
      _latitude = existing.latitude;
      _longitude = existing.longitude;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on location to pin your business.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack('Allow location access to pin your business.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (_) {
      _snack('Location could not be detected. Please try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      _snack('Pin your business location before submitting.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repository =
          BusinessRepository(AppControllerScope.of(context).apiClient);
      final values = <String, dynamic>{
        'name': _name.text.trim(),
        'category': _category.apiValue,
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'description': _description.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
      };

      final existing = widget.existing;
      if (existing == null) {
        await repository.create(values);
      } else {
        await repository.update(existing.id, values);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submitted for review. Your listing goes live once UDrive '
            'approves it.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _snack('$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final pinned = _latitude != null && _longitude != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(editing ? 'Edit business' : 'List your business'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const Text(
              'Customers browsing Near Me will see your business once it is '
              'approved. You can update details any time.',
              style: TextStyle(
                  fontSize: 12, height: 1.45, color: AppText.secondary),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter your business name'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BusinessCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: BusinessCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter your address' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              validator: (value) => (value ?? '').trim().length < 7
                  ? 'Enter a contact number'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              maxLength: 400,
              decoration: const InputDecoration(
                labelText: 'What do you offer? (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: pinned ? AppTint.success : Colors.white,
                borderRadius: AppRadii.all(AppRadii.card),
                border: Border.all(
                  color: pinned ? AppColors.success : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    pinned
                        ? Icons.check_circle_rounded
                        : Icons.location_on_outlined,
                    size: 20,
                    color: pinned ? AppTint.successText : AppText.secondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pinned
                          ? 'Location pinned '
                              '(${_latitude!.toStringAsFixed(4)}, '
                              '${_longitude!.toStringAsFixed(4)})'
                          : 'Pin your exact location so customers can find you',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color:
                            pinned ? AppTint.successText : AppText.secondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _locating ? null : _useCurrentLocation,
                    child: Text(_locating
                        ? '…'
                        : pinned
                            ? 'Redo'
                            : 'Pin'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(editing ? 'Save changes' : 'Submit for review'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Photos and menu items can be added from your dashboard once the '
              'listing is approved.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppText.disabled),
            ),
          ],
        ),
      ),
    );
  }
}
