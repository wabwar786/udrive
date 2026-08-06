import 'package:flutter/material.dart';

import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../models/hotel_models.dart';
import 'hotel_owner_manage_screen.dart';

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
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: <Widget>[
            const Text(
              'My Hotels',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Only admin-approved hotels appear to customers.',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                    'No hotel added yet. Use Add hotel to submit one for approval.',
                  ),
                ),
              )
            else
              ..._items.map(_hotelCard),
          ],
        ),
      ),
    );
  }

  Widget _hotelCard(HotelSummary hotel) {
    final status = hotel.approvalStatus ?? 'Pending';
    final isApproved = status == 'Approved';
    final isRejected = status == 'Rejected';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HotelOwnerManageScreen(hotel: hotel),
            ),
          );
        },
        leading: const CircleAvatar(
          child: Icon(Icons.hotel_rounded),
        ),
        title: Text(
          hotel.name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${hotel.city}\n$status',
          style: const TextStyle(fontSize: 10),
        ),
        isThreeLine: true,
        trailing: Icon(
          isApproved
              ? Icons.verified_rounded
              : isRejected
                  ? Icons.cancel_rounded
                  : Icons.hourglass_top_rounded,
          color: isApproved
              ? Colors.green
              : isRejected
                  ? Colors.red
                  : Colors.orange,
        ),
      ),
    );
  }
}
