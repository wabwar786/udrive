import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../models/booking_models.dart';
import '../../models/trip_operations_models.dart';
import '../../core/booking/trip_operations_repository.dart';
import 'live_packages_screen.dart';
import '../operations/live_trip_navigation_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  static const _navy = Color(0xFF061923);
  static const _panel = Color(0xE6102029);
  static const _lime = Color(0xFF8ED12B);
  static const _muted = Color(0xFFB4C0C6);

  final _pickup = TextEditingController(text: 'Detecting current address…');
  final _destination = TextEditingController();
  final _pageController = PageController();
  final _scrollController = ScrollController();
  late final ApiClient _api;

  Timer? _heroTimer;
  Timer? _tripTimer;
  int _heroIndex = 0;
  bool _loadingDestinations = true;
  bool _showDestinationList = false;
  bool _searched = false;
  String _destinationQuery = '';
  List<_HeroDestination> _destinations = const [];
  TripOperationsRepository? _tripRepository;
  MobileTrip? _activeTrip;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(SessionStore());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([_loadDestinations(), _loadLocation(), _loadMarketplace()]);
    });
    _heroTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients || _destinations.length < 2) return;
      final next = (_heroIndex + 1) % _destinations.length;
      _pageController.animateToPage(next, duration: const Duration(milliseconds: 550), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tripRepository ??= TripOperationsRepository(AppControllerScope.of(context).apiClient);
    _refreshActiveTrip();
    _tripTimer ??= Timer.periodic(const Duration(seconds: 12), (_) => _refreshActiveTrip());
  }

  Future<void> _loadMarketplace() async {
    final controller = AppControllerScope.of(context);
    await controller.refreshHomeVehicles();
    await controller.refreshPhase9Marketplace();
  }

  Future<void> _loadDestinations() async {
    try {
      final response = await _api.getJson('/api/v1/catalog/destinations?language=en', authenticated: false);
      final raw = response['data'] as List? ?? const [];
      final loaded = raw.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        return _HeroDestination(
          name: '${map['name'] ?? ''}'.trim(),
          district: '${map['district'] ?? ''}'.trim(),
          summary: '${map['summary'] ?? ''}'.trim(),
          imageUrl: ApiConfig.absoluteUrl(map['coverImageUrl']?.toString()),
        );
      }).where((item) => item.name.isNotEmpty && item.imageUrl.isNotEmpty).toList();
      if (mounted) setState(() => _destinations = loaded.isEmpty ? _fallbackDestinations : loaded);
    } catch (_) {
      if (mounted) setState(() => _destinations = _fallbackDestinations);
    } finally {
      if (mounted) setState(() => _loadingDestinations = false);
    }
  }

  Future<void> _loadLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _pickup.text = 'Enter pickup address';
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _pickup.text = 'Enter pickup address';
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final marks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (marks.isEmpty) return;
      final mark = marks.first;
      final values = [mark.street, mark.subLocality, mark.locality, mark.administrativeArea, mark.country]
          .whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      _pickup.text = values.join(', ');
    } catch (_) {
      _pickup.text = 'Enter pickup address';
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshActiveTrip() async {
    final repository = _tripRepository;
    if (repository == null) return;
    try {
      final trips = await repository.customerTrips();
      final active = trips.where((trip) => const {'DriverEnRoute', 'DriverArrived', 'TripStarted', 'Emergency'}.contains(trip.tripStatus)).toList();
      if (mounted) setState(() => _activeTrip = active.isEmpty ? null : active.first);
    } catch (_) {}
  }

  Future<void> _openActiveTrip() async {
    if (_activeTrip == null || _tripRepository == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerFullScreenTrackingScreen(trip: _activeTrip!, repository: _tripRepository!)));
    await _refreshActiveTrip();
  }

  void _selectDestination(_HeroDestination value) {
    _destination.text = value.name;
    setState(() {
      _destinationQuery = value.name.toLowerCase();
      _showDestinationList = false;
      _searched = false;
    });
  }

  void _findRides() {
    FocusScope.of(context).unfocus();
    if (_pickup.text.trim().isEmpty || _destination.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter pickup and destination.')));
      return;
    }
    setState(() {
      _destinationQuery = _destination.text.trim().toLowerCase();
      _showDestinationList = false;
      _searched = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(MediaQuery.sizeOf(context).height * .62, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
    });
  }

  List<LiveTourPackage> _matchingRides(List<LiveTourPackage> source) {
    if (!_searched) return const [];
    final q = _destinationQuery;
    return source.where((ride) => '${ride.destination} ${ride.title} ${ride.pickupPoint}'.toLowerCase().contains(q)).toList()
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstName(String value) {
    final clean = value.trim();
    return clean.isEmpty ? 'Traveller' : clean.split(RegExp(r'\s+')).first;
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _tripTimer?.cancel();
    _pickup.dispose();
    _destination.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final rides = _matchingRides(controller.liveMarketplacePackages);
    final height = MediaQuery.sizeOf(context).height;

    return ColoredBox(
      color: _navy,
      child: RefreshIndicator(
        color: _lime,
        onRefresh: () async => Future.wait([_loadDestinations(), _loadMarketplace(), _loadLocation()]),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: height - 86,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _HeroSlider(
                      items: _destinations,
                      loading: _loadingDestinations,
                      controller: _pageController,
                      onChanged: (value) => setState(() => _heroIndex = value),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x8A03101A), Color(0x12031923), Color(0xF2061923)],
                          stops: [0, .48, 1],
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _CircleButton(icon: Icons.menu_rounded, onTap: () => Scaffold.of(context).openDrawer()),
                                const Spacer(),
                                if (_activeTrip != null) ...[
                                  _CircleButton(icon: Icons.route_rounded, onTap: _openActiveTrip, showDot: true),
                                  const SizedBox(width: 9),
                                ],
                                _CircleButton(icon: Icons.notifications_none_rounded, onTap: () => widget.onNavigate('notifications')),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text('$_greeting, ${_firstName(controller.currentUserName)}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                            const SizedBox(height: 5),
                            Text(_destinations.isEmpty ? 'Explore Kashmir' : _destinations[_heroIndex.clamp(0, _destinations.length - 1)].name, style: const TextStyle(color: _lime, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
                              decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white.withValues(alpha: .12)), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 28, offset: Offset(0, 12))]),
                              child: Column(
                                children: [
                                  _LocationInput(controller: _pickup, label: 'From', icon: Icons.my_location_rounded, accent: _lime, hint: 'Enter pickup point manually'),
                                  Divider(height: 18, color: Colors.white.withValues(alpha: .1)),
                                  _LocationInput(
                                    controller: _destination,
                                    label: 'To',
                                    icon: Icons.location_on_rounded,
                                    accent: const Color(0xFFFFA13A),
                                    hint: 'Where do you want to go?',
                                    readOnly: true,
                                    onTap: () => setState(() => _showDestinationList = !_showDestinationList),
                                    suffix: Icon(_showDestinationList ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    child: !_showDestinationList ? const SizedBox.shrink() : _DestinationDropdown(items: _destinations, onSelected: _selectDestination),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 13),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton.icon(
                                onPressed: _findRides,
                                style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: const Color(0xFF102006), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                                icon: const Icon(Icons.directions_car_filled_rounded, size: 20),
                                label: const Text('Find rides', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_destinations.length, (index) => AnimatedContainer(duration: const Duration(milliseconds: 180), width: index == _heroIndex ? 18 : 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: index == _heroIndex ? _lime : Colors.white38, borderRadius: BorderRadius.circular(10))))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_searched)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 125),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(children: [const Expanded(child: Text('Available rides', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900))), Text('${rides.length} found', style: const TextStyle(color: _lime, fontSize: 11, fontWeight: FontWeight.w800))]),
                    const SizedBox(height: 12),
                    if (rides.isEmpty)
                      _EmptyRides(destination: _destination.text)
                    else
                      ...rides.map(
                        (ride) => Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: _RideCard(
                            ride: ride,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LivePackageDetailScreen(
                                  package: ride,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroDestination {
  const _HeroDestination({required this.name, required this.district, required this.summary, required this.imageUrl});
  final String name;
  final String district;
  final String summary;
  final String imageUrl;
}

const _fallbackDestinations = <_HeroDestination>[
  _HeroDestination(name: 'Neelum Valley', district: 'Azad Kashmir', summary: 'Mountains, rivers and unforgettable journeys', imageUrl: 'https://images.unsplash.com/photo-1595815771614-ade9d652a65d?auto=format&fit=crop&w=1400&q=85'),
  _HeroDestination(name: 'Gulmarg', district: 'Kashmir', summary: 'Snow, gondolas and alpine adventure', imageUrl: 'https://images.unsplash.com/photo-1598091383021-15ddea10925d?auto=format&fit=crop&w=1400&q=85'),
  _HeroDestination(name: 'Dal Lake', district: 'Srinagar', summary: 'Shikara rides and beautiful houseboats', imageUrl: 'https://images.unsplash.com/photo-1621232082074-1a7750ecc557?auto=format&fit=crop&w=1400&q=85'),
];

class _HeroSlider extends StatelessWidget {
  const _HeroSlider({required this.items, required this.loading, required this.controller, required this.onChanged});
  final List<_HeroDestination> items;
  final bool loading;
  final PageController controller;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    if (loading || items.isEmpty) return const ColoredBox(color: Color(0xFF0A2834), child: Center(child: CircularProgressIndicator(color: Color(0xFF8ED12B))));
    return PageView.builder(
      controller: controller,
      itemCount: items.length,
      onPageChanged: onChanged,
      itemBuilder: (_, index) => Image.network(items[index].imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0A2834), child: Center(child: Icon(Icons.landscape_rounded, color: Colors.white54, size: 70)))),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap, this.showDot = false});
  final IconData icon; final VoidCallback onTap; final bool showDot;
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent, child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: Ink(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xC90A1820), shape: BoxShape.circle, border: Border.all(color: Colors.white12)), child: Stack(alignment: Alignment.center, children: [Icon(icon, color: Colors.white, size: 22), if (showDot) const Positioned(right: 7, top: 7, child: CircleAvatar(radius: 4, backgroundColor: Color(0xFF8ED12B)))]))));
}

class _LocationInput extends StatelessWidget {
  const _LocationInput({required this.controller, required this.label, required this.icon, required this.accent, required this.hint, this.readOnly = false, this.onTap, this.suffix});
  final TextEditingController controller; final String label; final IconData icon; final Color accent; final String hint; final bool readOnly; final VoidCallback? onTap; final Widget? suffix;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(top: 17), child: Icon(icon, color: accent, size: 20)), const SizedBox(width: 10), Expanded(child: TextField(controller: controller, readOnly: readOnly, onTap: onTap, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700), decoration: InputDecoration(isDense: true, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 4), labelText: label, labelStyle: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.w800), hintText: hint, hintStyle: const TextStyle(color: Colors.white54, fontSize: 12), suffixIcon: suffix, suffixIconConstraints: const BoxConstraints(minWidth: 32))))]);
}

class _DestinationDropdown extends StatelessWidget {
  const _DestinationDropdown({required this.items, required this.onSelected});
  final List<_HeroDestination> items; final ValueChanged<_HeroDestination> onSelected;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(top: 10), constraints: const BoxConstraints(maxHeight: 210), decoration: BoxDecoration(color: const Color(0xFF142B35), borderRadius: BorderRadius.circular(16)), child: ListView.separated(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 5), itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10), itemBuilder: (_, index) { final item = items[index]; return ListTile(dense: true, onTap: () => onSelected(item), leading: ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.network(item.imageUrl, width: 42, height: 42, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 42, height: 42, child: Icon(Icons.landscape_rounded, color: Colors.white54)))), title: Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)), subtitle: Text(item.district, style: const TextStyle(color: Color(0xFF9EADB4), fontSize: 10)), trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8ED12B), size: 20)); }));
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, required this.onTap});
  final LiveTourPackage ride; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Ink(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF10242D), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(children: [Container(width: 88, height: 72, decoration: BoxDecoration(color: const Color(0xFF1A3039), borderRadius: BorderRadius.circular(14)), child: ride.coverImageUrl?.isNotEmpty == true ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(ride.coverImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.directions_car_filled_rounded, color: Colors.white70, size: 42))) : const Icon(Icons.directions_car_filled_rounded, color: Colors.white70, size: 42)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(ride.vehicle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text('${ride.pickupPoint} → ${ride.destination}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFAAB7BD), fontSize: 10.5, height: 1.3)), const SizedBox(height: 8), Row(children: [const Icon(Icons.event_seat_rounded, size: 14, color: Color(0xFF8ED12B)), Text(' ${ride.availableSeats} seats', style: const TextStyle(color: Colors.white70, fontSize: 10)), const SizedBox(width: 10), const Icon(Icons.schedule_rounded, size: 14, color: Colors.white54), Text(' ${DateFormat('dd MMM, hh:mm a').format(ride.departureAt)}', style: const TextStyle(color: Colors.white70, fontSize: 10))])])), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('PKR ${ride.pricePerSeat.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF8ED12B), fontSize: 13, fontWeight: FontWeight.w900)), const Text('per seat', style: TextStyle(color: Colors.white54, fontSize: 9)), const SizedBox(height: 14), const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)])]))));
}

class _EmptyRides extends StatelessWidget {
  const _EmptyRides({required this.destination});
  final String destination;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF10242D), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white10)), child: Column(children: [const Icon(Icons.directions_car_outlined, color: Color(0xFF8ED12B), size: 38), const SizedBox(height: 10), const Text('No matching ride available', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text('No active ride is currently going towards $destination.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFAAB7BD), fontSize: 11, height: 1.4))]));
}
