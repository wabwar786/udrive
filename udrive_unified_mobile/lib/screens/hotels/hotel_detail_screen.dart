import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../models/hotel_models.dart';
import '../customer/udrive_route_flow_screen.dart';

const _ink = AppColors.inkSurface;
const _card = AppColors.inkPanel;
const _tile = AppColors.inkTile;
const _lime = AppColors.brand;
const _muted = AppColors.onInkMuted;

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
  String? _error;
  /// The room id a booking is currently in flight for, and whether that
  /// booking asked for a ride as well. Null when nothing is in flight.
  ///
  /// A plain bool put a spinner on every room card at once, including rooms
  /// the customer had not touched.
  /// (room id, whether a ride was asked for as well).
  (String, bool)? _booking;
  late HotelRepository _repo;

  bool _loadStarted = false;

  // The guard is _loadStarted, not `_details == null`.
  //
  // AppControllerScope is an InheritedNotifier, and AppControllerScope.of makes
  // this State a dependent, so didChangeDependencies runs again on EVERY
  // notifyListeners() anywhere in the app. That was survivable only because
  // details() used to fall back to a demo object, which made _details non-null
  // on the first call and closed the guard for good. Now that it can fail and
  // leave _details null, the old guard never closes: booking a ride from this
  // screen notifies the controller, which silently re-fires the request, and a
  // late failure can overwrite a _details that had already arrived.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = HotelRepository(AppControllerScope.of(context).apiClient);
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  // This had a try/finally with no catch. When details() threw — which it does
  // whenever the request fails, and now also for any id the server does not
  // have — _details stayed null while `finally` cleared _busy, so build() went
  // straight to `_details!.rooms` and the screen crashed with a null-check
  // error. The failure is shown instead.
  Future<void> _load() async {
    try {
      final details = await _repo.details(widget.hotel.id, checkIn: widget.checkIn, checkOut: widget.checkOut);
      if (!mounted) return;
      setState(() {
        _details = details;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'This hotel\'s rooms could not be loaded. Check your connection and try again.');
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
    if (_booking != null) return;
    setState(() => _booking = (room.id, transport));
    try {
      await _repo.book(widget.hotel.id, {
        'roomId': room.id,
        'checkIn': widget.checkIn.toIso8601String().substring(0, 10),
        'checkOut': widget.checkOut.toIso8601String().substring(0, 10),
        'guests': 2,
        'rooms': 1,
        'includeTransport': transport,
      });
    } catch (_) {
      // Unhandled before: a failed booking left the button doing nothing at
      // all — no error, no confirmation — and the customer had no way to tell
      // whether they had a room.
      if (!mounted) return;
      setState(() => _booking = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('We could not complete this booking. Please try again.'),
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _booking = null);
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
                        ? const ColoredBox(color: AppColors.inkPanel, child: Icon(Icons.hotel_rounded, size: 66, color: _lime))
                        : Image.network(hotel.mainImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: AppColors.inkPanel, child: Icon(Icons.hotel_rounded, size: 66, color: _lime))),
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
                  Text(_details!.description, style: const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
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
                if (_error != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (_busy) return;
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          _load();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ]),
                  ),
                ] else ...[
                  for (final room in _details?.rooms ?? const <HotelRoom>[])
                    _RoomCard(room: room, onBook: _book, booking: _booking),
                  if ((_details?.rooms ?? const <HotelRoom>[]).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No rooms available for these dates.', style: TextStyle(color: _muted, fontSize: 12)),
                    ),
                ],
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
  const _RoomCard({required this.room, required this.onBook, required this.booking});
  final HotelRoom room;
  final Future<void> Function(HotelRoom room, bool transport) onBook;

  /// Which room a booking is in flight for, and whether it included a ride.
  ///
  /// Without any of this, a slow first tap looked like nothing had happened:
  /// the screen gave no feedback, so the customer tapped the other button,
  /// which returned immediately on the re-entry guard. The first request then
  /// completed, said "Hotel booking confirmed" and popped the screen — so
  /// somebody who asked for a room AND a ride got a room, and the screen was
  /// gone before they could tell. The spinner now marks the button they
  /// actually pressed; the rest are disabled but unchanged.
  final (String, bool)? booking;

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
              child: const Icon(Icons.bed_rounded, size: 32, color: _muted),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.roomType, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text('${room.capacity} guests • ${room.availableRooms} left',
                      style: TextStyle(color: soldOut ? AppColors.danger : _muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
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
                onPressed: soldOut || booking != null ? null : () => onBook(room, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: booking == (room.id, false)
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2.1))
                    : const Text('Room only', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: FilledButton(
                onPressed: soldOut || booking != null ? null : () => onBook(room, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _lime,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: booking == (room.id, true)
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2.1, color: Colors.black))
                    : const Text('Room + ride', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
