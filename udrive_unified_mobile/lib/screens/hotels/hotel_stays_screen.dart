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

/// My stays — the customer's own hotel bookings. Tap one for its ticket.
class HotelStaysScreen extends StatefulWidget {
  const HotelStaysScreen({super.key});

  @override
  State<HotelStaysScreen> createState() => _HotelStaysScreenState();
}

class _HotelStaysScreenState extends State<HotelStaysScreen> {
  List<HotelStay> _stays = const [];
  bool _busy = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stays = await HotelRepository(
        AppControllerScope.of(context).apiClient,
      ).myBookings();
      if (!mounted) return;
      setState(() => _stays = stays);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is ApiException
          ? error.message
          : 'Your stays could not be loaded. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = hotelDay(DateTime.now());
    final upcoming =
        _stays.where((s) => !s.checkOut.isBefore(today)).toList();
    final past = _stays.where((s) => s.checkOut.isBefore(today)).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: 'My stays',
        onBack: () => Navigator.maybePop(context),
      ),
      body: _busy
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.navy),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (_error != null) ...[
                    UdBanner(tone: UdTone.err, text: _error),
                    const SizedBox(height: 12),
                  ],
                  if (_stays.isEmpty && _error == null)
                    const UdEmptyState(
                      icon: Icons.hotel_rounded,
                      title: 'No stays yet',
                      text: 'Rooms you book appear here, with the hotel\'s '
                          'number and the way there.',
                    ),
                  if (upcoming.isNotEmpty) ...[
                    Text('UPCOMING', style: hotelOverline()),
                    const SizedBox(height: 10),
                    for (final stay in upcoming) _StayRow(stay: stay),
                  ],
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('PAST', style: hotelOverline()),
                    const SizedBox(height: 10),
                    for (final stay in past) _StayRow(stay: stay),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StayRow extends StatelessWidget {
  const _StayRow({required this.stay});

  final HotelStay stay;

  @override
  Widget build(BuildContext context) {
    final cancelled = stay.status.toLowerCase() == 'cancelled';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(18),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => HotelBookedScreen(stay: stay)),
          ),
          customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                HotelPhoto(
                  url: stay.imageUrl,
                  width: 72,
                  height: 72,
                  radius: 14,
                  iconSize: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stay.hotelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                      Text(
                        '${hotelRange(stay.checkIn, stay.checkOut)} · '
                        '${stay.roomType}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppText.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cancelled
                            ? 'Cancelled'
                            : '${Money.amount(stay.amount)} · arrive '
                                '${hotelTimeLabel(stay.arrivalTime)}',
                        style: AppType.small.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cancelled ? AppColors.danger : AppText.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.navy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
