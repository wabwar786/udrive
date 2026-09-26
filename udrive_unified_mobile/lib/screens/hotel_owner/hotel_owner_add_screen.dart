import 'package:flutter/material.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// H-02 — submit a property for admin approval.
///
/// Two lives: the second tab of [HotelOwnerShell], and a pushed page from the
/// customer's hotel list. [standalone] is which — as a tab it draws no
/// `Scaffold`, because the shell already has one. That split was here before
/// this rebuild and it is the right shape; the create-package and documents
/// screens got the same treatment in Phases 16 and 17.
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
    final body = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          UdBanner(
            tone: UdTone.info,
            icon: Icons.verified_user_outlined,
            text: 'Your hotel will stay hidden until the UDrive admin reviews '
                'and approves it. After approval it will automatically appear '
                'in Hotels & Stays.',
          ),
          const SizedBox(height: 20),

          _field('Hotel name', _name, icon: Icons.apartment_rounded),
          _field('Full address', _address,
              icon: Icons.location_on_outlined, maxLines: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field('City', _city)),
              const SizedBox(width: 12),
              Expanded(child: _field('District', _district)),
            ],
          ),
          _field('Contact phone', _phone,
              icon: Icons.call_outlined, keyboardType: TextInputType.phone),
          _field('Hotel description', _description,
              icon: Icons.notes_rounded, maxLines: 4),
          _field('Main hotel image URL', _imageUrl,
              suffix: '(optional)',
              icon: Icons.image_outlined,
              isRequired: false,
              keyboardType: TextInputType.url),
          _field('Amenities', _amenities,
              suffix: '(optional, comma separated)',
              icon: Icons.checklist_rounded,
              isRequired: false),

          const SizedBox(height: 6),
          const UdSectionHeader(title: 'Map location'),
          const SizedBox(height: 4),
          Text(
            'Where customers see the pin, and where a ride to this hotel is '
            'sent.',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field('Latitude', _latitude,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field('Longitude', _longitude,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
              ),
            ],
          ),

          UdListGroup(
            children: [
              UdListRow(
                title: 'Transport available',
                subtitle: 'Customers can book a ride to this hotel.',
                trailing: UdSwitch(
                  value: _transportAvailable,
                  onChanged: (value) =>
                      setState(() => _transportAvailable = value),
                  semanticLabel: 'Transport available',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          UdButton.primary(
            label: _busy ? 'Submitting…' : 'Submit for admin approval',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );

    if (!widget.standalone) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: 'Add your hotel',
        onBack: () => Navigator.pop(context),
      ),
      body: body,
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? suffix,
    IconData? icon,
    int maxLines = 1,
    bool isRequired = true,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: UdTextField(
        controller: controller,
        label: label,
        labelSuffix: suffix,
        icon: icon,
        maxLines: maxLines,
        minLines: maxLines > 1 ? maxLines : null,
        keyboardType: keyboardType,
        validator: isRequired
            ? (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null
            : null,
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
      await showUdDialog<void>(
        context: context,
        title: 'Submitted for approval',
        message: 'Your hotel is pending admin review. It will become visible '
            'to customers only after approval.',
        content: const Center(
          child: UdIconTile(
            icon: Icons.hourglass_top_rounded,
            tone: UdIconTone.warn,
            size: UdIconTileSize.lg,
          ),
        ),
        actions: [
          Builder(
            builder: (dialogContext) => UdButton.primary(
              label: 'Done',
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
        ],
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
