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
}

class _EmergencyNumber {
  const _EmergencyNumber(this.name, this.phone, this.subtitle, {this.whatsApp = true});
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
        const _EmergencyNumber('Rescue 1122', '1122', 'Ambulance, fire and rescue', whatsApp: false),
        const _EmergencyNumber('Police', '15', 'Police emergency helpline', whatsApp: false),
        const _EmergencyNumber('Udrive Safety', '+923000001122', 'Udrive safety operations'),
        ...contacts.map(
          (contact) => _EmergencyNumber(
            contact.name,
            contact.phone,
            '${contact.relationship}${contact.isPrimary ? ' · Primary contact' : ''}',
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
          _EmergencyNumber('Rescue 1122', '1122', 'Ambulance, fire and rescue', whatsApp: false),
          _EmergencyNumber('Police', '15', 'Police emergency helpline', whatsApp: false),
          _EmergencyNumber('Udrive Safety', '+923000001122', 'Udrive safety operations'),
        ];
        _loading = false;
        _error = 'Trusted contacts could not be loaded. Emergency helplines are still available.';
      });
    }
  }

  Future<void> _call(_EmergencyNumber item) async {
    final uri = Uri(scheme: 'tel', path: item.phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call to ${item.phone}.')),
      );
    }
  }

  Future<Position> _currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please switch on location services.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to share your location.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _share(_EmergencyNumber item) async {
    if (!item.whatsApp || _sharingPhone != null) return;
    setState(() => _sharingPhone = item.phone);
    try {
      final position = await _currentLocation();
      await _whatsApp.shareLocation(
        to: item.phone,
        contactName: item.name,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your live location was sent to ${item.name} on WhatsApp.')),
      );
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
                child: const Icon(Icons.sos_rounded, color: AppColors.danger, size: 30),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Emergency SOS', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('Call directly or share your current location on WhatsApp.', style: TextStyle(color: AppColors.muted, height: 1.35)),
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
                            const SizedBox(width: 5),
                            IconButton.filled(
                              tooltip: item.whatsApp ? 'Share location on WhatsApp' : 'WhatsApp is not available for this helpline',
                              onPressed: item.whatsApp && _sharingPhone == null ? () => _share(item) : null,
                              style: IconButton.styleFrom(backgroundColor: const Color(0xFF19B86B)),
                              icon: sharing
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Use SOS only in a genuine emergency. WhatsApp location sharing requires internet and location permission.',
            style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}
