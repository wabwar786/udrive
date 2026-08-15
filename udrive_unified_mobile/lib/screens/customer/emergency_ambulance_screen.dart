import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_config.dart';
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

  List<String> _cities = const [];
  List<_Ambulance> _ambulances = const [];
  String? _selectedCity;
  bool _loadingCities = true;
  bool _loadingAmbulances = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCities());
  }

  Future<void> _loadCities() async {
    if (!mounted) return;
    setState(() {
      _loadingCities = true;
      _error = null;
    });
    try {
      final client = AppControllerScope.of(context).apiClient;
      final response = await client.getJson('/api/v1/catalog/ambulance-cities', authenticated: false);
      final raw = response['data'];
      final cities = raw is List
          ? raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList(growable: false)
          : <String>[];
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _loadingCities = false;
      });
      if (cities.isNotEmpty) {
        await _selectCity(cities.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCities = false;
        _error = 'Ambulance cities could not be loaded. ${_message(error)}';
      });
    }
  }

  Future<void> _selectCity(String city) async {
    if (!mounted) return;
    setState(() {
      _selectedCity = city;
      _loadingAmbulances = true;
      _ambulances = const [];
      _error = null;
    });
    try {
      final client = AppControllerScope.of(context).apiClient;
      final response = await client.getJson(
        '/api/v1/catalog/ambulances?city=${Uri.encodeQueryComponent(city)}',
        authenticated: false,
      );
      final raw = response['data'];
      final ambulances = <_Ambulance>[];
      if (raw is List) {
        for (final item in raw.whereType<Map>()) {
          ambulances.add(_Ambulance.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      if (!mounted) return;
      setState(() {
        _ambulances = ambulances;
        _loadingAmbulances = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingAmbulances = false;
        _error = 'Ambulances could not be loaded. ${_message(error)}';
      });
    }
  }

  String _message(Object error) => '$error'.replaceFirst('Exception: ', '').trim();

  Future<void> _call(_Ambulance ambulance) async {
    final phone = ambulance.phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;
    final opened = await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open phone dialer for ${ambulance.phoneNumber}.')),
      );
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
        child: RefreshIndicator(
          onRefresh: _loadCities,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 84,
                      height: 62,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Image.asset(
                        'assets/images/home_services/ambulance.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.local_hospital_rounded, color: _lime, size: 42),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Choose your city', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                          SizedBox(height: 4),
                          Text('Only ambulances saved in the Udrive database are shown here.', style: TextStyle(color: Colors.white60, fontSize: 10.5, height: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              if (_loadingCities)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator(color: _lime)),
                )
              else if (_cities.isEmpty)
                _empty('No ambulance cities are saved in the database yet.')
              else ...[
                const Text('Cities', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _cities.map((city) {
                    final selected = city == _selectedCity;
                    return ChoiceChip(
                      selected: selected,
                      onSelected: (_) => _selectCity(city),
                      label: Text(city),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                      selectedColor: _lime,
                      backgroundColor: _panel,
                      side: BorderSide(color: selected ? _lime : Colors.white12),
                      showCheckmark: false,
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedCity == null ? 'Ambulances' : 'Ambulances in $_selectedCity',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (_loadingAmbulances)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _lime)),
                  ],
                ),
                const SizedBox(height: 9),
                if (!_loadingAmbulances && _ambulances.isEmpty)
                  _empty('No active ambulance is saved for $_selectedCity.')
                else
                  ..._ambulances.map(_ambulanceCard),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF351B1D), borderRadius: BorderRadius.circular(14)),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFF9B9F), fontSize: 11.5)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _ambulanceCard(_Ambulance ambulance) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 74,
              height: 58,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04), borderRadius: BorderRadius.circular(13)),
              child: ambulance.imageUrl.isEmpty
                  ? Image.asset('assets/images/home_services/ambulance.png', fit: BoxFit.contain)
                  : Image.network(
                      ambulance.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Image.asset('assets/images/home_services/ambulance.png', fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ambulance.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(ambulance.city, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _pill(Icons.payments_outlined, '${ambulance.currency} ${ambulance.perKmFare.toStringAsFixed(0)} / km'),
                      _pill(Icons.phone_outlined, ambulance.phoneNumber),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Call ${ambulance.name}',
              onPressed: () => _call(ambulance),
              style: IconButton.styleFrom(backgroundColor: _lime, foregroundColor: Colors.black),
              icon: const Icon(Icons.call_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _lime, size: 12),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: _lime),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4))),
          ],
        ),
      );
}

class _Ambulance {
  const _Ambulance({
    required this.id,
    required this.name,
    required this.city,
    required this.phoneNumber,
    required this.perKmFare,
    required this.currency,
    required this.imageUrl,
  });

  factory _Ambulance.fromJson(Map<String, dynamic> json) => _Ambulance(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Ambulance'}'.trim(),
        city: '${json['city'] ?? ''}'.trim(),
        phoneNumber: '${json['phoneNumber'] ?? ''}'.trim(),
        perKmFare: (json['perKmFare'] as num?)?.toDouble() ?? 0,
        currency: '${json['currency'] ?? 'PKR'}'.trim(),
        imageUrl: ApiConfig.absoluteUrl(json['imageUrl']?.toString()),
      );

  final String id;
  final String name;
  final String city;
  final String phoneNumber;
  final double perKmFare;
  final String currency;
  final String imageUrl;
}
