import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../models/auth_models.dart';
import 'live_vehicle_registration_screen.dart';

class DriverVerificationScreen extends StatefulWidget {
  const DriverVerificationScreen({super.key});
  @override
  State<DriverVerificationScreen> createState() => _DriverVerificationScreenState();
}

class _DriverVerificationScreenState extends State<DriverVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cnic = TextEditingController();
  final _licence = TextEditingController();
  final _address = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _bankTitle = TextEditingController();
  final _payoutAccount = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppControllerScope.of(context);
    if (_name.text.isEmpty) _name.text = controller.currentUserName;
  }

  @override
  void dispose() {
    for (final controller in [_name, _cnic, _licence, _address, _emergencyName, _emergencyPhone, _bankTitle, _payoutAccount]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final profile = controller.driverProfile;
    final urdu = controller.locale.languageCode == 'ur';

    return RefreshIndicator(
      onRefresh: controller.refreshAccount,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(colors: [Color(0xFF063F32), AppColors.primary]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Icon(Icons.badge_outlined, color: AppColors.primaryDark, size: 31)),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(urdu ? 'ÚˆØ±Ø§Ø¦ÛŒÙˆØ± Ú©ÛŒ ØªØµØ¯ÛŒÙ‚' : 'Driver verification', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(controller.currentUserPhone, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  ])),
                ]),
                const SizedBox(height: 18),
                Text(
                  urdu
                      ? 'Ù…Ø­ÙÙˆØ¸ Ø³ÛŒØ§Ø­Øª Ú©Û’ Ù„ÛŒÛ’ Ø´Ù†Ø§Ø®ØªØŒ Ù„Ø§Ø¦Ø³Ù†Ø³ØŒ Ø³ÛŒÙ„ÙÛŒ Ø§ÙˆØ± Ú¯Ø§Ú‘ÛŒ Ú©ÛŒ ØªØµØ¯ÛŒÙ‚ Ø¶Ø±ÙˆØ±ÛŒ ÛÛ’Û”'
                      : 'Identity, licence, selfie and vehicle verification are required before accepting real tourism bookings.',
                  style: const TextStyle(color: Colors.white, height: 1.45, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _StatusCard(status: profile?.verificationStatus ?? 'Not started', notes: profile?.reviewNotes),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          if (profile == null || profile.verificationStatus == 'Draft' || profile.verificationStatus == 'ChangesRequired')
            _profileForm(urdu)
          else
            _submittedProfile(profile, urdu),
          const SizedBox(height: 16),
          _documentsSection(urdu),
          const SizedBox(height: 16),
          _vehiclesSection(urdu),
          const SizedBox(height: 18),
          if (profile != null && profile.verificationStatus != 'Approved')
            FilledButton.icon(
              onPressed: _busy ? null : _submitApplication,
              icon: const Icon(Icons.send_rounded),
              label: Text(urdu ? 'ØªØµØ¯ÛŒÙ‚ Ú©Û’ Ù„ÛŒÛ’ Ø¬Ù…Ø¹ Ú©Ø±ÛŒÚº' : 'Submit complete application'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : AppControllerScope.of(context).refreshAccount,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(urdu ? 'Ø­Ø§Ù„Øª Ø¯ÙˆØ¨Ø§Ø±Û Ú†ÛŒÚ© Ú©Ø±ÛŒÚº' : 'Refresh approval status'),
          ),
        ],
      ),
    );
  }

  Widget _profileForm(bool urdu) => PremiumCard(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(urdu ? 'Ø°Ø§ØªÛŒ Ø§ÙˆØ± Ù‚Ø§Ù†ÙˆÙ†ÛŒ Ù…Ø¹Ù„ÙˆÙ…Ø§Øª' : 'Personal and legal information', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 15),
            _field(_name, urdu ? 'Ù¾ÙˆØ±Ø§ Ù†Ø§Ù…' : 'Full legal name', Icons.person_outline, required: true),
            _field(_cnic, urdu ? 'Ø´Ù†Ø§Ø®ØªÛŒ Ú©Ø§Ø±Úˆ Ù†Ù…Ø¨Ø± (13 ÛÙ†Ø¯Ø³Û’)' : 'CNIC number (13 digits)', Icons.credit_card_rounded, keyboard: TextInputType.number, required: true),
            _field(_licence, urdu ? 'ÚˆØ±Ø§Ø¦ÛŒÙˆÙ†Ú¯ Ù„Ø§Ø¦Ø³Ù†Ø³ Ù†Ù…Ø¨Ø±' : 'Driving licence number', Icons.badge_outlined, required: true),
            _field(_address, urdu ? 'Ù…Ú©Ù…Ù„ Ù¾ØªÛ' : 'Residential address', Icons.home_outlined, required: true, lines: 2),
            _field(_emergencyName, urdu ? 'Ø§ÛŒÙ…Ø±Ø¬Ù†Ø³ÛŒ Ø±Ø§Ø¨Ø·Û’ Ú©Ø§ Ù†Ø§Ù…' : 'Emergency contact name', Icons.contact_emergency_outlined, required: true),
            _field(_emergencyPhone, urdu ? 'Ø§ÛŒÙ…Ø±Ø¬Ù†Ø³ÛŒ Ù…ÙˆØ¨Ø§Ø¦Ù„ Ù†Ù…Ø¨Ø±' : 'Emergency mobile number', Icons.phone_outlined, keyboard: TextInputType.phone, required: true),
            _field(_bankTitle, urdu ? 'Ø§Ú©Ø§Ø¤Ù†Ù¹ Ú©Ø§ Ø¹Ù†ÙˆØ§Ù†' : 'Bank/wallet account title', Icons.account_balance_outlined),
            _field(_payoutAccount, urdu ? 'Ø¨ÛŒÙ†Ú©/ÙˆØ§Ù„Ù¹ Ø§Ú©Ø§Ø¤Ù†Ù¹' : 'Bank account, IBAN or wallet number', Icons.payments_outlined),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _busy ? null : _saveProfile,
              icon: const Icon(Icons.save_outlined),
              label: Text(urdu ? 'Ù…Ø¹Ù„ÙˆÙ…Ø§Øª Ù…Ø­ÙÙˆØ¸ Ú©Ø±ÛŒÚº' : 'Save registration details'),
            ),
          ]),
        ),
      );

  Widget _submittedProfile(DriverProfileLive profile, bool urdu) => PremiumCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(urdu ? 'Ù…Ø­ÙÙˆØ¸ Ù…Ø¹Ù„ÙˆÙ…Ø§Øª' : 'Saved registration', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          _info('CNIC', profile.cnicMasked ?? 'â€”'),
          _info(urdu ? 'Ù„Ø§Ø¦Ø³Ù†Ø³' : 'Licence', profile.drivingLicenceMasked ?? 'â€”'),
          _info(urdu ? 'Ø²Ø¨Ø§Ù†ÛŒÚº' : 'Languages', profile.languages.join(', ')),
          _info(urdu ? 'Ø³Ø±ÙˆØ³ Ø§ÛŒØ±ÛŒØ§Ø²' : 'Service areas', profile.serviceAreas.join(', ')),
        ]),
      );

  Widget _documentsSection(bool urdu) {
    const documents = <(String, String, IconData)>[
      ('CNIC_FRONT', 'CNIC front', Icons.credit_card_rounded),
      ('CNIC_BACK', 'CNIC back', Icons.credit_card_rounded),
      ('DRIVING_LICENCE', 'Driving licence', Icons.badge_rounded),
      ('SELFIE', 'Live selfie/profile photo', Icons.face_rounded),
    ];
    return PremiumCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(urdu ? 'Ø¶Ø±ÙˆØ±ÛŒ Ø¯Ø³ØªØ§ÙˆÛŒØ²Ø§Øª' : 'Required driver documents', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(urdu ? 'JPGØŒ PNGØŒ WebP ÛŒØ§ PDFØŒ Ø²ÛŒØ§Ø¯Û Ø³Û’ Ø²ÛŒØ§Ø¯Û 10 MBÛ”' : 'JPG, PNG, WebP or PDF, maximum 10 MB.', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        for (final item in documents)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: AppColors.primary.withValues(alpha: .1), child: Icon(item.$3, color: AppColors.primaryDark)),
            title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
            trailing: const Icon(Icons.upload_file_rounded),
            onTap: _busy ? null : () => _pickAndUploadDriverDocument(item.$1),
          ),
      ]),
    );
  }

  Widget _vehiclesSection(bool urdu) {
    final vehicles = AppControllerScope.of(context).liveVehicles;
    return PremiumCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(urdu ? 'Ø±Ø¬Ø³Ù¹Ø±Úˆ Ú¯Ø§Ú‘ÛŒØ§Úº' : 'Registered vehicles', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          IconButton.filledTonal(
            onPressed: _busy ? null : _openVehicleRegistration,
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
        if (vehicles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(urdu ? 'Ø§Ø¨Ú¾ÛŒ Ú©ÙˆØ¦ÛŒ Ú¯Ø§Ú‘ÛŒ Ø±Ø¬Ø³Ù¹Ø± Ù†ÛÛŒÚº ÛÙˆØ¦ÛŒÛ”' : 'No live vehicle is registered yet.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          )
        else
          for (final vehicle in vehicles)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: const Color(0xFFF5F8F7), borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.directions_car_filled_rounded, color: AppColors.primaryDark)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${vehicle.make} ${vehicle.model} ${vehicle.year}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text('${vehicle.registrationNumber} Â· ${vehicle.passengerCapacity} seats Â· readiness ${vehicle.mountainReadinessScore}%', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ])),
                _StatusPill(vehicle.status),
              ]),
            ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openVehicleRegistration,
          icon: const Icon(Icons.add_road_rounded),
          label: Text(urdu ? 'Ù†Ø¦ÛŒ Ú¯Ø§Ú‘ÛŒ Ø±Ø¬Ø³Ù¹Ø± Ú©Ø±ÛŒÚº' : 'Register another vehicle'),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon, {bool required = false, TextInputType? keyboard, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
          validator: required ? (value) => (value ?? '').trim().isEmpty ? 'Required' : null : null,
        ),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 105, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          Expanded(child: Text(value.isEmpty ? 'â€”' : value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
        ]),
      );

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await AppControllerScope.of(context).saveDriverProfile({
        'fullName': _name.text.trim(),
        'cnicNumber': _cnic.text.trim(),
        'drivingLicenceNumber': _licence.text.trim(),
        'address': _address.text.trim(),
        'emergencyContactName': _emergencyName.text.trim(),
        'emergencyContactPhone': _emergencyPhone.text.trim(),
        'bankAccountTitle': _bankTitle.text.trim().isEmpty ? null : _bankTitle.text.trim(),
        'payoutMethod': _payoutAccount.text.trim().isEmpty ? null : 'BankOrWallet',
        'payoutAccount': _payoutAccount.text.trim().isEmpty ? null : _payoutAccount.text.trim(),
        'languages': ['Urdu', 'English'],
        'serviceAreas': ['Muzaffarabad', 'Neelum Valley', 'Rawalakot'],
      });
      _message('Driver registration details saved.');
    });
  }

  Future<void> _pickAndUploadDriverDocument(String type) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    await _run(() async {
      await AppControllerScope.of(context).uploadDriverDocument(type, result.files.single);
      _message('${result.files.single.name} uploaded securely.');
    });
  }

  Future<void> _submitApplication() async {
    await _run(() async {
      final profile = await AppControllerScope.of(context).submitDriverProfile();
      _message('Application status: ${profile.verificationStatus}');
    });
  }

  Future<void> _openVehicleRegistration() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveVehicleRegistrationScreen()));
    if (mounted) await AppControllerScope.of(context).refreshAccount();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The request could not be completed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, this.notes});
  final String status;
  final String? notes;
  @override
  Widget build(BuildContext context) => PremiumCard(
        color: status == 'Approved' ? const Color(0xFFE6F7EE) : const Color(0xFFFFF8E7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(status == 'Approved' ? Icons.verified_rounded : Icons.pending_actions_rounded, color: status == 'Approved' ? AppColors.success : AppColors.warning, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Verification status: $status', style: const TextStyle(fontWeight: FontWeight.w900)),
            if (notes != null && notes!.isNotEmpty) ...[const SizedBox(height: 5), Text(notes!, style: const TextStyle(color: AppColors.muted, fontSize: 12))],
          ])),
        ]),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
        child: Text(status, style: const TextStyle(color: AppColors.primaryDark, fontSize: 10, fontWeight: FontWeight.w900)),
      );
}
