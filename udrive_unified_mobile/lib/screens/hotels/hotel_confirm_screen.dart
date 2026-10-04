import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../../models/hotel_models.dart';
import 'hotel_bits.dart';
import 'hotel_booked_screen.dart';

/// "Confirm your stay" — how the guest is coming, when they will reach, and
/// who they are.
///
/// Everything on this screen goes to the hotel on WhatsApp the moment the
/// booking is made, so the owner knows who to expect and when. A guest
/// driving their own car books exactly like anyone else; nothing here needs a
/// UDrive ride.
class HotelConfirmScreen extends StatefulWidget {
  const HotelConfirmScreen({
    required this.hotel,
    required this.room,
    required this.stay,
    this.hotelTransport = false,
    super.key,
  });

  final HotelSummary hotel;
  final HotelRoom room;
  final HotelQuery stay;

  /// Ticked "Pickup transport" on the hotel's page.
  final bool hotelTransport;

  @override
  State<HotelConfirmScreen> createState() => _HotelConfirmScreenState();
}

class _HotelConfirmScreenState extends State<HotelConfirmScreen> {
  late HotelArrivalMode _mode = widget.hotelTransport
      ? HotelArrivalMode.hotelTransport
      : HotelArrivalMode.ownCar;

  /// "14:00".
  String _arrival = '14:00';
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _car = TextEditingController();
  bool _prefilled = false;
  bool _busy = false;
  String? _error;

  static const List<String> _slots = [
    '10:00', '12:00', '14:00', '16:00', '18:00', '20:00', '22:00',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final controller = AppControllerScope.of(context);
    final name = controller.currentUserName;
    _name.text = name == 'Udrive User' ? '' : name;
    _phone.text = controller.currentUserPhone;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _car.dispose();
    super.dispose();
  }

  Future<void> _pickOtherTime() async {
    final parts = _arrival.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 14,
        minute: int.tryParse(parts.last) ?? 0,
      ),
      helpText: 'When will you reach?',
    );
    if (picked == null || !mounted) return;
    setState(() => _arrival =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _phone.text.replaceAll(RegExp(r'\D'), '').length >= 10;

  Future<void> _confirm() async {
    if (!_valid) {
      setState(() => _error =
          'Add your name and a mobile number the hotel can reach you on.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final stay = widget.stay;
    try {
      final repo = HotelRepository(AppControllerScope.of(context).apiClient);
      final result = await repo.book(widget.hotel.id, {
        'roomId': widget.room.id,
        'checkIn': stay.checkIn.toIso8601String().substring(0, 10),
        'checkOut': stay.checkOut.toIso8601String().substring(0, 10),
        'guests': stay.guests,
        'rooms': stay.rooms,
        'includeTransport': _mode == HotelArrivalMode.hotelTransport,
        'arrivalTime': _arrival,
        'arrivalMode': _mode.wire,
        'carNumber':
            _mode == HotelArrivalMode.ownCar ? _car.text.trim() : null,
        'guestName': _name.text.trim(),
        'guestPhone': _phone.text.trim(),
      });
      if (!mounted) return;
      final hotel = widget.hotel;
      final booked = HotelStay(
        id: '${result['bookingId'] ?? ''}',
        reference: '${result['reference'] ?? ''}',
        hotelId: hotel.id,
        hotelName: hotel.name,
        address: hotel.address,
        city: hotel.city,
        latitude: hotel.latitude,
        longitude: hotel.longitude,
        contactPhone: hotel.contactPhone,
        imageUrl: hotel.mainImageUrl,
        roomType: widget.room.roomType,
        checkIn: stay.checkIn,
        checkOut: stay.checkOut,
        guests: stay.guests,
        rooms: stay.rooms,
        amount: (result['amount'] as num?)?.toDouble() ??
            widget.room.rate * stay.nights * stay.rooms,
        status: 'Confirmed',
        arrivalTime: _arrival,
        arrivalMode: _mode,
        carNumber: _mode == HotelArrivalMode.ownCar && _car.text.trim().isNotEmpty
            ? _car.text.trim()
            : null,
        ownerNotified: result['ownerNotified'] == true,
      );
      // Replaces the whole hotel flow: Back from the confirmation goes to
      // where the customer started, not into a form that was already sent.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HotelBookedScreen(stay: booked, justBooked: true),
        ),
        (route) => route.isFirst,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : 'We could not complete this booking. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final total = widget.room.rate * stay.nights * stay.rooms;
    final arrivalLabel = hotelTimeLabel(_arrival);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Material(
                    color: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.all(14),
                      side: const BorderSide(
                          color: AppColors.border, width: 1.5),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.maybePop(context),
                      customBorder: RoundedRectangleBorder(
                          borderRadius: AppRadii.all(14)),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.chevron_left_rounded,
                            size: 26, color: AppColors.navy),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm your stay',
                          style: AppType.h3.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppText.primary,
                          ),
                        ),
                        Text(
                          '${widget.hotel.name} · ${widget.room.roomType}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('HOW ARE YOU COMING?', style: hotelOverline()),
                  const SizedBox(height: 10),
                  _WayOption(
                    icon: Icons.directions_car_rounded,
                    title: 'My own car',
                    subtitle: 'Driving there yourself',
                    selected: _mode == HotelArrivalMode.ownCar,
                    onTap: () =>
                        setState(() => _mode = HotelArrivalMode.ownCar),
                  ),
                  const SizedBox(height: 8),
                  _WayOption(
                    icon: Icons.place_rounded,
                    title: 'Book a UDrive ride',
                    subtitle: 'We find you a car after this booking',
                    selected: _mode == HotelArrivalMode.udriveRide,
                    onTap: () =>
                        setState(() => _mode = HotelArrivalMode.udriveRide),
                  ),
                  if (widget.hotel.transportAvailable) ...[
                    const SizedBox(height: 8),
                    _WayOption(
                      icon: Icons.airport_shuttle_rounded,
                      title: 'Hotel pickup transport',
                      subtitle: 'The hotel arranges your ride',
                      selected: _mode == HotelArrivalMode.hotelTransport,
                      onTap: () => setState(
                          () => _mode = HotelArrivalMode.hotelTransport),
                    ),
                  ],
                  const SizedBox(height: 20),

                  Text(
                    'WHEN WILL YOU REACH? · ${hotelDate(stay.checkIn).toUpperCase()}',
                    style: hotelOverline(),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.9,
                    children: [
                      for (final slot in _slots)
                        _TimeChip(
                          label: hotelTimeLabel(slot).replaceAll(':00', ''),
                          selected: _arrival == slot,
                          onTap: () => setState(() => _arrival = slot),
                        ),
                      _TimeChip(
                        label: _slots.contains(_arrival)
                            ? 'Other'
                            : arrivalLabel,
                        selected: !_slots.contains(_arrival),
                        onTap: _pickOtherTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The hotel keeps your room ready for this time.',
                    style: AppType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppText.secondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text('YOUR DETAILS · SENT TO THE HOTEL',
                      style: hotelOverline()),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.all(16),
                      border: Border.all(color: AppColors.border, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        _Field(
                          label: 'FULL NAME',
                          controller: _name,
                          keyboard: TextInputType.name,
                          onChanged: () => setState(() {}),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        _Field(
                          label: 'MOBILE / WHATSAPP',
                          controller: _phone,
                          keyboard: TextInputType.phone,
                          onChanged: () => setState(() {}),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('GUESTS · ROOMS',
                                        style: hotelOverline()
                                            .copyWith(fontSize: 11)),
                                    Text(
                                      '${stay.guests} '
                                      '${stay.guests == 1 ? 'guest' : 'guests'}'
                                      ' · ${stay.rooms} '
                                      '${stay.rooms == 1 ? 'room' : 'rooms'}',
                                      style: AppType.body2.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppText.primary,
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
                  if (_mode == HotelArrivalMode.ownCar) ...[
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.all(16),
                        border:
                            Border.all(color: AppColors.border, width: 1.5),
                      ),
                      child: _Field(
                        label: 'CAR NUMBER (FOR PARKING) · OPTIONAL',
                        controller: _car,
                        hint: 'e.g. MZD 1234',
                        keyboard: TextInputType.text,
                        caps: true,
                        onChanged: () {},
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.all(16),
                    ),
                    child: Column(
                      children: [
                        _SumRow(
                          label: '${hotelRange(stay.checkIn, stay.checkOut)} · '
                              '${stay.nights} '
                              '${stay.nights == 1 ? 'night' : 'nights'}',
                          value: Money.amount(total),
                        ),
                        const SizedBox(height: 6),
                        const _SumRow(
                          label: 'Pay at the hotel',
                          value: 'On arrival',
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    UdBanner(tone: UdTone.err, text: _error),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: HotelPrimaryButton(
                label: 'Confirm booking · arrive $arrivalLabel',
                icon: Icons.check_rounded,
                busy: _busy,
                onPressed: _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WayOption extends StatelessWidget {
  const _WayOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(16),
        side: BorderSide(
          color: selected ? AppColors.navy : AppColors.border,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brand : AppColors.surfaceAlt,
                  borderRadius: AppRadii.all(12),
                ),
                child: Icon(icon, size: 20, color: AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.small.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppText.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.navy : AppColors.borderStrong,
                    width: selected ? 7 : 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(12),
        side: BorderSide(
          color: selected ? AppColors.navy : AppColors.border,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: AppType.small.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? AppText.onInk : AppText.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.keyboard,
    required this.onChanged,
    this.hint,
    this.caps = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType keyboard;
  final VoidCallback onChanged;
  final String? hint;
  final bool caps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: hotelOverline().copyWith(fontSize: 11)),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            textCapitalization: caps
                ? TextCapitalization.characters
                : TextCapitalization.words,
            onChanged: (_) => onChanged(),
            style: AppType.body2.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppText.primary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppType.body2.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppText.caption,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.only(top: 4, bottom: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w600,
              color: AppText.secondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppType.small.copyWith(
            fontWeight: FontWeight.w800,
            color: AppText.primary,
          ),
        ),
      ],
    );
  }
}
