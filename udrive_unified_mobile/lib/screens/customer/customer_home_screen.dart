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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() => AppControllerScope.of(context).refreshPhase9Marketplace();

  @override
  Widget build(BuildContext context) {
    final c = AppControllerScope.of(context);
    final active = c.liveBookings.where((b) => !_closed.contains(b.status)).toList()
      ..sort((a, b) => a.pickupAt.compareTo(b.pickupAt));
    final upcoming = active.where((b) => b.pickupAt.isAfter(DateTime.now())).length;
    final pendingOffers = c.liveRideRequests.fold<int>(0, (sum, item) => sum + item.offersCount);
    final packages = c.liveMarketplacePackages.take(3).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
        children: [
          _AccountHeader(name: c.currentUserName, phone: c.currentUserPhone),
          const SizedBox(height: 16),
          _BookingHero(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TourismBookingScreen()))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Metric(icon: Icons.route_rounded, label: _t('Active trips', 'فعال سفر'), value: '${active.length}', color: AppColors.primary)),
            const SizedBox(width: 10),
            Expanded(child: _Metric(icon: Icons.calendar_month_rounded, label: _t('Upcoming', 'آنے والے'), value: '$upcoming', color: AppColors.info)),
            const SizedBox(width: 10),
            Expanded(child: _Metric(icon: Icons.local_offer_rounded, label: _t('Offers', 'آفرز'), value: '$pendingOffers', color: AppColors.secondary)),
          ]),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(title: _t('Current booking', 'موجودہ بکنگ'), action: _t('View all', 'سب دیکھیں'), onAction: () => widget.onNavigate('trips')),
            const SizedBox(height: 10),
            _LiveBookingCard(booking: active.first, onTap: () => widget.onNavigate('trips')),
          ],
          const SizedBox(height: 20),
          SectionHeader(title: _t('Quick actions', 'فوری سہولیات')),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _Action(icon: Icons.local_taxi_rounded, title: _t('Book a ride', 'رائیڈ بک کریں'), subtitle: _t('Private or shared', 'پرائیویٹ یا شیئرڈ'), colors: const [Color(0xFF0E8F68), Color(0xFF16B982)], onTap: () => widget.onNavigate('bookRide')),
              _Action(icon: Icons.luggage_rounded, title: _t('Tour packages', 'ٹور پیکجز'), subtitle: _t('Explore Kashmir', 'کشمیر دیکھیں'), colors: const [Color(0xFF3568D4), Color(0xFF5A8AF0)], onTap: () => widget.onNavigate('packages')),
              _Action(icon: Icons.groups_rounded, title: _t('Join a tour', 'ٹور جوائن کریں'), subtitle: _t('Reserve your seat', 'اپنی سیٹ بک کریں'), colors: const [Color(0xFF7A42C8), Color(0xFFA164E8)], onTap: () => widget.onNavigate('joinTour')),
              _Action(icon: Icons.health_and_safety_rounded, title: _t('Safety centre', 'سیفٹی سینٹر'), subtitle: _t('Tracking & support', 'ٹریکنگ اور مدد'), colors: const [Color(0xFFE5702A), Color(0xFFF49A46)], onTap: () => widget.onNavigate('safety')),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(title: _t('Live tourism packages', 'لائیو ٹورزم پیکجز'), action: _t('View all', 'سب دیکھیں'), onAction: () => widget.onNavigate('packages')),
          const SizedBox(height: 10),
          if (c.marketplaceBusy && packages.isEmpty)
            const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
          else if (packages.isEmpty)
            _EmptyLiveData(message: _t('No Admin-approved package is currently available.', 'اس وقت کوئی ایڈمن منظور شدہ پیکج دستیاب نہیں۔'))
          else
            ...packages.map((p) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _PackagePreview(package: p, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LivePackagesScreen()))))),
          if (c.marketplaceError != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: c.marketplaceError!, onRetry: _refresh),
          ],
        ],
      ),
    );
  }

  String _t(String en, String ur) => AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  static const _closed = {'Completed', 'Cancelled', 'NoShow'};
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.name, required this.phone});
  final String name;
  final String phone;
  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(radius: 24, backgroundColor: AppColors.primary.withValues(alpha: .12), child: Text(_initials(name), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900))),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_greeting(context, name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), const SizedBox(height: 2), Text(phone.isEmpty ? '—' : phone, style: const TextStyle(color: AppColors.muted, fontSize: 12))])),
        const StatusPill(label: 'Live', color: AppColors.success),
      ]);


  static String _greeting(BuildContext context, String name) {
    final hour = DateTime.now().toUtc().add(const Duration(hours: 5)).hour;
    final isUrdu = AppControllerScope.of(context).locale.languageCode == 'ur';
    final greeting = isUrdu
        ? (hour < 12 ? 'صبح بخیر' : hour < 17 ? 'دوپہر بخیر' : 'شب بخیر')
        : (hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening');
    final safeName = name.trim().isEmpty ? (isUrdu ? 'صارف' : 'uDrive User') : name.trim();
    return '$greeting, $safeName';
  }

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2).toList();
    return parts.isEmpty ? 'U' : parts.map((e) => e[0].toUpperCase()).join();
  }
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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFF063F32), Color(0xFF129E6A)])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('whereTo'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 5),
            const Text('Create a ride request and receive offers from verified Drivers.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
            const SizedBox(height: 15),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: const Row(children: [Icon(Icons.search_rounded, color: AppColors.primaryDark), SizedBox(width: 9), Expanded(child: Text('Pickup and destination', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))), Icon(Icons.arrow_forward_rounded)])),
          ]),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon; final String label; final String value; final Color color;
  @override
  Widget build(BuildContext context) => PremiumCard(padding: const EdgeInsets.all(12), child: Column(children: [Icon(icon, color: color, size: 21), const SizedBox(height: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 10))]));
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.subtitle, required this.colors, required this.onTap});
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
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .22), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Colors.white)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 9.5, fontWeight: FontWeight.w600)),
              ])),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
            ],
          ),
        ),
      );
}

class _LiveBookingCard extends StatelessWidget {
  const _LiveBookingCard({required this.booking, required this.onTap});
  final LiveBooking booking; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PremiumCard(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(booking.bookingReference, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))), StatusPill(label: booking.status)]),
        const SizedBox(height: 10),
        Text('${booking.pickupLabel} → ${booking.destinationLabel}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 7),
        Text(DateFormat('dd MMM yyyy · hh:mm a').format(booking.pickupAt), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        if (booking.driverName != null) ...[const SizedBox(height: 6), Text('${booking.driverName} · ${booking.vehicle ?? ''} ${booking.registrationNumber ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12))],
        const Divider(height: 22),
        Row(children: [Text('${booking.bookingType} · ${booking.seatsBooked} seat(s)', style: const TextStyle(fontSize: 11, color: AppColors.muted)), const Spacer(), Text('PKR ${NumberFormat('#,##0').format(booking.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.w900))]),
      ]));
}

class _PackagePreview extends StatelessWidget {
  const _PackagePreview({required this.package, required this.onTap});
  final LiveTourPackage package; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PremiumCard(onTap: onTap, child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .11), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.landscape_rounded, color: AppColors.primaryDark)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(package.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${package.startingCity} → ${package.destination} · ${package.bookableSeats} seats', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
        const SizedBox(width: 8),
        Text('PKR ${NumberFormat('#,##0').format(package.pricePerSeat)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 12)),
      ]));
}

class _EmptyLiveData extends StatelessWidget {
  const _EmptyLiveData({required this.message}); final String message;
  @override Widget build(BuildContext context) => PremiumCard(child: Row(children: [const Icon(Icons.inbox_outlined, color: AppColors.muted), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 12)))]));
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry}); final String message; final VoidCallback onRetry;
  @override Widget build(BuildContext context) => PremiumCard(color: const Color(0xFFFFF3F2), child: Row(children: [const Icon(Icons.error_outline_rounded, color: AppColors.danger), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(fontSize: 11))), TextButton(onPressed: onRetry, child: const Text('Retry'))]));
}
