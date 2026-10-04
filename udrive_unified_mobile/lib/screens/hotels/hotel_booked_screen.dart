import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/hotel_models.dart';
import 'hotel_bits.dart';
import 'hotel_directions_screen.dart';
import 'hotel_stays_screen.dart';

/// The booking, as a ticket the guest can show at the desk.
///
/// Opened straight after booking ([justBooked]) and again from My stays.
class HotelBookedScreen extends StatelessWidget {
  const HotelBookedScreen({
    required this.stay,
    this.justBooked = false,
    super.key,
  });

  final HotelStay stay;
  final bool justBooked;

  String get _coming => switch (stay.arrivalMode) {
        HotelArrivalMode.ownCar => 'own car',
        HotelArrivalMode.udriveRide => 'UDrive ride',
        HotelArrivalMode.hotelTransport => 'hotel transport',
      };

  @override
  Widget build(BuildContext context) {
    final cancelled = stay.status.toLowerCase() == 'cancelled';

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  HotelBackButton(
                    dark: true,
                    onTap: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 64),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cancelled ? AppColors.navyLine : AppColors.brand,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      cancelled ? Icons.close_rounded : Icons.check_rounded,
                      size: 32,
                      color: cancelled ? AppText.onInk : AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    cancelled
                        ? 'Booking cancelled'
                        : justBooked
                            ? 'Room booked'
                            : 'Your stay',
                    style: AppType.h2.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppText.onInk,
                    ),
                  ),
                  if (stay.reference.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Booking ${stay.reference}',
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onInkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -46),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    children: [
                      Row(
                        children: [
                          HotelPhoto(
                            url: stay.imageUrl,
                            width: 56,
                            height: 56,
                            radius: 14,
                            iconSize: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stay.hotelName,
                                  style: AppType.listTitle.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                                Text(
                                  [stay.address, stay.city]
                                      .where((s) => s.trim().isNotEmpty)
                                      .join(', '),
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
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.5,
                        children: [
                          _Cell(
                            label: 'ARRIVE',
                            value: '${hotelDate(stay.checkIn)} · '
                                '${hotelTimeLabel(stay.arrivalTime)}',
                          ),
                          _Cell(
                            label: 'CHECK-OUT',
                            value: hotelDate(stay.checkOut),
                          ),
                          _Cell(label: 'ROOM', value: stay.roomType),
                          _Cell(
                            label: 'GUESTS',
                            value: '${stay.guests} · $_coming',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          borderRadius: AppRadii.all(14),
                          border: Border.all(
                              color: AppColors.borderStrong, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pay at the hotel',
                                    style: AppType.caption.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppText.secondary,
                                    ),
                                  ),
                                  Text(
                                    Money.amount(stay.amount),
                                    style: AppType.h3.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppText.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${stay.nights} '
                              '${stay.nights == 1 ? 'night' : 'nights'}',
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppText.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _NoticeStrip(sent: stay.ownerNotified),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: HotelOutlineButton(
                              label: 'Call hotel',
                              icon: Icons.call_rounded,
                              onPressed: () =>
                                  callHotel(context, stay.contactPhone),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: HotelOutlineButton(
                              label: 'My stays',
                              onPressed: justBooked
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const HotelStaysScreen(),
                                        ),
                                      )
                                  : () => Navigator.maybePop(context),
                            ),
                          ),
                        ],
                      ),
                      if (stay.hasLocation && !cancelled) ...[
                        const SizedBox(height: 10),
                        HotelPrimaryButton(
                          label: 'Go to this hotel',
                          icon: Icons.navigation_rounded,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  HotelDirectionsScreen(stay: stay),
                            ),
                          ),
                        ),
                      ],
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

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: hotelOverline().copyWith(fontSize: 10.5)),
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
    );
  }
}

/// Whether the hotel got the booking on WhatsApp.
class _NoticeStrip extends StatelessWidget {
  const _NoticeStrip({required this.sent});

  final bool sent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: sent ? AppColors.brandWash : AppColors.surfaceAlt,
        borderRadius: AppRadii.all(14),
      ),
      child: Row(
        children: [
          Icon(
            sent ? Icons.mark_chat_read_rounded : Icons.info_outline_rounded,
            size: 20,
            color: sent ? AppColors.brandInk : AppColors.navy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sent
                  ? 'The hotel has your name, number and arrival time on '
                      'WhatsApp.'
                  : 'Your room is booked. The hotel could not be reached on '
                      'WhatsApp just now — please call them to confirm.',
              style: AppType.caption.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: sent ? AppColors.brandInk : AppText.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
