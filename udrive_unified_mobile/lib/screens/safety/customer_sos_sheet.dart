import 'dart:async';

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

  static Future<void> triggerEmergency(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _EmergencyCountdownDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final controller = AppControllerScope.of(context);
    final safety = SafetyRepository(controller.apiClient);
    final whatsApp = WhatsAppRepository(controller.apiClient);

    _showSendingDialog(context);
    try {
      final position = await _getCurrentLocation();
      final contacts = await safety.contacts();
      final whatsappNumbers = contacts.map((contact) => contact.phone).toSet().toList();

      await safety.raiseSos(
        type: 'EmergencyMicrophone',
        description: 'Customer activated the emergency microphone/panic alert.',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      final sent = await whatsApp.emergencyBroadcast(
        numbers: whatsappNumbers,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        customerName: controller.currentUserName,
      );

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 48),
          title: const Text('Emergency alert sent'),
          content: Text(
            'Your location and emergency message were sent to $sent WhatsApp contact(s). Udrive safety operations were also notified.',
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _callNumber('1122'),
              icon: const Icon(Icons.emergency_rounded),
              label: const Text('Call Rescue 1122'),
            ),
            TextButton.icon(
              onPressed: () => _callNumber('15'),
              icon: const Icon(Icons.local_police_rounded),
              label: const Text('Call Police 15'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                show(context);
              },
              child: const Text('All emergency numbers'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final text = error.toString().replaceFirst('Exception: ', '');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 48),
          title: const Text('Alert could not be fully sent'),
          content: Text('$text\n\nCall Rescue 1122 or Police 15 immediately if you are in danger.'),
          actions: [
            TextButton(onPressed: () => _callNumber('1122'), child: const Text('Call 1122')),
            TextButton(onPressed: () => _callNumber('15'), child: const Text('Call 15')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          ],
        ),
      );
    }
  }

  static void _showSendingDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Getting your location and sending the emergency alert…')),
          ],
        ),
      ),
    );
  }

  static Future<void> _callNumber(String number) async {
    await launchUrl(Uri(scheme: 'tel', path: number), mode: LaunchMode.externalApplication);
  }

  static Future<Position> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please switch on location services.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required for the emergency alert.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  @override
  State<CustomerSosSheet> createState() => _CustomerSosSheetState();
}

class _EmergencyCountdownDialog extends StatefulWidget {
  const _EmergencyCountdownDialog();

  @override
  State<_EmergencyCountdownDialog> createState() => _EmergencyCountdownDialogState();
}

class _EmergencyCountdownDialogState extends State<_EmergencyCountdownDialog> {
  int seconds = 3;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (seconds <= 1) {
        timer?.cancel();
        Navigator.pop(context, true);
      } else {
        setState(() => seconds--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Container(
        width: 62,
        height: 62,
        decoration: const BoxDecoration(color: Color(0xFFFFE6E7), shape: BoxShape.circle),
        child: const Icon(Icons.mic_rounded, color: AppColors.danger, size: 34),
      ),
      title: const Text('Emergency alert starting'),
      content: Text(
        'In $seconds second${seconds == 1 ? '' : 's'}, your location and an emergency message will be sent to all trusted WhatsApp contacts and Udrive safety operations.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Send now'),
        ),
      ],
    );
  }
}

class _EmergencyNumber {
  const _EmergencyNumber(this.name, this.phone, this.subtitle, {this.whatsApp = false});
  final String name;
  final String phone;
  final String subtitle;
  final bool whatsApp;
}

class _CustomerSosSheetState extends State<CustomerSosSheet> {
  late SafetyRepository _safety;
  late WhatsAppRepository _whatsApp;
  bool _loading = true;
  String? _error;
  String? _sharingPhone;
  List<_EmergencyNumber> _numbers = const [];

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
      final values = <_EmergencyNumber>[
        const _EmergencyNumber('Rescue 1122', '1122', 'Ambulance, fire, road accidents and rescue'),
        const _EmergencyNumber('Police Emergency', '15', 'Police emergency helpline'),
        const _EmergencyNumber('AJK Tourist Helpline', '05822924300', 'Tourist assistance and coordination'),
        const _EmergencyNumber('AJK Tourist Helpline 2', '05822921649', 'Tourist assistance and coordination'),
        const _EmergencyNumber('Muzaffarabad Police Control', '05822930418', 'District police control room'),
        const _EmergencyNumber('Neelum Police Control', '05821930000', 'Neelum district police control room'),
        const _EmergencyNumber('SDMA Operations', '05822921591', 'Disaster management operations'),
        ...contacts.map(
          (contact) => _EmergencyNumber(
            contact.name,
            contact.phone,
            '${contact.relationship}${contact.isPrimary ? ' · Primary contact' : ''}',
            whatsApp: true,
          ),
        ),
      ];
      if (!mounted) return;
      setState(() {
        _numbers = values;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _numbers = const [
          _EmergencyNumber('Rescue 1122', '1122', 'Ambulance, fire, road accidents and rescue'),
          _EmergencyNumber('Police Emergency', '15', 'Police emergency helpline'),
          _EmergencyNumber('AJK Tourist Helpline', '05822924300', 'Tourist assistance and coordination'),
          _EmergencyNumber('Muzaffarabad Police Control', '05822930418', 'District police control room'),
          _EmergencyNumber('Neelum Police Control', '05821930000', 'Neelum district police control room'),
          _EmergencyNumber('SDMA Operations', '05822921591', 'Disaster management operations'),
        ];
        _loading = false;
        _error = 'Trusted contacts could not be loaded. Official emergency helplines are still available.';
      });
    }
  }

  Future<void> _call(_EmergencyNumber item) async {
    final uri = Uri(scheme: 'tel', path: item.phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start a call to ${item.phone}.')));
    }
  }

  Future<void> _share(_EmergencyNumber item) async {
    if (!item.whatsApp || _sharingPhone != null) return;
    setState(() => _sharingPhone = item.phone);
    try {
      final position = await CustomerSosSheet._getCurrentLocation();
      await _whatsApp.shareLocation(
        to: item.phone,
        contactName: item.name,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Your location was sent to ${item.name} on WhatsApp.')));
    } catch (error) {
      if (!mounted) return;
      final text = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _sharingPhone = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 22 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: const Color(0xFFFFE3E5), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.mic_rounded, color: AppColors.danger, size: 29),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Emergency & safety contacts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('Call an official helpline or share your location with a WhatsApp contact.', style: TextStyle(color: AppColors.muted, height: 1.35)),
                  ],
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF3D8), borderRadius: BorderRadius.circular(13)),
              child: Text(_error!, style: const TextStyle(color: Color(0xFF785500), fontSize: 12)),
            ),
          ],
          const SizedBox(height: 14),
          Flexible(
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(34), child: CircularProgressIndicator()))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _numbers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final item = _numbers[index];
                      final sharing = _sharingPhone == item.phone;
                      return Container(
                        padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE0EAE6)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: .11),
                              child: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryDark),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text('${item.phone} · ${item.subtitle}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Call',
                              onPressed: () => _call(item),
                              icon: const Icon(Icons.call_rounded, size: 20),
                            ),
                            if (item.whatsApp) ...[
                              const SizedBox(width: 5),
                              IconButton.filled(
                                tooltip: 'Share location on WhatsApp',
                                onPressed: _sharingPhone == null ? () => _share(item) : null,
                                style: IconButton.styleFrom(backgroundColor: const Color(0xFF19B86B)),
                                icon: sharing
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tap the red microphone to send a panic alert. Long-press it to open this contact list. Use emergency features only when genuine help is required.',
            style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}
