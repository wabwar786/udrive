import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
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
  final AudioRecorder _recorder = AudioRecorder();
  final List<int> _audioBytes = <int>[];

  late SafetyRepository _safety;
  late WhatsAppRepository _whatsApp;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _recordingTimer;

  bool _loading = true;
  bool _recording = false;
  bool _sending = false;
  String? _error;
  int _recordingSeconds = 0;
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

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
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

  Future<void> _startRecording() async {
    if (_sending || _recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission is required to record an emergency message.');
      }
      _audioBytes.clear();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _audioSubscription = stream.listen(_audioBytes.addAll);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingSeconds = 0;
        _error = null;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recording) return;
        if (_recordingSeconds >= 29) {
          _finishAndSendRecording();
          return;
        }
        setState(() => _recordingSeconds++);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _finishAndSendRecording() async {
    if (!_recording || _sending) return;
    _recordingTimer?.cancel();
    await _recorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (!mounted) return;
    setState(() {
      _recording = false;
      _sending = true;
    });

    try {
      if (_audioBytes.isEmpty) throw Exception('No voice recording was captured. Please try again.');
      final controller = AppControllerScope.of(context);
      final location = await CustomerSosSheet.currentLocation();
      final personalNumbers = _numbers
          .where((item) => !item.isOfficial)
          .map((item) => item.phone)
          .where((phone) => phone.trim().isNotEmpty)
          .toSet()
          .toList();

      await _safety.raiseSos(
        type: 'EmergencyVoiceAlert',
        description: 'Customer sent an emergency voice recording.',
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
      );

      final audio = PlatformFile(
        name: 'emergency_voice_${DateTime.now().millisecondsSinceEpoch}.pcm',
        size: _audioBytes.length,
        bytes: Uint8List.fromList(_audioBytes),
      );

      final sent = await _whatsApp.emergencyVoiceBroadcast(
        numbers: personalNumbers,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracy,
        customerName: controller.currentUserName,
        audio: audio,
      );

      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergency voice alert sent to $sent personal contact(s). Udrive safety operations were notified.'),
          backgroundColor: AppColors.primaryDark,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '${error.toString().replaceFirst('Exception: ', '')} Your recording was not marked as sent; press and hold to retry.';
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

  String get _timerText =>
      '00:${_recordingSeconds.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final personalCount = _numbers.where((item) => !item.isOfficial).length;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFF7FAF9),
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
                decoration: BoxDecoration(color: const Color(0xFFFFE3E5), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.mic_rounded, color: AppColors.danger, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Emergency & safety contacts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('Call an official helpline or send your voice and location to personal contacts.', style: TextStyle(color: AppColors.muted, height: 1.3)),
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
              decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(13)),
              child: Text(_error!, style: const TextStyle(color: Color(0xFF795500), fontSize: 12)),
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
                          border: Border.all(color: const Color(0xFFFFD5D9)),
                        ),
                        child: Column(
                          children: [
                            const Text('Send emergency voice alert', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text(
                              _recording
                                  ? 'Recording $_timerText — release to send'
                                  : _sending
                                      ? 'Sending voice recording and live location…'
                                      : 'Press and hold the microphone. Release to send immediately.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _recording ? AppColors.danger : AppColors.muted, fontSize: 12.5, height: 1.35),
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              onLongPressStart: (_) => _startRecording(),
                              onLongPressEnd: (_) => _finishAndSendRecording(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: _recording ? 82 : 72,
                                height: _recording ? 82 : 72,
                                decoration: BoxDecoration(
                                  color: _sending ? const Color(0xFFB8BEC5) : AppColors.danger,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFFFE5E7), width: _recording ? 9 : 6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.danger.withValues(alpha: _recording ? .38 : .20),
                                      blurRadius: _recording ? 28 : 16,
                                      spreadRadius: _recording ? 4 : 0,
                                    ),
                                  ],
                                ),
                                child: _sending
                                    ? const Padding(padding: EdgeInsets.all(23), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                                    : Icon(_recording ? Icons.graphic_eq_rounded : Icons.mic_rounded, color: Colors.white, size: 34),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text('Maximum recording: 30 seconds', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Official helplines receive calls only. Voice alerts are sent to your personal emergency contacts and Udrive safety operations.',
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
    final pale = item.isOfficial ? const Color(0xFFE8F7F1) : const Color(0xFFF0ECFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 9, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: item.isOfficial ? const Color(0xFFDDEAE5) : const Color(0xFFDDD5FA)),
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
