import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/businesses/business_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/business_models.dart';
import '../../core/permissions/location_access.dart';

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
      // Disclosure before the prompt — see LocationAccess. This one uses the
      // `place` wording: the reading becomes a public pin on a business
      // listing, which is a different thing to say than "we find your pickup".
      final permission =
          await LocationAccess.ensure(context, LocationPurpose.place);
      if (!LocationAccess.granted(permission)) {
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
      appBar: UdTopBar(
        title: editing ? 'Edit business' : 'List your business',
        onBack: () => Navigator.pop(context),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
          children: [
            Text(
              'Customers browsing Near Me will see your business once it is '
              'approved. You can update details any time.',
              style:
                  AppType.body.copyWith(height: 1.45, color: AppText.secondary),
            ),
            const SizedBox(height: 22),

            UdTextField(
              controller: _name,
              label: 'Business name',
              icon: Icons.storefront_outlined,
              textCapitalization: TextCapitalization.words,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter your business name'
                  : null,
            ),
            const SizedBox(height: 16),

            // Was a `DropdownButtonFormField` of seven categories. Seven chips
            // fit on three lines and each one carries its own icon, which is
            // the same icon the customer sees on Near Me.
            const UdLabel('Category'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in BusinessCategory.values)
                  UdChip(
                    label: category.label,
                    icon: category.icon,
                    selected: _category == category,
                    onTap: () => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            UdTextField(
              controller: _address,
              label: 'Address',
              icon: Icons.location_on_outlined,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter your address' : null,
            ),
            const SizedBox(height: 16),
            UdTextField(
              controller: _phone,
              label: 'Phone number',
              icon: Icons.call_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) => (value ?? '').trim().length < 7
                  ? 'Enter a contact number'
                  : null,
            ),
            const SizedBox(height: 16),
            UdTextField(
              controller: _description,
              label: 'What do you offer?',
              labelSuffix: '(optional)',
              icon: Icons.notes_rounded,
              minLines: 3,
              maxLines: 4,
              maxLength: 400,
            ),
            const SizedBox(height: 16),

            // Pinned or not, in the shape the artboard gives it: a banner
            // that states the fact, and one button that either sets it or
            // does it again.
            UdBanner(
              tone: pinned ? UdTone.ok : UdTone.gray,
              icon: pinned
                  ? Icons.check_circle_rounded
                  : Icons.location_on_outlined,
              trailing: UdButton(
                label: _locating
                    ? 'Locating…'
                    : pinned
                        ? 'Redo'
                        : 'Pin',
                size: UdButtonSize.xs,
                variant: UdButtonVariant.outline,
                expand: false,
                busy: _locating,
                onPressed: _locating ? null : _useCurrentLocation,
              ),
              text: pinned
                  ? 'Location pinned '
                      '(${_latitude!.toStringAsFixed(4)}, '
                      '${_longitude!.toStringAsFixed(4)})'
                  : 'Pin your exact location so customers can find you',
            ),
            const SizedBox(height: 24),

            UdButton.primary(
              label: editing ? 'Save changes' : 'Submit for review',
              icon: Icons.send_rounded,
              busy: _saving,
              onPressed: _saving ? null : _submit,
            ),
            const SizedBox(height: 14),
            Text(
              'Photos and menu items can be added from your dashboard once '
              'the listing is approved.',
              textAlign: TextAlign.center,
              style:
                  AppType.small.copyWith(height: 1.5, color: AppText.caption),
            ),
          ],
        ),
      ),
    );
  }
}
