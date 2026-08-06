import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../models/hotel_models.dart';
import '../customer/udrive_route_flow_screen.dart';

const _ink = Color(0xFF0C0E0D);
const _card = Color(0xFF151816);
const _tile = Color(0xFF232724);
const _lime = Color(0xFFB7F20A);
const _muted = Color(0xFF9AA09A);

class HotelDetailScreen extends StatefulWidget {
  const HotelDetailScreen({required this.hotel, required this.checkIn, required this.checkOut, super.key});
  final HotelSummary hotel;
  final DateTime checkIn, checkOut;
  @override
  State<HotelDetailScreen> createState() => _HotelDetailScreenState();
}

class _HotelDetailScreenState extends State<HotelDetailScreen> {
  HotelDetails? _details;
  bool _busy = true;
  late HotelRepository _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = HotelRepository(AppControllerScope.of(context).apiClient);
    if (_details == null) _load();
  }

  Future<void> _load() async {
    try {
      _details = await _repo.details(widget.hotel.id, checkIn: widget.checkIn, checkOut: widget.checkOut);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rideToHotel() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UDriveRouteFlowScreen(
            serviceType: UDriveServiceType.city,
            pickupLabel: 'Current location',
            pickupPoint: const LatLng(34.3700, 73.4700),
            initialDestinationLabel: '${widget.hotel.name} — ${widget.hotel.address}',
            initialDestinationLatitude: widget.hotel.latitude,
            initialDestinationLongitude: widget.hotel.longitude,
            skipRouteEntry: true,
          ),
        ),
      );

  Future<void> _book(HotelRoom room, bool transport) async {
    await _repo.book(widget.hotel.id, {
      'roomId': room.id,
      'checkIn': widget.checkIn.toIso8601String().substring(0, 10),
      'checkOut': widget.checkOut.toIso8601String().substring(0, 10),
      'guests': 2,
      'rooms': 1,
      'includeTransport': transport,
    });
    if (!mounted) return;
    if (!transport) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hotel booking confirmed.')));
      Navigator.pop(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UDriveRouteFlowScreen(
          serviceType: UDriveServiceType.tours,
          pickupLabel: 'Current location',
          pickupPoint: const LatLng(34.3700, 73.4700),
          initialDestinationLabel: '${widget.hotel.name} — ${widget.hotel.address}',
          initialDestinationLatitude: widget.hotel.latitude,
          initialDestinationLongitude: widget.hotel.longitude,
          skipRouteEntry: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotel = widget.hotel;
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        backgroundColor: _ink,
        surfaceTintColor: _ink,
        foregroundColor: Colors.white,
        title: Text(hotel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator(color: _lime))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: hotel.mainImageUrl.isEmpty
                        ? const ColoredBox(color: Color(0xFF20241F), child: Icon(Icons.hotel_rounded, size: 66, color: _lime))
                        : Image.network(hotel.mainImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Color(0xFF20241F), child: Icon(Icons.hotel_rounded, size: 66, color: _lime))),
                  ),
                ),
                const SizedBox(height: 14),
                Text(hotel.name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.location_on_rounded, size: 14, color: _muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text('${hotel.city} • ${hotel.address}', style: const TextStyle(color: _muted, fontSize: 11.5))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _chip(Icons.star_rounded, hotel.rating.toStringAsFixed(1)),
                  const SizedBox(width: 8),
                  _chip(Icons.meeting_room_rounded, '${hotel.availableRooms} rooms'),
                  const SizedBox(width: 8),
                  if (hotel.startingRate > 0) _chip(Icons.payments_rounded, 'From PKR ${hotel.startingRate.toStringAsFixed(0)}'),
                ]),
                if ((_details?.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_details!.description, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _rideToHotel,
                    icon: const Icon(Icons.local_taxi_rounded, size: 19),
                    label: const Text('Book a ride to this hotel', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Available rooms', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                for (final room in _details!.rooms) _RoomCard(room: room, onBook: _book),
                if (_details!.rooms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No rooms available for these dates.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
              ],
            ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: _lime),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onBook});
  final HotelRoom room;
  final Future<void> Function(HotelRoom room, bool transport) onBook;

  @override
  Widget build(BuildContext context) {
    final soldOut = room.availableRooms < 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 66,
              height: 60,
              decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.bed_rounded, size: 32, color: Colors.white70),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.roomType, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text('${room.capacity} guests • ${room.availableRooms} left',
                      style: TextStyle(color: soldOut ? const Color(0xFFE5484D) : _muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('PKR ${room.rate.toStringAsFixed(0)}', style: const TextStyle(color: _lime, fontSize: 14, fontWeight: FontWeight.w900)),
                const Text('per night', style: TextStyle(color: _muted, fontSize: 9)),
              ],
            ),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: soldOut ? null : () => onBook(room, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Room only', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: FilledButton(
                onPressed: soldOut ? null : () => onBook(room, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _lime,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Room + ride', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
