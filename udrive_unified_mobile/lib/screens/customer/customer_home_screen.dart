import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import 'live_packages_screen.dart';
import 'tourism_booking_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final TextEditingController _vehicleSearch = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _vehicleSearch.addListener(() {
      final value = _vehicleSearch.text.trim().toLowerCase();
      if (value != _query) setState(() => _query = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _vehicleSearch.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      AppControllerScope.of(context).refreshPhase9Marketplace();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final active = controller.liveBookings
        .where((booking) => !_closed.contains(booking.status))
        .toList()
      ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
    final upcoming = active
        .where((booking) => booking.pickupAt.isAfter(DateTime.now()))
        .length;
    final pendingOffers = controller.liveRideRequests.fold<int>(
      0,
      (sum, request) => sum + request.offersCount,
    );
    final vehicles = _filteredVehicles(controller.liveMarketplacePackages);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          _BookingHero(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TourismBookingScreen(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _VehiclesSectionHeader(
            title: _t('Vehicles going your way', 'آپ کے راستے کی گاڑیاں'),
            subtitle: _t(
              'Search your destination and reserve an available seat.',
              'اپنی منزل تلاش کریں اور دستیاب سیٹ بک کریں۔',
            ),
            onViewAll: () => widget.onNavigate('packages'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vehicleSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: _t(
                'Search destination, e.g. Neelum Valley',
                'منزل تلاش کریں، مثلاً نیلم ویلی',
              ),
              prefixIcon: const Icon(Icons.location_searching_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: _t('Clear search', 'تلاش صاف کریں'),
                      onPressed: _vehicleSearch.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (controller.marketplaceBusy && vehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (vehicles.isEmpty)
            _EmptyLiveData(
              message: _query.isEmpty
                  ? _t(
                      'No scheduled vehicle is currently available.',
                      'اس وقت کوئی شیڈول گاڑی دستیاب نہیں۔',
                    )
                  : _t(
                      'No vehicle is going to this destination right now.',
                      'اس وقت اس منزل کی طرف کوئی گاڑی نہیں جا رہی۔',
                    ),
            )
          else
            ...vehicles.map(
              (package) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ScheduledVehicleCard(
                  package: package,
                  onTap: () => _openVehicle(package),
                ),
              ),
            ),
          if (controller.marketplaceError != null &&
              vehicles.isEmpty &&
              !controller.marketplaceBusy) ...[
            const SizedBox(height: 8),
            _ErrorBanner(
              message: _t(
                'Vehicles could not be refreshed. Pull down or tap retry.',
                'گاڑیاں ریفریش نہیں ہو سکیں۔ نیچے کھینچیں یا دوبارہ کوشش کریں۔',
              ),
              onRetry: _refresh,
            ),
          ],
          if (active.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(
              title: _t('Current booking', 'موجودہ بکنگ'),
              action: _t('View all', 'سب دیکھیں'),
              onAction: () => widget.onNavigate('trips'),
            ),
            const SizedBox(height: 10),
            _LiveBookingCard(
              booking: active.first,
              onTap: () => widget.onNavigate('trips'),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.route_rounded,
                  label: _t('Active trips', 'فعال سفر'),
                  value: '${active.length}',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  icon: Icons.calendar_month_rounded,
                  label: _t('Upcoming', 'آنے والے'),
                  value: '$upcoming',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  icon: Icons.local_offer_rounded,
                  label: _t('Offers', 'آفرز'),
                  value: '$pendingOffers',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(title: _t('Quick actions', 'فوری سہولیات')),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.72,
            children: [
              _Action(
                icon: Icons.local_taxi_rounded,
                title: _t('Book a ride', 'رائیڈ بک کریں'),
                subtitle: _t('Private or shared', 'پرائیویٹ یا شیئرڈ'),
                colors: const [Color(0xFF0E8F68), Color(0xFF16B982)],
                onTap: () => widget.onNavigate('bookRide'),
              ),
              _Action(
                icon: Icons.directions_bus_filled_rounded,
                title: _t('Scheduled rides', 'شیڈول رائیڈز'),
                subtitle: _t('Book available seats', 'دستیاب سیٹ بک کریں'),
                colors: const [Color(0xFF3568D4), Color(0xFF5A8AF0)],
                onTap: () => widget.onNavigate('packages'),
              ),
              _Action(
                icon: Icons.groups_rounded,
                title: _t('Join a tour', 'ٹور جوائن کریں'),
                subtitle: _t('Find matching tours', 'میچنگ ٹور تلاش کریں'),
                colors: const [Color(0xFF7A42C8), Color(0xFFA164E8)],
                onTap: () => widget.onNavigate('joinTour'),
              ),
              _Action(
                icon: Icons.health_and_safety_rounded,
                title: _t('Safety centre', 'سیفٹی سینٹر'),
                subtitle: _t('Tracking & support', 'ٹریکنگ اور مدد'),
                colors: const [Color(0xFFE5702A), Color(0xFFF49A46)],
                onTap: () => widget.onNavigate('safety'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<LiveTourPackage> _filteredVehicles(List<LiveTourPackage> source) {
    final sorted = [...source]
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    final filtered = _query.isEmpty
        ? sorted
        : sorted.where(
            (package) => package.destination.toLowerCase().contains(_query),
          );
    return filtered.take(10).toList();
  }

  Future<void> _openVehicle(LiveTourPackage package) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePackageDetailScreen(package: package),
      ),
    );
    if (mounted) await _refresh();
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  static const _closed = {'Completed', 'Cancelled', 'NoShow'};
}

class _BookingHero extends StatelessWidget {
  const _BookingHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF063F32), Color(0xFF129E6A)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF129E6A).withValues(alpha: .24),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('whereTo'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Book a private vehicle or reserve seats on a scheduled ride.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: AppColors.primaryDark),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Pickup and destination',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _VehiclesSectionHeader extends StatelessWidget {
  const _VehiclesSectionHeader({
    required this.title,
    required this.subtitle,
    required this.onViewAll,
  });

  final String title;
  final String subtitle;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3568D4), Color(0xFF5A8AF0)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_bus_filled_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onViewAll, child: const Text('View all')),
        ],
      );
}

class _ScheduledVehicleCard extends StatelessWidget {
  const _ScheduledVehicleCard({required this.package, required this.onTap});

  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final seats = package.bookableSeats;
    final money = NumberFormat('#,###').format(package.pricePerSeat);
    final image = package.coverImageUrl?.trim();

    return PremiumCard(
      onTap: seats > 0 ? onTap : null,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: image != null && image.isNotEmpty
                        ? Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _vehicleFallback(),
                          )
                        : _vehicleFallback(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.vehicle.isEmpty ? package.title : package.vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        package.registrationNumber.isEmpty
                            ? package.title
                            : '${package.registrationNumber} · ${package.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: AppColors.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              DateFormat('dd MMM · hh:mm a').format(package.departureAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Fare per seat',
                      style: TextStyle(color: AppColors.muted, fontSize: 9.5),
                    ),
                    Text(
                      'PKR $money',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: seats > 0
                            ? const Color(0xFFE2F7EF)
                            : const Color(0xFFFFE8E8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        seats > 0 ? '$seats seats free' : 'Full',
                        style: TextStyle(
                          color: seats > 0 ? AppColors.primaryDark : AppColors.danger,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F8F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trip_origin_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      package.startingCity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 15, color: AppColors.muted),
                  ),
                  Expanded(
                    child: Text(
                      package.destination,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.location_on_rounded, size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _vehicleFallback() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3568D4), Color(0xFF5A8AF0)],
          ),
        ),
        child: Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 28),
      );
}

class _RoutePlace extends StatelessWidget {
  const _RoutePlace({
    required this.icon,
    required this.label,
    this.alignEnd = false,
  });

  final IconData icon;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!alignEnd) ...[
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: alignEnd ? AppColors.primaryDark : AppColors.navy,
              ),
            ),
          ),
          if (alignEnd) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 17, color: AppColors.primary),
          ],
        ],
      );
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.muted),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _VehicleFact extends StatelessWidget {
  const _VehicleFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => PremiumCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: .22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 13),
            ],
          ),
        ),
      );
}

class _LiveBookingCard extends StatelessWidget {
  const _LiveBookingCard({required this.booking, required this.onTap});

  final LiveBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.bookingReference,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusPill(label: booking.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${booking.pickupLabel} → ${booking.destinationLabel}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              '${DateFormat('dd MMM · hh:mm a').format(booking.pickupAt)} · ${booking.seatsBooked} seat(s)',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if ((booking.driverName ?? '').isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                '${booking.driverName} · ${booking.vehicle ?? 'Vehicle pending'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      );
}

class _EmptyLiveData extends StatelessWidget {
  const _EmptyLiveData({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PremiumCard(
        child: Row(
          children: [
            const Icon(Icons.directions_bus_outlined, color: AppColors.muted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => PremiumCard(
        color: const Color(0xFFFFF4F4),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
