import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/media/image_compressor.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';
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
    final status = profile?.verificationStatus ?? 'Not started';

    // Rendered inside `main_shell`, which draws the bar — no Scaffold here.
    return RefreshIndicator(
      onRefresh: controller.refreshAccount,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 120),
        children: [
          // Was a navy gradient from AppColors.inkDeep — the last of the old
          // dark theme on this screen.
          UdCard(
            tone: UdCardTone.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const UdIconTile(
                      icon: Icons.badge_outlined,
                      tone: UdIconTone.lime,
                      size: UdIconTileSize.lg,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            urdu ? 'ڈرائیور کی تصدیق' : 'Driver verification',
                            style: AppType.h2.copyWith(color: AppText.onInk),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.currentUserPhone,
                            style: AppType.body2
                                .copyWith(color: AppText.onInkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  urdu
                      ? 'محفوظ سیاحت کے لیے شناخت، لائسنس، سیلفی اور گاڑی کی تصدیق ضروری ہے۔'
                      : 'Identity, licence, selfie and vehicle verification are '
                          'required before accepting real tourism bookings.',
                  style: AppType.body2.copyWith(color: AppText.onInkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _StatusCard(status: status, notes: profile?.reviewNotes),
          if (_error != null) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.error_outline_rounded,
              text: _error!,
            ),
          ],
          const SizedBox(height: 22),
          // Editable while it is a draft or has come back for changes;
          // read-only once it is with the reviewers. Unchanged.
          if (profile == null ||
              profile.verificationStatus == 'Draft' ||
              profile.verificationStatus == 'ChangesRequired')
            _profileForm(urdu)
          else
            _submittedProfile(profile, urdu),
          const SizedBox(height: 22),
          _documentsSection(urdu),
          const SizedBox(height: 22),
          _vehiclesSection(urdu),
          const SizedBox(height: 24),
          if (profile != null && profile.verificationStatus != 'Approved')
            UdButton.primary(
              label: urdu
                  ? 'تصدیق کے لیے جمع کریں'
                  : 'Submit complete application',
              icon: Icons.send_rounded,
              busy: _busy,
              onPressed: _submitApplication,
            ),
          const SizedBox(height: 10),
          UdButton.outline(
            label: urdu ? 'حالت دوبارہ چیک کریں' : 'Refresh approval status',
            icon: Icons.refresh_rounded,
            onPressed: _busy ? null : controller.refreshAccount,
          ),
        ],
      ),
    );
  }

  Widget _profileForm(bool urdu) => UdCard(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                urdu
                    ? 'ذاتی اور قانونی معلومات'
                    : 'Personal and legal information',
                style: AppType.section.copyWith(
                  fontSize: 17,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 18),
              _field(_name, urdu ? 'پورا نام' : 'Full legal name',
                  Icons.person_outline, required: true),
              _field(
                  _cnic,
                  urdu
                      ? 'شناختی کارڈ نمبر (13 ہندسے)'
                      : 'CNIC number (13 digits)',
                  Icons.credit_card_rounded,
                  keyboard: TextInputType.number,
                  required: true),
              _field(_licence, urdu ? 'ڈرائیونگ لائسنس نمبر' : 'Driving licence number',
                  Icons.badge_outlined, required: true),
              _field(_address, urdu ? 'مکمل پتہ' : 'Residential address',
                  Icons.home_outlined, required: true, lines: 2),
              _field(
                  _emergencyName,
                  urdu ? 'ایمرجنسی رابطے کا نام' : 'Emergency contact name',
                  Icons.contact_emergency_outlined,
                  required: true),
              _field(
                  _emergencyPhone,
                  urdu ? 'ایمرجنسی موبائل نمبر' : 'Emergency mobile number',
                  Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                  required: true),
              _field(_bankTitle, urdu ? 'اکاؤنٹ کا عنوان' : 'Bank/wallet account title',
                  Icons.account_balance_outlined),
              _field(
                  _payoutAccount,
                  urdu
                      ? 'بینک/والٹ اکاؤنٹ'
                      : 'Bank account, IBAN or wallet number',
                  Icons.payments_outlined),
              const SizedBox(height: 6),
              // Navy, not lime. The lime button on this screen is "Submit
              // complete application" at the very bottom — one green button
              // per screen, and it is the one that ends the job.
              UdButton.dark(
                label: urdu
                    ? 'معلومات محفوظ کریں'
                    : 'Save registration details',
                trailingIcon: Icons.edit_outlined,
                busy: _busy,
                onPressed: _saveProfile,
              ),
            ],
          ),
        ),
      );

  Widget _submittedProfile(DriverProfileLive profile, bool urdu) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              urdu ? 'محفوظ معلومات' : 'Saved registration',
              style: AppType.section.copyWith(
                fontSize: 17,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 10),
            UdKeyValue(label: 'CNIC', value: profile.cnicMasked ?? '—'),
            UdKeyValue(
              label: urdu ? 'لائسنس' : 'Licence',
              value: profile.drivingLicenceMasked ?? '—',
            ),
            UdKeyValue(
              label: urdu ? 'زبانیں' : 'Languages',
              value: profile.languages.isEmpty
                  ? '—'
                  : profile.languages.join(', '),
            ),
            UdKeyValue(
              label: urdu ? 'سروس ایریاز' : 'Service areas',
              value: profile.serviceAreas.isEmpty
                  ? '—'
                  : profile.serviceAreas.join(', '),
              showDivider: false,
            ),
          ],
        ),
      );

  Widget _documentsSection(bool urdu) {
    const documents = <(String, String, IconData)>[
      ('CNIC_FRONT', 'CNIC front', Icons.credit_card_rounded),
      ('CNIC_BACK', 'CNIC back', Icons.credit_card_rounded),
      ('DRIVING_LICENCE', 'Driving licence', Icons.badge_rounded),
      ('SELFIE', 'Live selfie/profile photo', Icons.face_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdSectionHeader(
          title: urdu ? 'ضروری دستاویزات' : 'Required driver documents',
        ),
        const SizedBox(height: 6),
        Text(
          urdu
              ? 'JPG، PNG، WebP یا PDF، زیادہ سے زیادہ 10 MB۔'
              : 'JPG, PNG, WebP or PDF, maximum 10 MB.',
          style: AppType.small.copyWith(color: AppText.secondary),
        ),
        const SizedBox(height: 14),
        UdListGroup(
          children: [
            for (final item in documents)
              UdListRow(
                title: item.$2,
                leading: UdIconTile(icon: item.$3),
                trailing: const Icon(Icons.upload_file_rounded,
                    size: 22, color: AppText.secondary),
                onTap: _busy
                    ? null
                    : () => _pickAndUploadDriverDocument(item.$1),
              ),
          ],
        ),
      ],
    );
  }

  Widget _vehiclesSection(bool urdu) {
    final vehicles = AppControllerScope.of(context).liveVehicles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdSectionHeader(
          title: urdu ? 'رجسٹرڈ گاڑیاں' : 'Registered vehicles',
          caption: vehicles.isEmpty
              ? null
              : (urdu
                  ? '${vehicles.length} گاڑیاں'
                  : '${vehicles.length} on your account'),
        ),
        const SizedBox(height: 14),
        if (vehicles.isEmpty)
          UdEmptyState(
            icon: Icons.directions_car_outlined,
            title: urdu ? 'کوئی گاڑی نہیں' : 'No vehicle yet',
            text: urdu
                ? 'ابھی کوئی گاڑی رجسٹر نہیں ہوئی۔'
                : 'No live vehicle is registered yet.',
          )
        else
          UdListGroup(
            children: [
              for (final vehicle in vehicles)
                UdListRow(
                  title: '${vehicle.make} ${vehicle.model} ${vehicle.year}',
                  subtitle: '${vehicle.registrationNumber} · '
                      '${vehicle.passengerCapacity} seats · '
                      'readiness ${vehicle.mountainReadinessScore}%',
                  leading: const UdIconTile(
                    icon: Icons.directions_car_filled_rounded,
                    tone: UdIconTone.soft,
                  ),
                  trailing: UdBadge(
                    label: vehicle.status,
                    tone: _vehicleTone(vehicle.status),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 14),
        UdButton.outline(
          label: urdu ? 'نئی گاڑی رجسٹر کریں' : 'Register another vehicle',
          icon: Icons.add_road_rounded,
          onPressed: _busy ? null : _openVehicleRegistration,
        ),
      ],
    );
  }

  static UdTone _vehicleTone(String status) => switch (status) {
        'Approved' || 'Active' => UdTone.ok,
        'Rejected' || 'Suspended' => UdTone.err,
        _ => UdTone.warn,
      };

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType? keyboard,
    int lines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: UdTextField(
          controller: controller,
          label: label,
          icon: icon,
          keyboardType: keyboard,
          maxLines: lines,
          minLines: lines > 1 ? lines : null,
          validator: required
              ? (value) => (value ?? '').trim().isEmpty ? 'Required' : null
              : null,
        ),
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
      // Shrunk first: see ImageCompressor. A four-megabyte camera photograph
      // is a minute of waiting per document on a mobile connection, and the
      // server refuses anything over ten.
      final file = await ImageCompressor.shrink(result.files.single);
      if (!mounted) return;
      await AppControllerScope.of(context).uploadDriverDocument(type, file);
      _message('${file.name} uploaded securely.');
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

/// Where the application stands, and what the reviewers said about it.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, this.notes});

  final String status;
  final String? notes;

  /// What to do next, per status.
  ///
  /// The banner used to say only "Verification status: Draft", which tells a
  /// driver where they are and not what to do about it — and "Draft" on its
  /// own reads like a failure rather than a form nobody has sent yet.
  static String? _hint(String status) => switch (status) {
        'Draft' || 'Not started' =>
          'save your details below, then submit for review',
        'Submitted' || 'PendingReview' || 'UnderReview' =>
          'our team reviews new registrations within 24 hours',
        'ChangesRequired' || 'Rejected' =>
          'send the document below again and resubmit',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final approved = status == 'Approved';
    final hint = _hint(status);
    return UdBanner(
      tone: approved ? UdTone.ok : UdTone.warn,
      icon: approved
          ? Icons.verified_rounded
          : Icons.pending_actions_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hint == null
                ? 'Verification status: $status'
                : 'Verification status: $status — $hint.',
            style: AppType.listTitle.copyWith(
              fontSize: 15.5,
              height: 1.4,
              color: approved ? AppTint.successText : AppTint.warningText,
            ),
          ),
          if ((notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notes!,
              style: AppType.small.copyWith(
                color: approved ? AppTint.successText : AppTint.warningText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
