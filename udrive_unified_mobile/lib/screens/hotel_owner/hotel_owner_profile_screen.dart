import 'package:flutter/material.dart';

import '../../core/hotels/hotel_owner_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../listing/listing_owner_parts.dart' show pickOwnerImage;

/// The hotel owner's profile: filled once, checked by the admin with the
/// owner's first hotel.
///
/// Name, business and contact are required, and so are both sides of the
/// CNIC. No personal photo is asked for. The CNIC pictures go to a protected
/// folder only the admin can open; this screen shows a tick, never the image.
///
/// Pops with `true` once the profile is complete, so the hotel wizard can carry
/// on straight after it.
class HotelOwnerProfileScreen extends StatefulWidget {
  const HotelOwnerProfileScreen({super.key});

  @override
  State<HotelOwnerProfileScreen> createState() => _HotelOwnerProfileScreenState();
}

class _HotelOwnerProfileScreenState extends State<HotelOwnerProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  late final HotelOwnerRepository _repo =
      HotelOwnerRepository(AppControllerScope.of(context).apiClient);

  HotelOwnerProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _uploading;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_name, _business, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final controller = AppControllerScope.of(context);
    try {
      final profile = await _repo.profile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        _name.text = profile.ownerName.isNotEmpty ? profile.ownerName : _realName(controller.currentUserName);
        _business.text = profile.businessName;
        _phone.text = _local(profile.phone.isNotEmpty ? profile.phone : controller.currentUserPhone);
        _email.text = profile.email;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _upload(String side) async {
    if (_profile?.verified == true) return;
    final file = await pickOwnerImage();
    if (file == null || !mounted) return;
    setState(() {
      _uploading = side;
      _error = null;
    });
    try {
      final profile = await _repo.uploadCnic(side, file);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _uploading = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = null;
        _error = 'Photo upload nahi hui: $error';
      });
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final current = _profile;
    if (current == null || !current.cnicFront || !current.cnicBack) {
      setState(() => _error = 'CNIC ke dono rukh (front aur back) ki photo lagayein.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await _repo.saveProfile(
        ownerName: _name.text.trim(),
        businessName: _business.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _saving = false;
      });
      if (profile.complete) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final locked = profile?.verified == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(title: 'Owner profile', onBack: () => Navigator.maybePop(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
                children: [
                  Text('Ek dafa — admin isi se aap ko verify karega.',
                      style: AppType.small.copyWith(color: AppText.secondary)),
                  if (profile?.verificationStatus == 'Rejected' && profile?.verificationNote != null) ...[
                    const SizedBox(height: 12),
                    UdBanner(tone: UdTone.err, icon: Icons.error_outline_rounded, text: profile!.verificationNote),
                  ],
                  const SizedBox(height: 14),
                  UdTextField(
                    controller: _name,
                    label: 'Owner ka naam',
                    icon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Naam likhein.' : null,
                  ),
                  const SizedBox(height: 12),
                  UdTextField(
                    controller: _business,
                    label: 'Business ka naam',
                    icon: Icons.storefront_outlined,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Business ka naam likhein.' : null,
                  ),
                  const SizedBox(height: 12),
                  UdTextField(
                    controller: _phone,
                    label: 'Contact / WhatsApp',
                    hint: '03001234567',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) => _validPhone(v) ? null : 'Sahi number likhein, jaise 03001234567.',
                  ),
                  const SizedBox(height: 12),
                  UdTextField(
                    controller: _email,
                    label: 'Email',
                    labelSuffix: 'optional',
                    hint: 'name@email.com',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                          ? null
                          : 'Email sahi nahi lagti.';
                    },
                  ),
                  const SizedBox(height: 18),
                  const UdLabel('CNIC photo (verification)'),
                  const SizedBox(height: 4),
                  Text(
                    locked
                        ? 'Verify ho chuka. Badalne ke liye support se rabta karein.'
                        : 'Sirf admin dekhega — customers ko kabhi nahi dikhai jati.',
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _CnicTile(
                          label: 'Front',
                          done: profile?.cnicFront == true,
                          busy: _uploading == 'front',
                          onTap: locked ? null : () => _upload('front'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CnicTile(
                          label: 'Back',
                          done: profile?.cnicBack == true,
                          busy: _uploading == 'back',
                          onTap: locked ? null : () => _upload('back'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    UdBanner(tone: UdTone.err, icon: Icons.error_outline_rounded, text: _error),
                  ],
                  const SizedBox(height: 20),
                  UdButton.primary(
                    label: 'Save & aage chalein',
                    busy: _saving,
                    onPressed: _saving || _uploading != null ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }

  static bool _validPhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^(03\d{9}|923\d{9}|3\d{9})$').hasMatch(digits);
  }

  /// "+923001234567" → "03001234567", for typing.
  static String _local(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('92') && digits.length == 12) return '0${digits.substring(2)}';
    return phone;
  }

  /// A "uDrive User 1234" placeholder is not a name.
  static String _realName(String name) =>
      name.toLowerCase().startsWith('udrive user') ? '' : name;
}

class _CnicTile extends StatelessWidget {
  const _CnicTile({required this.label, required this.done, required this.busy, required this.onTap});

  final String label;
  final bool done;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done ? AppColors.brandWash : AppColors.background,
      borderRadius: AppRadii.all(14),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: AppRadii.all(14),
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            borderRadius: AppRadii.all(14),
            border: Border.all(color: done ? AppColors.brand : AppColors.border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(done ? Icons.check_circle_rounded : Icons.photo_camera_outlined,
                        color: done ? AppColors.brandInk : AppColors.navy),
                    const SizedBox(height: 6),
                    Text(done ? '$label ✓' : label,
                        style: AppType.small.copyWith(fontWeight: FontWeight.w700, color: AppText.primary)),
                    if (done && onTap != null)
                      Text('Badalne ke liye tap', style: AppType.caption.copyWith(color: AppText.secondary)),
                  ],
                ),
        ),
      ),
    );
  }
}
