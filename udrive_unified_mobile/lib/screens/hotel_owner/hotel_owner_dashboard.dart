import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/hotel_models.dart';
import 'hotel_owner_manage_screen.dart';

/// H-01 — the hotels this owner has listed, and where each one stands.
///
/// The first tab of [HotelOwnerShell], which draws the bar — no `Scaffold`
/// here.
class HotelOwnerDashboard extends StatefulWidget {
  const HotelOwnerDashboard({super.key});

  @override
  State<HotelOwnerDashboard> createState() => _HotelOwnerDashboardState();
}

class _HotelOwnerDashboardState extends State<HotelOwnerDashboard> {
  final List<HotelSummary> _items = <HotelSummary>[];
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
    if (mounted) {
      setState(() => _busy = true);
    }

    try {
      final hotels = await HotelRepository(
        AppControllerScope.of(context).apiClient,
      ).myHotels();

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(hotels);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load hotels: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The two numbers the artboard leads with. Both come off the list that is
    // already loaded, so they cost nothing — the screen simply never said
    // them.
    final rooms = _items.fold<int>(0, (sum, h) => sum + h.availableRooms);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: <Widget>[
          Text(
            'My hotels',
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 6),
          Text(
            'Only admin-approved hotels appear to customers in Hotels & '
            'Stays.',
            style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 20),

          UdCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: UdStat(
                    value: '${_items.length}',
                    label: 'Listed hotels',
                  ),
                ),
                Expanded(
                  child: UdStat(
                    value: '$rooms',
                    label: 'Rooms available',
                    align: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          UdSectionHeader(
            title: 'Your listings',
            caption: _items.isEmpty ? null : '${_items.length}',
          ),
          const SizedBox(height: 12),

          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.navy),
              ),
            )
          else if (_items.isEmpty)
            const UdEmptyState(
              icon: Icons.apartment_outlined,
              title: 'No hotel added yet',
              text: 'Use Add hotel to submit your property for admin '
                  'approval.',
            )
          else
            ..._items.map(
              (hotel) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HotelCard(
                  hotel: hotel,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HotelOwnerManageScreen(hotel: hotel),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One listing: what it is, where it is, and what the reviewers did with it.
class _HotelCard extends StatelessWidget {
  const _HotelCard({required this.hotel, required this.onTap});

  final HotelSummary hotel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = hotel.approvalStatus ?? 'Pending';
    final approved = status == 'Approved';
    final rejected = status == 'Rejected';
    final reason = (hotel.rejectionReason ?? '').trim();

    return UdCard(
      selected: rejected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UdIconTile(
                icon: Icons.hotel_rounded,
                tone: approved ? UdIconTone.soft : UdIconTone.neutral,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hotel.name,
                      style: AppType.h3.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${hotel.city} · ${hotel.availableRooms} rooms · '
                      'PKR ${NumberFormat('#,###').format(hotel.startingRate.round())}'
                      '/night',
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(
                label: rejected
                    ? 'Rejected'
                    : approved
                        ? 'Approved'
                        : 'Pending review',
                tone: rejected
                    ? UdTone.err
                    : approved
                        ? UdTone.ok
                        : UdTone.warn,
              ),
            ],
          ),

          // Why it came back, and what to do about it.
          //
          // The rejection reason is on `HotelSummary` and this screen never
          // showed it — the status icon went red and that was all the owner
          // was told.
          if (rejected) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.assignment_late_outlined,
              text: reason.isEmpty
                  ? '${hotel.name} was rejected. Open Manage hotel to edit '
                      'and resubmit.'
                  : 'Reason: $reason Edit and resubmit from Manage hotel.',
            ),
          ],
        ],
      ),
    );
  }
}
