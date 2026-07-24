import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import 'package_detail_screen.dart';
import 'tourism_booking_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = destinations.where((e) => e.name.toLowerCase().contains(_query.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
      TextField(onChanged: (value) => setState(() => _query = value), decoration: InputDecoration(hintText: '${context.tr('search')} destinations', prefixIcon: const Icon(Icons.search_rounded))),
      const SizedBox(height: 18),
      ...filtered.map((item) => Padding(padding: const EdgeInsets.only(bottom: 14), child: PremiumCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(23)), child: Image.asset(item.image, height: 190, width: double.infinity, fit: BoxFit.cover)), Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(item.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), StatusPill(label: '${item.rating} ★', color: AppColors.accent)]), const SizedBox(height: 5), Text(item.location, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)), const SizedBox(height: 10), Text(item.description, style: const TextStyle(color: AppColors.muted, height: 1.4)), const SizedBox(height: 14), FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TourismBookingScreen(initialDestination: item.name))), icon: const Icon(Icons.local_taxi_rounded), label: Text('Ride to ${item.name}'))]))])))),
    ]);
  }
}

class PackagesScreen extends StatelessWidget {
  const PackagesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
    PremiumCard(color: const Color(0xFF0D4337), child: const Row(children: [Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 34), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Driver-created Kashmir tours', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)), SizedBox(height: 4), Text('Compare packages, drivers and customer-offer options.', style: TextStyle(color: Colors.white70, fontSize: 12))]))])),
    const SizedBox(height: 16),
    ...tourPackages.map((package) => Padding(padding: const EdgeInsets.only(bottom: 14), child: PremiumCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(package: package))), padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(23)), child: Image.asset(package.image, height: 180, width: double.infinity, fit: BoxFit.cover)), Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [StatusPill(label: '${package.days} days'), const SizedBox(width: 7), StatusPill(label: '${package.rating} ★', color: AppColors.accent), const Spacer(), Text('PKR ${package.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 17))]), const SizedBox(height: 11), Text(package.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)), const SizedBox(height: 5), Text(package.route, style: const TextStyle(color: AppColors.muted, fontSize: 12)), const SizedBox(height: 12), Row(children: [const Icon(Icons.person_rounded, size: 18, color: AppColors.muted), Text(' ${package.driver}', style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text('${package.maxGuests} guests · ${package.vehicle}', style: const TextStyle(color: AppColors.muted, fontSize: 11))])]))])))),
  ]);
}

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(
          children: [
            TabBar(tabs: [Tab(text: context.tr('upcoming')), Tab(text: context.tr('completed')), Tab(text: context.tr('cancelled'))]),
            const Expanded(
              child: TabBarView(
                children: [
                  _UpcomingTrips(),
                  _HistoricalTripList(filter: 'Completed'),
                  _EmptyMessage(icon: Icons.event_busy_rounded, title: 'No cancelled trips'),
                ],
              ),
            ),
          ],
        ),
      );
}

class _UpcomingTrips extends StatelessWidget {
  const _UpcomingTrips();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final advance = controller.advanceBookings;
    final scheduled = trips.where((trip) => trip.status == 'Upcoming').toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (advance.isNotEmpty) ...[
          SectionHeader(title: context.tr('advanceBooking')),
          const SizedBox(height: 9),
          ...advance.map((booking) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PremiumCard(
                  color: const Color(0xFFF0FAF6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Expanded(child: Text('${booking.pickup} → ${booking.destination}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))), StatusPill(label: booking.status)]),
                      const SizedBox(height: 8),
                      Text('${MaterialLocalizations.of(context).formatFullDate(booking.departureDate)} · ${booking.departureTime.format(context)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      const Divider(height: 22),
                      Row(children: [Icon(booking.bookingType == BookingType.perSeat ? Icons.event_seat_rounded : Icons.directions_car_filled_rounded, color: AppColors.primaryDark), const SizedBox(width: 8), Expanded(child: Text('${booking.vehicle} · ${booking.adults + booking.children} travellers', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))), Text('PKR ${booking.estimatedTotal}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
        ],
        if (scheduled.isNotEmpty) ...[
          SectionHeader(title: context.tr('upcoming')),
          const SizedBox(height: 9),
          ...scheduled.map((trip) => Padding(padding: const EdgeInsets.only(bottom: 13), child: _TripCard(trip: trip))),
        ],
      ],
    );
  }
}

class _HistoricalTripList extends StatelessWidget {
  const _HistoricalTripList({required this.filter});
  final String filter;

  @override
  Widget build(BuildContext context) {
    final list = trips.where((trip) => trip.status == filter).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: list.map((trip) => Padding(padding: const EdgeInsets.only(bottom: 13), child: _TripCard(trip: trip))).toList(),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});
  final TripRecord trip;

  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: () => _tripDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text(trip.route, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), StatusPill(label: trip.status, color: trip.status == 'Completed' ? AppColors.success : AppColors.info)]),
            const SizedBox(height: 8),
            Text(trip.date, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const Divider(height: 24),
            Row(children: [const CircleAvatar(radius: 19, child: Icon(Icons.person_rounded, size: 19)), const SizedBox(width: 9), Expanded(child: Text('${trip.driver}\n${trip.vehicle}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))), Text('PKR ${trip.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
          ],
        ),
      );

  void _tripDetail(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MapPreview(height: 220),
                const SizedBox(height: 15),
                ListTile(contentPadding: EdgeInsets.zero, title: Text(trip.route, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${trip.date}\n${trip.driver} · ${trip.vehicle}'), trailing: Text('PKR ${trip.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))),
                FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dummy receipt opened.'))), icon: const Icon(Icons.receipt_long_rounded), label: const Text('View receipt')),
              ],
            ),
          ),
        ),
      );
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final balance = AppControllerScope.of(context).walletBalance;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF063F32), AppColors.primary])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.account_balance_wallet_rounded, color: Colors.white), Spacer(), Text('uDrive Wallet', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))]), const SizedBox(height: 24), const Text('Available balance', style: TextStyle(color: Colors.white70)), const SizedBox(height: 4), Text('PKR $balance', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)), const SizedBox(height: 22), Row(children: [Expanded(child: _WalletAction(icon: Icons.add_rounded, label: context.tr('addMoney'))), const SizedBox(width: 10), Expanded(child: _WalletAction(icon: Icons.send_rounded, label: context.tr('sendMoney')))])])),
      const SizedBox(height: 22),
      SectionHeader(title: context.tr('transactions')),
      const SizedBox(height: 10),
      ...walletTransactions.map((tx) => Padding(padding: const EdgeInsets.only(bottom: 10), child: PremiumCard(child: Row(children: [Container(width: 43, height: 43, decoration: BoxDecoration(color: (tx.credit ? AppColors.success : AppColors.secondary).withValues(alpha: .11), borderRadius: BorderRadius.circular(13)), child: Icon(tx.credit ? Icons.south_west_rounded : Icons.north_east_rounded, color: tx.credit ? AppColors.success : AppColors.secondary)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tx.title, style: const TextStyle(fontWeight: FontWeight.w900)), Text(tx.date, style: const TextStyle(color: AppColors.muted, fontSize: 11))])), Text('${tx.credit ? '+' : '-'} PKR ${tx.amount}', style: TextStyle(fontWeight: FontWeight.w900, color: tx.credit ? AppColors.success : AppColors.navy))])))),
    ]);
  }
}

class _WalletAction extends StatelessWidget {
  const _WalletAction({required this.icon, required this.label});
  final IconData icon; final String label;
  @override
  Widget build(BuildContext context) => InkWell(onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label demo opened'))), borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(15)), child: Column(children: [Icon(icon, color: Colors.white), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))])));
}

class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    for (final item in const [('Home', 'Bahria Town, Rawalpindi', Icons.home_rounded), ('Office', 'Blue Area, Islamabad', Icons.work_rounded), ('Hotel', 'Pearl Continental, Muzaffarabad', Icons.hotel_rounded)]) Padding(padding: const EdgeInsets.only(bottom: 12), child: PremiumCard(child: ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: AppColors.primary.withValues(alpha: .1), child: Icon(item.$3, color: AppColors.primaryDark)), title: Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(item.$2), trailing: const Icon(Icons.edit_outlined)))),
    OutlinedButton.icon(onPressed: () => _simpleInput(context, 'Add saved place'), icon: const Icon(Icons.add_location_alt_rounded), label: const Text('Add a new place')),
  ]);
}

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(28)), child: Column(children: [const Icon(Icons.sos_rounded, color: Colors.white, size: 52), const SizedBox(height: 10), Text(context.tr('emergency'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)), const SizedBox(height: 6), const Text('Immediately share your location with emergency contacts and uDrive operations.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.4)), const SizedBox(height: 16), FilledButton(onPressed: () => _sos(context), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.danger), child: const Text('Activate SOS'))])),
    const SizedBox(height: 18),
    _SafetyOption(icon: Icons.share_location_rounded, title: context.tr('shareTrip'), subtitle: 'Share route, driver and live status', onTap: () => _notice(context, 'Live trip link copied.')),
    _SafetyOption(icon: Icons.people_alt_rounded, title: context.tr('trustedContacts'), subtitle: 'Amir Qureshi · +92 300 555 0112', onTap: () => _simpleInput(context, 'Add trusted contact')),
    _SafetyOption(icon: Icons.report_problem_rounded, title: context.tr('reportIssue'), subtitle: 'Report unsafe driving or route issues', onTap: () => _simpleInput(context, 'Describe the safety issue')),
    _SafetyOption(icon: Icons.local_hospital_rounded, title: 'Nearby emergency services', subtitle: 'Police, rescue and hospitals', onTap: () => _notice(context, 'Emergency directory opened with dummy contacts.')),
  ]);
}

class _SafetyOption extends StatelessWidget {
  const _SafetyOption({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 11), child: PremiumCard(onTap: onTap, child: Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppColors.primaryDark)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12))])), const Icon(Icons.chevron_right_rounded)])));
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(padding: const EdgeInsets.all(18), children: [
      PremiumCard(color: const Color(0xFF0D4337), child: Column(children: [const CircleAvatar(radius: 38, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, size: 42, color: AppColors.primaryDark)), const SizedBox(height: 12), const Text('Shahzad Ahmad Qureshi', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 4), const Text('+92 300 123 4567 · shahzad@example.com', style: TextStyle(color: Colors.white70, fontSize: 11)), const SizedBox(height: 15), const Row(mainAxisAlignment: MainAxisAlignment.center, children: [StatusPill(label: '4.9 ★', color: AppColors.accent), SizedBox(width: 8), StatusPill(label: 'Verified', color: AppColors.success)])])),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: () => controller.switchMode(UserMode.driver), icon: const Icon(Icons.drive_eta_rounded), label: Text(context.tr('switchDriver'))),
      const SizedBox(height: 14),
      for (final item in [('wallet', Icons.account_balance_wallet_rounded, context.tr('wallet')), ('saved', Icons.bookmark_rounded, context.tr('savedPlaces')), ('safety', Icons.health_and_safety_rounded, context.tr('safety')), ('settings', Icons.settings_rounded, context.tr('settings')), ('support', Icons.support_agent_rounded, context.tr('support'))]) Padding(padding: const EdgeInsets.only(bottom: 9), child: PremiumCard(onTap: () => onNavigate(item.$1), child: Row(children: [Icon(item.$2, color: AppColors.primaryDark), const SizedBox(width: 13), Expanded(child: Text(item.$3, style: const TextStyle(fontWeight: FontWeight.w900))), const Icon(Icons.chevron_right_rounded)]))),
    ]);
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.icon, required this.title});
  final IconData icon; final String title;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 58, color: AppColors.muted), const SizedBox(height: 12), Text(title, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800))]));
}

void _simpleInput(BuildContext context, String title) => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 14), const TextField(maxLines: 3), const SizedBox(height: 14), FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Save demo'))])));
void _notice(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
void _sos(BuildContext context) => showDialog(context: context, builder: (_) => AlertDialog(icon: const Icon(Icons.sos_rounded, color: AppColors.danger, size: 52), title: const Text('SOS demo activated'), content: const Text('Your dummy location was shared with trusted contacts and the operations dashboard.'), actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('I am safe'))]));
