import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/hotel_models.dart';
import 'hotel_bits.dart';
import 'hotel_confirm_screen.dart';
import 'hotel_search_screen.dart';

/// C-43 — one hotel, and the rooms it has for these dates.
///
/// A big photograph with the details on a white sheet over it, the stay as one
/// tappable strip, rooms to swipe through, and the price and Book on a navy
/// bar. Pops with the changed [HotelQuery] when the customer changed their
/// dates here, so the list behind follows.
class HotelDetailScreen extends StatefulWidget {
  const HotelDetailScreen({
    required this.hotel,
    required this.checkIn,
    required this.checkOut,
    this.guests = 2,
    this.rooms = 1,
    super.key,
  });

  final HotelSummary hotel;
  final DateTime checkIn, checkOut;
  final int guests, rooms;

  @override
  State<HotelDetailScreen> createState() => _HotelDetailScreenState();
}

class _HotelDetailScreenState extends State<HotelDetailScreen> {
  late HotelQuery _stay = HotelQuery(
    query: '',
    checkIn: hotelDay(widget.checkIn),
    checkOut: hotelDay(widget.checkOut),
    guests: widget.guests,
    rooms: widget.rooms,
  );
  bool _stayChanged = false;

  HotelDetails? _details;
  bool _busy = true;
  String? _error;
  String? _roomId;
  bool _transport = false;
  bool _descriptionOpen = false;
  late HotelRepository _repo;
  bool _loadStarted = false;

  // The guard is _loadStarted: AppControllerScope.of makes this State a
  // dependent, so didChangeDependencies runs on every notifyListeners().
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = HotelRepository(AppControllerScope.of(context).apiClient);
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = await _repo.details(
        widget.hotel.id,
        checkIn: _stay.checkIn,
        checkOut: _stay.checkOut,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        final bookable = details.rooms
            .where((r) => r.availableRooms >= _stay.rooms)
            .toList();
        if (_roomId == null || !bookable.any((r) => r.id == _roomId)) {
          _roomId = bookable.isEmpty ? null : bookable.first.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'This hotel\'s rooms could not be loaded. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  HotelSummary get _hotel => _details?.hotel ?? widget.hotel;

  HotelRoom? get _room {
    final rooms = _details?.rooms ?? const <HotelRoom>[];
    for (final room in rooms) {
      if (room.id == _roomId) return room;
    }
    return null;
  }

  Future<void> _changeStay() async {
    final result = await Navigator.push<HotelQuery>(
      context,
      MaterialPageRoute(builder: (_) => HotelSearchScreen(initial: _stay)),
    );
    if (result == null || !mounted) return;
    setState(() {
      _stay = result;
      _stayChanged = true;
    });
    await _load();
  }

  void _book() {
    final room = _room;
    if (room == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HotelConfirmScreen(
          hotel: _hotel,
          room: room,
          stay: _stay,
          hotelTransport: _transport && _hotel.transportAvailable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotel = _hotel;
    final room = _room;
    final total = room == null ? 0.0 : room.rate * _stay.nights * _stay.rooms;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _stayChanged ? _stay : null);
      },
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: AppColors.background,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _Hero(
                      hotel: hotel,
                      onBack: () =>
                          Navigator.pop(context, _stayChanged ? _stay : null),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                        child: _sheet(hotel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _BottomBar(
              total: total,
              caption: room == null
                  ? 'Choose a room'
                  : '${room.roomType} · ${_stay.nights} '
                      '${_stay.nights == 1 ? 'night' : 'nights'}'
                      '${_stay.rooms > 1 ? ' · ${_stay.rooms} rooms' : ''}',
              onBook: room == null ? null : _book,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheet(HotelSummary hotel) {
    final details = _details;
    final description = details?.description.trim() ?? '';
    final amenities = details?.amenities ?? const <String>[];
    final area = [hotel.address, hotel.city]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hotel.name,
                    style: AppType.h2.copyWith(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    area,
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (hotel.rating > 0) ...[
              const SizedBox(width: 10),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: AppRadii.all(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hotel.rating.toStringAsFixed(1),
                      style: AppType.listTitle.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: AppText.onInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'RATING',
                      style: AppType.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // The stay, one strip.
        Material(
          color: AppColors.surface,
          borderRadius: AppRadii.all(16),
          child: InkWell(
            onTap: _changeStay,
            borderRadius: AppRadii.all(16),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _StayCell(label: 'CHECK-IN', value: hotelDate(_stay.checkIn)),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  _StayCell(
                      label: 'CHECK-OUT', value: hotelDate(_stay.checkOut)),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  _StayCell(
                    label: 'GUESTS',
                    value: '${_stay.guests} · ${_stay.rooms} '
                        '${_stay.rooms == 1 ? 'room' : 'rooms'}',
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (amenities.isNotEmpty) ...[
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: .95,
            children: [
              for (final amenity in amenities.take(8))
                _AmenityIcon(label: amenity),
            ],
          ),
          const SizedBox(height: 14),
        ],

        if (description.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(() => _descriptionOpen = !_descriptionOpen),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: description),
                  if (description.length > 140)
                    TextSpan(
                      text: _descriptionOpen ? '  Less' : '  More',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                ],
              ),
              maxLines: _descriptionOpen ? null : 3,
              overflow: _descriptionOpen
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: AppType.small.copyWith(
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        Text(
          'Rooms',
          style: AppType.h3.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppText.primary,
          ),
        ),
        const SizedBox(height: 10),
        _rooms(),
        const SizedBox(height: 16),

        if (hotel.transportAvailable) ...[
          Material(
            color: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.all(16),
              side: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            child: InkWell(
              onTap: () => setState(() => _transport = !_transport),
              customBorder:
                  RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: AppRadii.all(12),
                      ),
                      child: const Icon(Icons.airport_shuttle_rounded,
                          size: 20, color: AppColors.navy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pickup transport',
                            style: AppType.small.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                          Text(
                            'The hotel arranges your ride',
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Checkbox(
                      value: _transport,
                      activeColor: AppColors.navy,
                      onChanged: (value) =>
                          setState(() => _transport = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _rooms() {
    if (_busy && _details == null) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.navy),
        ),
      );
    }
    if (_error != null) {
      return UdBanner(
        tone: UdTone.err,
        text: _error,
        trailing: UdButton(
          label: 'Retry',
          variant: UdButtonVariant.ghost,
          size: UdButtonSize.xs,
          expand: false,
          onPressed: _load,
        ),
      );
    }
    final rooms = _details?.rooms ?? const <HotelRoom>[];
    if (rooms.isEmpty) {
      return Text(
        'No rooms are listed for these dates.',
        style: AppType.small.copyWith(color: AppText.secondary),
      );
    }
    return SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final room = rooms[index];
          final full = room.availableRooms < _stay.rooms;
          return _RoomCard(
            room: room,
            selected: room.id == _roomId,
            full: full,
            onTap: full ? null : () => setState(() => _roomId = room.id),
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.hotel, required this.onBack});

  final HotelSummary hotel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final hasLocation = hotel.latitude != 0 || hotel.longitude != 0;
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          HotelPhoto(url: hotel.mainImageUrl, radius: 0, iconSize: 64),
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    HotelBackButton(onTap: onBack),
                    const Spacer(),
                    if (hasLocation)
                      Material(
                        color: AppColors.background,
                        borderRadius: AppRadii.all(14),
                        child: InkWell(
                          onTap: () => navigateToHotel(
                              context, hotel.latitude, hotel.longitude),
                          borderRadius: AppRadii.all(14),
                          child: Container(
                            height: 44,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.navigation_rounded,
                                    size: 16, color: AppColors.navy),
                                const SizedBox(width: 6),
                                Text(
                                  'Directions',
                                  style: AppType.small.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StayCell extends StatelessWidget {
  const _StayCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: hotelOverline().copyWith(fontSize: 10.5)),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.small.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One amenity as a lime tile with an icon picked from its name.
class _AmenityIcon extends StatelessWidget {
  const _AmenityIcon({required this.label});

  final String label;

  IconData get _icon {
    final text = label.toLowerCase();
    if (text.contains('wi')) return Icons.wifi_rounded;
    if (text.contains('water') || text.contains('geyser')) {
      return Icons.water_drop_rounded;
    }
    if (text.contains('park')) return Icons.local_parking_rounded;
    if (text.contains('restaurant') ||
        text.contains('food') ||
        text.contains('breakfast')) {
      return Icons.restaurant_rounded;
    }
    if (text.contains('heat')) return Icons.local_fire_department_rounded;
    if (text.contains('tv')) return Icons.tv_rounded;
    if (text.contains('view') || text.contains('river')) {
      return Icons.landscape_rounded;
    }
    if (text.contains('family')) return Icons.family_restroom_rounded;
    if (text.contains('transport') || text.contains('pickup')) {
      return Icons.airport_shuttle_rounded;
    }
    return Icons.check_circle_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.brandWash,
            borderRadius: AppRadii.all(16),
          ),
          child: Icon(_icon, size: 22, color: AppColors.brandInk),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppText.primary,
          ),
        ),
      ],
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.selected,
    required this.full,
    required this.onTap,
  });

  final HotelRoom room;
  final bool selected;
  final bool full;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      '${room.capacity} ${room.capacity == 1 ? 'guest' : 'guests'}',
      ...room.amenities.take(2),
      if (full)
        'full'
      else if (room.availableRooms == 1)
        'last one'
      else
        '${room.availableRooms} left',
    ].join(' · ');

    return Opacity(
      opacity: full ? .55 : 1,
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(20),
          side: BorderSide(
            color: selected ? AppColors.navy : AppColors.border,
            width: selected ? 2 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 236,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HotelPhoto(
                        url: room.imageUrl,
                        radius: 0,
                        iconSize: 40,
                      ),
                      if (selected)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: AppRadii.all(9),
                            ),
                            child: Text(
                              'Selected',
                              style: AppType.caption.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.roomType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppText.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: Money.amount(room.rate),
                              style: AppType.listTitle.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppText.primary,
                              ),
                            ),
                            TextSpan(
                              text: ' / night',
                              style: AppType.caption.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppText.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.caption,
    required this.onBook,
  });

  final double total;
  final String caption;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    total > 0 ? Money.amount(total) : '—',
                    style: AppType.h2.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppText.onInk,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onInkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: onBook == null ? AppColors.navyLine : AppColors.brand,
              borderRadius: AppRadii.all(18),
              child: InkWell(
                onTap: onBook,
                borderRadius: AppRadii.all(18),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Book',
                        style: AppType.button.copyWith(
                          fontWeight: FontWeight.w800,
                          color: onBook == null
                              ? AppColors.onInkMuted
                              : AppColors.navy,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 22,
                          color: onBook == null
                              ? AppColors.onInkMuted
                              : AppColors.navy),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
