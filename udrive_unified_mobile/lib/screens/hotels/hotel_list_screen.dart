import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../models/hotel_models.dart';
import '../customer/udrive_route_flow_screen.dart';
import '../hotel_owner/hotel_owner_add_screen.dart';
import 'hotel_detail_screen.dart';

const _ink = Color(0xFF0C0E0D);
const _card = Color(0xFF151816);
const _tile = Color(0xFF232724);
const _lime = Color(0xFFB7F20A);
const _muted = Color(0xFF9AA09A);

class HotelListScreen extends StatefulWidget {
  const HotelListScreen({this.destination, super.key});
  final String? destination;
  @override
  State<HotelListScreen> createState() => _HotelListScreenState();
}

class _HotelListScreenState extends State<HotelListScreen> {
  final _query = TextEditingController();
  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 2));
  int _guests = 2;
  int _rooms = 1;
  bool _busy = true;
  String? _loadError;
  List<HotelSummary> _items = const [];
  HotelRepository? _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_query.text.isEmpty && widget.destination != null) {
      _query.text = widget.destination!;
    }
    if (_repo != null) return;
    try {
      _repo = HotelRepository(AppControllerScope.of(context).apiClient);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } catch (error) {
      _busy = false;
      _loadError = 'Hotels service is not ready yet. Please retry.';
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      final repo = _repo;
      if (repo == null) {
        throw Exception('Hotels service is not ready yet.');
      }
      final loaded = await repo.search(
        query: _query.text,
        checkIn: _checkIn,
        checkOut: _checkOut,
        guests: _guests,
        rooms: _rooms,
      );
      if (!mounted) return;
      setState(() => _items = loaded);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loadError = '$error'.replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _openHotel(HotelSummary hotel) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HotelDetailScreen(hotel: hotel, checkIn: _checkIn, checkOut: _checkOut),
        ),
      );

  // Book a vehicle heading to the selected hotel (reuses the ride/booking flow).
  void _rideToHotel(HotelSummary hotel) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UDriveRouteFlowScreen(
            serviceType: UDriveServiceType.city,
            pickupLabel: 'Current location',
            pickupPoint: const LatLng(34.3700, 73.4700),
            initialDestinationLabel: '${hotel.name} — ${hotel.address}',
            initialDestinationLatitude: hotel.latitude,
            initialDestinationLongitude: hotel.longitude,
            skipRouteEntry: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        backgroundColor: _ink,
        surfaceTintColor: _ink,
        foregroundColor: Colors.white,
        title: const Text('Hotels & Stays', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Add your hotel',
            onPressed: () => _openAddHotel(),
            icon: const Icon(Icons.add_business_rounded),
          ),
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          if (_loadError != null) _errorBanner(),
          _addHotelBanner(),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator(color: _lime))
                : _items.isEmpty
                    ? _EmptyHotels(hasError: _loadError != null)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 28),
                        itemCount: _items.length,
                        itemBuilder: (context, index) => _HotelCard(
                          hotel: _items[index],
                          onOpen: () => _openHotel(_items[index]),
                          onRide: () => _rideToHotel(_items[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddHotel() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const HotelOwnerAddScreen(standalone: true)),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hotel submitted. It will appear here after admin approval.')),
      );
    }
  }

  Widget _errorBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF321E1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEA6B66).withValues(alpha: .45)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF8A80), size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _loadError ?? 'Hotels could not be loaded.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.3),
                ),
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _addHotelBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Material(
          color: const Color(0xFF20251F),
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: _openAddHotel,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: Color(0xFFB7F20A),
                    child: Icon(Icons.add_business_rounded, color: Colors.black, size: 20),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Own a hotel or guest house?', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900)),
                        SizedBox(height: 2),
                        Text('Add it for admin approval and publish it on UDrive.', style: TextStyle(color: Colors.white60, fontSize: 9.5)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          children: [
            TextField(
              controller: _query,
              onSubmitted: (_) => _load(),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.white70),
                hintText: 'Destination or hotel',
                hintStyle: const TextStyle(color: _muted, fontSize: 12.5),
                isDense: true,
                filled: true,
                fillColor: _tile,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, constraints) {
                final dateFields = [
                  Expanded(
                    child: _dateBox(
                      'Check-in',
                      _checkIn,
                      (date) => setState(() => _checkIn = date),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dateBox(
                      'Check-out',
                      _checkOut,
                      (date) => setState(() => _checkOut = date),
                    ),
                  ),
                ];

                if (constraints.maxWidth < 350) {
                  return Column(
                    children: [
                      Row(children: dateFields),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Search hotels'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _lime,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    ...dateFields,
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: IconButton.filled(
                        tooltip: 'Search hotels',
                        onPressed: _load,
                        style: IconButton.styleFrom(
                          backgroundColor: _lime,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );

  Widget _dateBox(String label, DateTime value, ValueChanged<DateTime> onPick) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            initialDate: value,
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: _muted)),
              const SizedBox(height: 1),
              Text('${value.day}/${value.month}/${value.year}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      );
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({required this.hotel, required this.onOpen, required this.onRide});
  final HotelSummary hotel;
  final VoidCallback onOpen;
  final VoidCallback onRide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 132,
                    width: double.infinity,
                    child: hotel.mainImageUrl.isEmpty
                        ? const ColoredBox(
                            color: Color(0xFF20241F),
                            child: Icon(Icons.hotel_rounded, size: 46, color: _lime),
                          )
                        : Image.network(
                            hotel.mainImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Color(0xFF20241F),
                              child: Icon(Icons.hotel_rounded, size: 46, color: _lime),
                            ),
                          ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, size: 13, color: _lime),
                        const SizedBox(width: 3),
                        Text(hotel.rating.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                  if (hotel.transportAvailable)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: _lime.withValues(alpha: .92), borderRadius: BorderRadius.circular(99)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.directions_car_rounded, size: 13, color: Colors.black),
                          SizedBox(width: 3),
                          Text('Transport', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hotel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text('${hotel.city} • ${hotel.address}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 11)),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Starts from', style: TextStyle(color: _muted, fontSize: 9.5)),
                            const SizedBox(height: 1),
                            Text(
                              hotel.startingRate > 0 ? 'PKR ${hotel.startingRate.toStringAsFixed(0)}' : 'Check rooms',
                              style: const TextStyle(color: _lime, fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text('${hotel.availableRooms} rooms',
                            style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onRide,
                            icon: const Icon(Icons.local_taxi_rounded, size: 17),
                            label: const Text('Book ride', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(44),
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onOpen,
                            icon: const Icon(Icons.bed_rounded, size: 17),
                            label: const Text('Book room', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                            style: FilledButton.styleFrom(
                              backgroundColor: _lime,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHotels extends StatelessWidget {
  const _EmptyHotels({required this.hasError});
  final bool hasError;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasError ? Icons.cloud_off_rounded : Icons.hotel_rounded,
                color: Colors.white24,
                size: 46,
              ),
              const SizedBox(height: 12),
              Text(
                hasError
                    ? 'Hotels are temporarily unavailable. Use Retry after the updated API is deployed.'
                    : 'No approved hotels match this search. Clear the destination and search again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
      );
}
