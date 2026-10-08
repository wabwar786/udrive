import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/money.dart';
import '../../core/hotels/hotel_owner_dashboard_repository.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import 'hotel_owner_manage_screen.dart';

/// H-01 — the hotel owner's home: new bookings, who arrives and leaves
/// today, and how many rooms are free over the next seven days.
///
/// Bookings are confirmed when the customer books — nothing here to accept.
/// The owner only marks a guest arrived or gone.
///
/// The first tab of the hotel owner shell, which draws the bar — no
/// `Scaffold` here.
class HotelOwnerDashboard extends StatefulWidget {
  const HotelOwnerDashboard({super.key});

  @override
  State<HotelOwnerDashboard> createState() => _HotelOwnerDashboardState();
}

class _HotelOwnerDashboardState extends State<HotelOwnerDashboard> {
  late final HotelOwnerDashboardRepository _repository =
      HotelOwnerDashboardRepository(AppControllerScope.of(context).apiClient);

  OwnerHotelDashboard? _data;
  String? _error;
  String? _hotelId;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await _repository.load(hotelId: _hotelId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _hotelId = data.hotelId;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _mark(OwnerHotelBooking booking, String status) async {
    setState(() => _busyId = booking.id);
    try {
      _snack(await _repository.setStatus(booking.id, status));
      await _load();
    } on ApiException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null) {
      _snack('Guest ka number nahi mila.');
      return;
    }
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      _snack('Dialer nahi khul saka.');
    }
  }

  Future<void> _message(String? phone, String name) async {
    if (phone == null) {
      _snack('Guest ka number nahi mila.');
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final choice = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$name ko message',
              style: AppType.h3.copyWith(color: AppText.primary)),
          const SizedBox(height: 14),
          UdButton.primary(
            label: 'WhatsApp',
            icon: Icons.chat_rounded,
            onPressed: () => Navigator.pop(sheetContext, 'wa'),
          ),
          const SizedBox(height: 10),
          UdButton.outline(
            label: 'SMS',
            icon: Icons.sms_outlined,
            onPressed: () => Navigator.pop(sheetContext, 'sms'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final uri = choice == 'wa'
        ? Uri.parse('https://wa.me/$digits')
        : Uri(scheme: 'sms', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Message app nahi khul saka.');
    }
  }

  /// Room types are managed on the existing hotel screen.
  Future<void> _manage() async {
    final id = _hotelId;
    if (id == null) return;
    try {
      final hotels = await HotelRepository(
        AppControllerScope.of(context).apiClient,
      ).myHotels();
      final hotel = hotels.where((h) => h.id == id).toList();
      if (hotel.isEmpty || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HotelOwnerManageScreen(hotel: hotel.first),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      _snack('$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
          : ListView(
              padding: const EdgeInsets.all(AppSizes.sidePadding),
              children: [
                UdEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Load nahi ho saka',
                  text: _error,
                  action: UdButton.outline(
                    label: 'Dobara koshish',
                    expand: false,
                    onPressed: _load,
                  ),
                ),
              ],
            );
    }

    final hotel = data.hotel;
    if (hotel == null) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSizes.sidePadding),
          children: const [
            UdEmptyState(
              icon: Icons.apartment_outlined,
              title: 'Abhi koi hotel nahi',
              text: 'Neeche "Add hotel" se apna hotel bhejein — admin approve '
                  'kare to customers ko dikhega.',
            ),
          ],
        ),
      );
    }

    final today = [
      for (final b in data.checkInsToday) (b, true),
      for (final b in data.checkOutsToday) (b, false),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 10, AppSizes.sidePadding, 40),
        children: [
          _Header(
            data: data,
            hotel: hotel,
            onSwitch: (id) {
              setState(() => _hotelId = id);
              _load();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _Stat(value: '${data.newBookings}', label: 'Nayi bookings')),
              const SizedBox(width: 8),
              Expanded(
                  child: _Stat(
                      value: '${data.freeRoomsToday} / ${data.totalRooms}',
                      label: 'Aaj khali kamre')),
              const SizedBox(width: 8),
              Expanded(
                  child: _Stat(value: _short(data.monthAmount), label: 'Is mahine')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Nayi bookings — confirm ho chuki',
              style: AppType.section.copyWith(color: AppText.primary)),
          const SizedBox(height: 10),
          if (data.bookings.isEmpty)
            const UdEmptyState(
              icon: Icons.event_available_rounded,
              title: 'Abhi koi booking nahi',
              text: 'Customer kamra book karega to yahan aa jayegi — aap ko '
                  'accept nahi karna.',
            )
          else
            for (final booking in data.bookings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BookingCard(
                  booking: booking,
                  onCall: () => _call(booking.guestPhone),
                  onMessage: () => _message(booking.guestPhone, booking.guestName),
                ),
              ),
          if (today.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Aaj',
                style: AppType.section.copyWith(color: AppText.primary)),
            const SizedBox(height: 10),
            for (final (booking, arriving) in today)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TodayCard(
                  booking: booking,
                  arriving: arriving,
                  busy: _busyId == booking.id,
                  onAction: () =>
                      _mark(booking, arriving ? 'CheckedIn' : 'CheckedOut'),
                ),
              ),
          ],
          if (data.rooms.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Kamre — agle 7 din (khali)',
                style: AppType.section.copyWith(color: AppText.primary)),
            const SizedBox(height: 10),
            _RoomsGrid(rooms: data.rooms, today: data.today),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: UdButton.outline(
                  label: '+ Room type',
                  size: UdButtonSize.small,
                  onPressed: _manage,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: UdButton.outline(
                  label: 'Hotel manage karein',
                  size: UdButtonSize.small,
                  onPressed: _manage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _short(double value) => value >= 1000
      ? 'PKR ${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
      : Money.amount(value);
}

final _day = DateFormat('d MMM');

class _Header extends StatelessWidget {
  const _Header({
    required this.data,
    required this.hotel,
    required this.onSwitch,
  });

  final OwnerHotelDashboard data;
  final OwnerHotel hotel;
  final ValueChanged<String> onSwitch;

  @override
  Widget build(BuildContext context) {
    final link = ApiConfig.absoluteUrl(hotel.photoUrl);
    final (String badge, Color wash, Color ink) = switch (hotel.approvalStatus) {
      'Approved' => ('LIVE', AppColors.brand, AppColors.navy),
      'Rejected' => ('REJECTED', AppTint.danger, AppTint.dangerText),
      _ => ('REVIEW MEIN', AppTint.warning, AppTint.warningText),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadii.all(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: AppRadii.all(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: link.isEmpty
                      ? const ColoredBox(
                          color: AppColors.inkTile,
                          child: Icon(Icons.hotel_rounded,
                              color: AppColors.onInkMuted),
                        )
                      : Image.network(
                          link,
                          fit: BoxFit.cover,
                          cacheWidth: 156,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: AppColors.inkTile,
                            child: Icon(Icons.hotel_rounded,
                                color: AppColors.onInkMuted),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.onInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${hotel.city} · ${hotel.roomTypes} room types · '
                      '${hotel.totalRooms} kamre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppType.caption.copyWith(color: AppColors.onInkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: wash,
                  borderRadius: AppRadii.all(8),
                ),
                child: Text(
                  badge,
                  style: AppType.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          if (data.hotels.length > 1) ...[
            const SizedBox(height: 10),
            Text('Hotel badlein',
                style: AppType.caption.copyWith(color: AppColors.onInkMuted)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.inkPanel,
                borderRadius: AppRadii.all(10),
                border: Border.all(color: AppColors.navyLine),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: hotel.id,
                  isExpanded: true,
                  dropdownColor: AppColors.inkPanel,
                  iconEnabledColor: AppText.onInk,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.onInk,
                  ),
                  items: [
                    for (final h in data.hotels)
                      DropdownMenuItem(
                        value: h.id,
                        child: Text(
                          h.city.isEmpty ? h.name : '${h.name} — ${h.city}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null && id != hotel.id) onSwitch(id);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.h3.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(11),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(11)),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _initial(String name) => Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.navy,
        shape: BoxShape.circle,
      ),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: AppType.listTitle.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.brand,
        ),
      ),
    );

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onCall,
    required this.onMessage,
  });

  final OwnerHotelBooking booking;
  final VoidCallback onCall;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final line = [
      b.roomType,
      '${b.rooms} ${b.rooms == 1 ? 'kamra' : 'kamre'}',
      '${b.guests} log',
      if (b.transport) 'pickup chahiye',
    ].join(' · ');
    final dates = '${_day.format(b.checkIn)} – ${_day.format(b.checkOut)} · '
        '${b.nights} ${b.nights == 1 ? 'raat' : 'raatein'}'
        '${b.arrivalTime == null ? '' : ' · aamad ${b.arrivalTime}'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _initial(b.guestName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.guestName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style: AppType.caption.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              Text(
                Money.amount(b.amount),
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(dates, style: AppType.caption.copyWith(color: AppText.secondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SmallButton(label: 'Call', onTap: onCall)),
              const SizedBox(width: 8),
              Expanded(child: _SmallButton(label: 'Message', onTap: onMessage)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.booking,
    required this.arriving,
    required this.busy,
    required this.onAction,
  });

  final OwnerHotelBooking booking;
  final bool arriving;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final line = '${b.roomType} · ${b.rooms} ${b.rooms == 1 ? 'kamra' : 'kamre'}'
        '${arriving && b.arrivalTime != null ? ' · ${b.arrivalTime}' : ''}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: arriving ? AppTint.success : AppTint.info,
              borderRadius: AppRadii.all(6),
            ),
            child: Text(
              arriving ? 'CHECK-IN' : 'CHECK-OUT',
              style: AppType.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: arriving ? AppTint.successText : AppTint.infoText,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.guestName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(line,
                    style: AppType.caption.copyWith(color: AppText.secondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          UdButton.dark(
            label: arriving ? 'Aa gaye' : 'Chale gaye',
            size: UdButtonSize.small,
            expand: false,
            busy: busy,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// Room types down the side, the next seven nights across; each cell is how
/// many rooms of that type are still free that night.
class _RoomsGrid extends StatelessWidget {
  const _RoomsGrid({required this.rooms, required this.today});

  final List<OwnerHotelRoom> rooms;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    final dayFormat = DateFormat('E d');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 86),
              for (final d in days)
                Expanded(
                  child: Text(
                    dayFormat.format(d),
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppText.secondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final room in rooms) ...[
            Row(
              children: [
                SizedBox(
                  width: 86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.roomType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                      Text(
                        '${Money.plain(room.rate)} / raat',
                        style: AppType.caption.copyWith(
                          fontSize: 10.5,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _cell(i < room.freePerDay.length ? room.freePerDay[i] : 0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            'Number = us din kitne kamre khali. Peela = sab bhar gaye.',
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ],
      ),
    );
  }

  Widget _cell(int free) {
    final full = free <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: full ? AppTint.warning : AppTint.success,
        borderRadius: AppRadii.all(7),
      ),
      child: Text(
        '$free',
        style: AppType.small.copyWith(
          fontWeight: FontWeight.w800,
          color: full ? AppTint.warningText : AppTint.successText,
        ),
      ),
    );
  }
}
