import '../../core/theme/app_tokens.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/communication/whatsapp_repository.dart';
import '../../core/safety/safety_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';

class CustomerSosSheet extends StatefulWidget {
  const CustomerSosSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CustomerSosSheet(),
      );

  @override
  State<CustomerSosSheet> createState() => _CustomerSosSheetState();

  static Future<Position> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please switch on location services.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required for an emergency alert.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}

class _EmergencyNumber {
  const _EmergencyNumber({
    required this.name,
    required this.phone,
    required this.subtitle,
    required this.isOfficial,
    this.isPrimary = false,
  });

  final String name;
  final String phone;
  final String subtitle;
  final bool isOfficial;
  final bool isPrimary;
}

class _CustomerSosSheetState extends State<CustomerSosSheet> {
  late SafetyRepository _safety;
  late WhatsAppRepository _whatsApp;

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<_EmergencyNumber> _numbers = const [];

  static const _official = <_EmergencyNumber>[
    _EmergencyNumber(name: 'Rescue 1122', phone: '1122', subtitle: 'Ambulance, fire, road accidents and rescue', isOfficial: true),
    _EmergencyNumber(name: 'Police Emergency', phone: '15', subtitle: 'Police emergency helpline', isOfficial: true),
    _EmergencyNumber(name: 'AJK Tourist Helpline', phone: '05822924300', subtitle: 'Tourist assistance and coordination', isOfficial: true),
    _EmergencyNumber(name: 'AJK Tourist Helpline 2', phone: '05822921649', subtitle: 'Tourist assistance and coordination', isOfficial: true),
    _EmergencyNumber(name: 'Muzaffarabad Police Control', phone: '05822930418', subtitle: 'District police control room', isOfficial: true),
    _EmergencyNumber(name: 'Neelum Police Control', phone: '05821930000', subtitle: 'Neelum district police control room', isOfficial: true),
    _EmergencyNumber(name: 'SDMA Operations', phone: '05822921591', subtitle: 'Disaster management operations', isOfficial: true),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = AppControllerScope.of(context).apiClient;
    _safety = SafetyRepository(client);
    _whatsApp = WhatsAppRepository(client);
    if (_loading && _numbers.isEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await _safety.contacts();
      if (!mounted) return;
      setState(() {
        _numbers = [
          ..._official,
          ...contacts.map((contact) => _EmergencyNumber(
                name: contact.name,
                phone: contact.phone,
                subtitle: contact.relationship.isEmpty ? 'Personal emergency contact' : contact.relationship,
                isOfficial: false,
                isPrimary: contact.isPrimary,
              )),
        ];
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _numbers = _official;
        _loading = false;
        _error = 'Personal contacts could not be loaded. Official helplines are still available.';
      });
    }
  }

  Future<void> _call(_EmergencyNumber item) async {
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: item.phone),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call to ${item.phone}.')),
      );
    }
  }

  /// Raises the alert: a case for the safety desk, and a WhatsApp message with
  /// the customer's name and position to every personal contact they have
  /// added.
  ///
  /// This used to be a press-and-hold that recorded thirty seconds of audio and
  /// posted it to `/whatsapp/emergency-voice-broadcast`. **That endpoint does
  /// not exist in the API.** Every alert therefore 404'd on the upload and told
  /// the customer their recording "was not marked as sent" — in an emergency,
  /// after they had held the button for half a minute. The microphone, and the
  /// permission that went with it, bought nothing and cost a working SOS.
  ///
  /// One tap now, and the part that always worked is the part that runs.
  Future<void> _sendAlert() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final controller = AppControllerScope.of(context);
      final location = await CustomerSosSheet.currentLocation();
      final personalNumbers = _numbers
          .where((item) => !item.isOfficial)
          .map((item) => item.phone)
          .where((phone) => phone.trim().isNotEmpty)
          .toSet()
          .toList();

      // The case first. If the WhatsApp fan-out fails — no signal, WA Engine
      // down — the safety desk has still been told, which is the half that
      // matters most.
      await _safety.raiseSos(
        type: 'EmergencyAlert',
        description: 'Customer raised an emergency alert from the SOS sheet.',
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
      );

      final sent = await _whatsApp.emergencyBroadcast(
        numbers: personalNumbers,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracy,
        customerName: controller.currentUserName,
      );

      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            personalNumbers.isEmpty
                ? 'Udrive safety operations were notified with your location.'
                : 'Emergency alert sent to $sent personal contact(s). Udrive safety operations were notified.',
          ),
          backgroundColor: AppColors.primaryDark,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '${error.toString().replaceFirst('Exception: ', '')} '
            'If this keeps failing, call a helpline above.';
      });
    }
  }

  Future<void> _addContact() async {
    final result = await showDialog<_NewContact>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    );
    if (result == null || !mounted) return;
    try {
      setState(() => _loading = true);
      await _safety.addContact(
        name: result.name,
        phone: result.phone,
        relationship: result.relationship,
        primary: result.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final personalCount = _numbers.where((item) => !item.isOfficial).length;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppTint.danger, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.shield_rounded, color: AppTint.dangerText, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Emergency & safety contacts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('Call an official helpline, or send your name and live location to your personal contacts.', style: TextStyle(color: AppColors.muted, height: 1.3)),
                  ],
                ),
              ),
              IconButton(onPressed: _sending ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: AppTint.warning, borderRadius: BorderRadius.circular(13)),
              child: Text(_error!, style: const TextStyle(color: AppTint.warningText, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(34), child: CircularProgressIndicator()))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      ..._numbers.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _ContactCard(item: item, onCall: () => _call(item)),
                          )),
                      OutlinedButton.icon(
                        onPressed: _addContact,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(personalCount == 0 ? 'Add emergency contact' : 'Add another emergency contact'),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppTint.danger),
                        ),
                        child: Column(
                          children: [
                            const Text('Send emergency alert', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text(
                              _sending
                                  ? 'Sending your location…'
                                  : personalCount == 0
                                      ? 'Tap to alert Udrive safety operations with your location.'
                                      : 'Tap to send your name and live location to your $personalCount emergency contact(s) and Udrive safety operations.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35),
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              onTap: _sending ? null : _sendAlert,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: _sending ? AppText.disabled : AppColors.danger,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTint.danger, width: 6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.danger.withValues(alpha: .20),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: _sending
                                    ? const Padding(padding: EdgeInsets.all(23), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                                    : const Icon(Icons.sos_rounded, color: Colors.white, size: 34),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Official helplines receive calls only. Your alert goes to your personal emergency contacts and Udrive safety operations. No audio is recorded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.35),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.item, required this.onCall});
  final _EmergencyNumber item;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final accent = item.isOfficial ? AppColors.primaryDark : const Color(0xFF6C55C9);
    final pale = item.isOfficial ? AppTint.success : const Color(0xFFF0ECFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 9, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: item.isOfficial ? AppColors.border : const Color(0xFFDDD5FA)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: pale, child: Icon(item.isOfficial ? Icons.phone_in_talk_rounded : Icons.person_rounded, color: accent)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: pale, borderRadius: BorderRadius.circular(99)),
                      child: Text(item.isOfficial ? 'Official' : item.isPrimary ? 'Primary' : 'My Contact', style: TextStyle(color: accent, fontSize: 9.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(item.phone, style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(item.subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Call ${item.phone}',
            onPressed: onCall,
            style: IconButton.styleFrom(backgroundColor: pale, foregroundColor: accent),
            icon: const Icon(Icons.call_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _NewContact {
  const _NewContact(this.name, this.phone, this.relationship, this.primary);
  final String name;
  final String phone;
  final String relationship;
  final bool primary;
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();
  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _relationship = TextEditingController();
  bool _primary = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add emergency contact'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Contact name'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter contact name' : null),
                const SizedBox(height: 10),
                TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp number'), validator: (v) => v == null || v.trim().length < 7 ? 'Enter a valid phone number' : null),
                const SizedBox(height: 10),
                TextFormField(controller: _relationship, decoration: const InputDecoration(labelText: 'Relationship')),
                SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Set as primary contact'), value: _primary, onChanged: (v) => setState(() => _primary = v)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, _NewContact(_name.text.trim(), _phone.text.trim(), _relationship.text.trim(), _primary));
            },
            child: const Text('Save contact'),
          ),
        ],
      );
}
