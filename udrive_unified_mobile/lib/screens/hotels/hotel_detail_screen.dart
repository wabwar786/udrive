import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/hotel_models.dart';
import '../customer/udrive_route_flow_screen.dart';

/// C-43 — one hotel, and the rooms it has for these dates.
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
    final rooms = _details?.rooms ?? const <HotelRoom>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: hotel.name,
        onBack: () => Navigator.maybePop(context),
        divider: true,
      ),
      body: _busy
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.navy),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 16, AppSizes.sidePadding, 34),
              children: [
                ClipRRect(
                  borderRadius: AppRadii.all(22),
                  child: SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: hotel.mainImageUrl.isEmpty
                        ? const _HotelHeroFallback()
                        : Image.network(
                            hotel.mainImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _HotelHeroFallback(),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  hotel.name,
                  style: AppType.h2.copyWith(color: AppText.primary),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.location_on_rounded,
                          size: 18, color: AppText.secondary),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${hotel.city} · ${hotel.address}',
                        style:
                            AppType.body2.copyWith(color: AppText.secondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Fact(Icons.star_rounded, hotel.rating.toStringAsFixed(1),
                        gold: true),
                    _Fact(Icons.meeting_room_rounded,
                        '${hotel.availableRooms} rooms'),
                    // Only when there is a rate to show — unchanged.
                    if (hotel.startingRate > 0)
                      _Fact(
                        Icons.payments_rounded,
                        'From PKR ${NumberFormat('#,###').format(hotel.startingRate)}',
                      ),
                  ],
                ),
                if ((_details?.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _details!.description,
                    style: AppType.body2.copyWith(color: AppText.secondary),
                  ),
                ],
                const SizedBox(height: 20),
                UdButton.outline(
                  label: 'Book a ride to this hotel',
                  icon: Icons.local_taxi_rounded,
                  onPressed: _rideToHotel,
                ),
                const SizedBox(height: 24),
                UdSectionHeader(
                  title: 'Available rooms',
                  caption: '${DateFormat('dd MMM').format(widget.checkIn)} – '
                      '${DateFormat('dd MMM').format(widget.checkOut)}',
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  UdBanner(
                    tone: UdTone.err,
                    icon: Icons.cloud_off_rounded,
                    trailing: UdButton.outline(
                      label: 'Try again',
                      size: UdButtonSize.xs,
                      expand: false,
                      onPressed: () {
                        if (_busy) return;
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        _load();
                      },
                    ),
                    text: _error!,
                  )
                else if (rooms.isEmpty)
                  const UdEmptyState(
                    icon: Icons.bed_rounded,
                    title: 'No rooms for these dates',
                    text: 'No rooms available for these dates. Try a different '
                        'check-in or check-out date.',
                  )
                else
                  for (final room in rooms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _RoomCard(
                        room: room,
                        onBook: _book,
                        booking: _booking,
                      ),
                    ),
              ],
            ),
    );
  }
}

/// A small outlined fact chip: the rating, the room count, the lowest rate.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, {this.gold = false});

  final IconData icon;
  final String label;

  /// Only the rating star is gold; nothing else in the app uses that hue.
  final bool gold;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(AppRadii.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: gold ? AppTint.star : AppText.secondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppType.caption.copyWith(
                fontSize: 13.5,
                color: AppText.primary,
              ),
            ),
          ],
        ),
      );
}

class _HotelHeroFallback extends StatelessWidget {
  const _HotelHeroFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTint.mapPark, AppTint.mapWater],
          ),
        ),
        child: Center(
          child: Icon(Icons.hotel_rounded,
              size: 64, color: AppColors.borderStrong),
        ),
      );
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.onBook,
    required this.booking,
  });

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
    final locked = soldOut || booking != null;

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const UdIconTile(
                icon: Icons.bed_rounded,
                size: UdIconTileSize.lg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.roomType,
                      style: AppType.listTitle.copyWith(
                        fontSize: 16,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${room.capacity} guests · ${room.availableRooms} left',
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        // Red only when there is nothing left to take.
                        color: soldOut ? AppColors.danger : AppText.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PKR ${NumberFormat('#,###').format(room.rate)}',
                    style: AppType.priceMd.copyWith(
                      fontSize: 19,
                      color: AppColors.brandInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'per night',
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          UdButtonRow(
            children: [
              UdButton.outline(
                label: 'Room only',
                size: UdButtonSize.small,
                busy: booking == (room.id, false),
                onPressed: locked ? null : () => onBook(room, false),
              ),
              UdButton.primary(
                label: 'Room + ride',
                size: UdButtonSize.small,
                busy: booking == (room.id, true),
                onPressed: locked ? null : () => onBook(room, true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
