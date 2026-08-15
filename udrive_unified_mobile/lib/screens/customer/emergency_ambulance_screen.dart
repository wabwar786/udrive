import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/safety/safety_repository.dart';
import '../../core/state/app_controller.dart';

class EmergencyAmbulanceScreen extends StatefulWidget {
  const EmergencyAmbulanceScreen({
    required this.pickupLabel,
    required this.latitude,
    required this.longitude,
    super.key,
  });

  final String pickupLabel;
  final double latitude;
  final double longitude;

  @override
  State<EmergencyAmbulanceScreen> createState() => _EmergencyAmbulanceScreenState();
}

class _EmergencyAmbulanceScreenState extends State<EmergencyAmbulanceScreen> {
  static const _lime = Color(0xFFB7F20A);
  static const _bg = Color(0xFF111312);
  static const _panel = Color(0xFF1C201E);

  static const _cities = <String>[
    'Muzaffarabad',
    'Mirpur',
    'Rawalakot',
    'Kotli',
    'Bagh',
    'Bhimber',
    'Hattian Bala',
    'Athmuqam / Neelum',
    'Pallandri / Sudhnoti',
    'Forward Kahuta / Haveli',
  ];

  String _selectedCity = _cities.first;
  bool _requesting = false;

  Future<void> _call1122() async {
    final uri = Uri(scheme: 'tel', path: '1122');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone dialer. Please dial 1122 manually.')),
      );
    }
  }

  Future<void> _requestAmbulance() async {
    if (_requesting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request ambulance?'),
        content: Text(
          'An emergency ambulance request will be sent for $_selectedCity. For a life-threatening emergency, call 1122 immediately.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send request')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _requesting = true);
    try {
      final repo = SafetyRepository(AppControllerScope.of(context).apiClient);
      await repo.raiseSos(
        type: 'Ambulance',
        description: 'Ambulance requested in $_selectedCity. Pickup: ${widget.pickupLabel}',
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency ambulance request sent to Udrive safety operations.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Online request could not be sent. Please call Rescue 1122 now.'),
          action: SnackBarAction(label: 'CALL 1122', onPressed: _call1122),
        ),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Emergency Ambulance', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF32191B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x66FF5B61)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emergency_rounded, color: Color(0xFFFF6B70), size: 30),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Need an ambulance now?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text('For urgent emergencies, direct calling is the fastest option.', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                  const SizedBox(height: 13),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _call1122,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5B61), foregroundColor: Colors.white),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('CALL RESCUE 1122', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Select Kashmir city', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ..._cities.map((city) {
              final selected = city == _selectedCity;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected ? const Color(0xFF292D29) : _panel,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    onTap: () => setState(() => _selectedCity = city),
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: selected ? _lime : Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_city_rounded, color: selected ? _lime : Colors.white54, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(city, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800))),
                          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? _lime : Colors.white30),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded, color: _lime, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.pickupLabel.isEmpty ? 'Current pickup location' : widget.pickupLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _requesting ? null : _requestAmbulance,
                style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: Colors.black),
                icon: _requesting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.local_hospital_rounded),
                label: Text(_requesting ? 'Sending request…' : 'Request ambulance in $_selectedCity', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The app request uses Udrive emergency/SOS operations. It does not replace the official Rescue 1122 emergency call.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 9.5, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
