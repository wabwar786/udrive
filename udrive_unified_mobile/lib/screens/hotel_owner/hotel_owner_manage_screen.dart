import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/hotel_models.dart';

/// H-03 — one hotel: where it stands, who has booked, and what rooms it sells.
///
/// Pushed from the dashboard, so it keeps its own `Scaffold`.
class HotelOwnerManageScreen extends StatefulWidget {
  const HotelOwnerManageScreen({required this.hotel, super.key});

  final HotelSummary hotel;

  @override
  State<HotelOwnerManageScreen> createState() => _HotelOwnerManageScreenState();
}

class _HotelOwnerManageScreenState extends State<HotelOwnerManageScreen> {
  List<Map<String, dynamic>> _bookings = [];

  /// The room types this hotel sells.
  ///
  /// The artboard has them and the screen did not — it loaded bookings only,
  /// so an owner could add a room type and never see the list they had just
  /// added to. `details()` already returns them; nothing new is asked of the
  /// server.
  List<HotelRoom> _rooms = const [];

  bool _busy = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    final repository =
        HotelRepository(AppControllerScope.of(context).apiClient);
    try {
      _bookings = await repository.ownerBookings(hotelId: widget.hotel.id);
    } catch (_) {
      // A failed booking list leaves the rest of the screen usable.
    }
    try {
      final details = await repository.details(widget.hotel.id);
      _rooms = details.rooms;
    } catch (_) {
      // Same: room types are worth showing, not worth blocking the page.
    }
    if (mounted) setState(() => _busy = false);
  }

  static String _money(Object? value) {
    final number = value is num ? value : num.tryParse('$value') ?? 0;
    return 'PKR ${NumberFormat('#,###').format(number.round())}';
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.hotel.approvalStatus ?? 'Pending';
    final approved = status == 'Approved';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: widget.hotel.name,
        onBack: () => Navigator.pop(context),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
          children: [
            UdCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Status: $status',
                          style: AppType.h3.copyWith(color: AppText.primary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      UdBadge(
                        label: approved ? 'Live' : status,
                        tone: approved
                            ? UdTone.ok
                            : status == 'Rejected'
                                ? UdTone.err
                                : UdTone.warn,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Only approved hotels are visible to customers. '
                    '${widget.hotel.city} · ${widget.hotel.availableRooms} '
                    'rooms listed.',
                    style: AppType.small
                        .copyWith(height: 1.45, color: AppText.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            UdSectionHeader(
              title: 'Recent bookings',
              caption: _bookings.isEmpty ? null : '${_bookings.length}',
            ),
            const SizedBox(height: 12),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.navy),
                ),
              )
            else if (_bookings.isEmpty)
              const UdEmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No bookings yet',
                text: 'Bookings customers make on this hotel appear here.',
              )
            else
              for (final booking in _bookings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BookingCard(booking: booking, money: _money),
                ),

            const SizedBox(height: 26),
            UdSectionHeader(
              title: 'Room types',
              caption: _rooms.isEmpty ? null : '${_rooms.length}',
            ),
            const SizedBox(height: 12),
            if (!_busy && _rooms.isEmpty)
              const UdEmptyState(
                icon: Icons.bed_outlined,
                title: 'No room type yet',
                text: 'Add at least one room type so customers can book.',
              )
            else if (_rooms.isNotEmpty)
              UdListGroup(
                children: [
                  for (final room in _rooms)
                    UdListRow(
                      title: room.roomType,
                      subtitle: 'Sleeps ${room.capacity} · '
                          '${room.availableRooms} '
                          'room${room.availableRooms == 1 ? '' : 's'} free',
                      leading: const UdIconTile(
                        icon: Icons.bed_rounded,
                        tone: UdIconTone.soft,
                      ),
                      trailing: Text(
                        _money(room.rate),
                        style: AppType.listTitle.copyWith(
                          fontSize: 15.5,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 22),
            // Was a floating action button, which v2 does not have.
            UdButton.primary(
              label: 'Add room type',
              icon: Icons.bed_rounded,
              onPressed: _addRoom,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRoom() async {
    final type = TextEditingController();
    final capacity = TextEditingController(text: '2');
    final total = TextEditingController(text: '1');
    final rate = TextEditingController();

    final ok = await showUdSheet<bool>(
          context: context,
          builder: (sheetContext) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Add room type',
                  style: AppType.h2.copyWith(color: AppText.primary),
                ),
                const SizedBox(height: 16),
                UdTextField(
                  controller: type,
                  label: 'Room type',
                  hint: 'e.g. Deluxe River View',
                  icon: Icons.bed_outlined,
                  autofocus: true,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: UdTextField(
                        controller: capacity,
                        label: 'Sleeps',
                        icon: Icons.people_alt_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: UdTextField(
                        controller: total,
                        label: 'Total rooms',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                UdTextField(
                  controller: rate,
                  label: 'Base rate per night',
                  labelSuffix: 'PKR',
                  icon: Icons.payments_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                UdButtonRow(
                  children: [
                    UdButton.outline(
                      label: 'Cancel',
                      onPressed: () => Navigator.pop(sheetContext, false),
                    ),
                    UdButton.primary(
                      label: 'Add',
                      onPressed: () => Navigator.pop(sheetContext, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!ok || type.text.trim().isEmpty) return;
    if (!mounted) return;

    await HotelRepository(AppControllerScope.of(context).apiClient)
        .addRoom(widget.hotel.id, {
      'roomType': type.text.trim(),
      'description': '',
      'capacity': int.tryParse(capacity.text) ?? 2,
      'totalRooms': int.tryParse(total.text) ?? 1,
      'baseRate': double.tryParse(rate.text) ?? 0,
      'imageUrl': '',
      'amenities': <String>[],
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room type added.')),
    );
    // The list the owner just added to now reloads, rather than staying as it
    // was until they left the screen and came back.
    await _load();
  }
}

/// One booking on this hotel.
class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.money});

  final Map<String, dynamic> booking;
  final String Function(Object?) money;

  static UdTone _tone(String status) => switch (status) {
        'Confirmed' => UdTone.lime,
        'Completed' => UdTone.ok,
        'Cancelled' => UdTone.err,
        _ => UdTone.warn,
      };

  @override
  Widget build(BuildContext context) {
    final status = '${booking['status'] ?? ''}';
    final payment = '${booking['paymentStatus'] ?? ''}';

    return UdCard(
      tone: UdCardTone.flat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const UdIconTile(
                icon: Icons.bed_outlined,
                tone: UdIconTone.neutral,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${booking['roomType']} · ${booking['rooms']} '
                      'room${booking['rooms'] == 1 ? '' : 's'}',
                      style: AppType.listTitle
                          .copyWith(fontSize: 16, color: AppText.primary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${booking['checkIn']} → ${booking['checkOut']}',
                      style:
                          AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                money(booking['amount']),
                style: AppType.priceMd.copyWith(color: AppText.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              UdBadge(label: status, tone: _tone(status)),
              const SizedBox(width: 8),
              UdBadge(
                label: payment,
                tone: payment == 'Paid' ? UdTone.ok : UdTone.gray,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
