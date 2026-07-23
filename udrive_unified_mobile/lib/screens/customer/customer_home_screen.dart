import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import 'ride_booking_screen.dart';
import 'package_detail_screen.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => Future<void>.delayed(const Duration(milliseconds: 700)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          children: [
            Row(
              children: [
                const CircleAvatar(radius: 24, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, color: AppColors.primaryDark)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('goodMorning'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy)),
                      const SizedBox(height: 3),
                      const Row(children: [Icon(Icons.location_on_rounded, size: 15, color: AppColors.primary), SizedBox(width: 4), Text('Islamabad, Pakistan', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600))]),
                    ],
                  ),
                ),
                Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)), child: const Icon(Icons.qr_code_scanner_rounded)),
              ],
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RideBookingScreen())),
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  const MapPreview(height: 238),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .08), blurRadius: 18)]),
                      child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primary), const SizedBox(width: 10), Expanded(child: Text(context.tr('whereTo'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted))), const Icon(Icons.tune_rounded, color: AppColors.navy)]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: services
                  .map((service) => _ServiceCard(
                        title: context.tr(service.titleKey),
                        icon: service.icon,
                        color: service.color,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RideBookingScreen(serviceId: service.id))),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            PremiumCard(
              color: const Color(0xFF0D4337),
              child: Row(
                children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white)),
                  const SizedBox(width: 13),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Driver arriving in 6 min', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)), SizedBox(height: 4), Text('Adeel · Toyota Corolla · AJK-4821', style: TextStyle(color: Colors.white70, fontSize: 12))])),
                  FilledButton.tonal(onPressed: () => _showTrip(context), style: FilledButton.styleFrom(minimumSize: const Size(74, 42), backgroundColor: Colors.white, foregroundColor: AppColors.primaryDark), child: Text(context.tr('viewTrip'))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PremiumCard(
              color: const Color(0xFFFFF9E9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning)),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Muzaffarabad → Keran', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('Light rain expected. Drive during daylight and use a suitable vehicle.', style: TextStyle(color: AppColors.muted, height: 1.35, fontSize: 12))])),
                  const StatusPill(label: 'Caution', color: AppColors.warning),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionHeader(title: context.tr('popularPlaces'), action: context.tr('viewAll'), onAction: () => onNavigate('explore')),
            const SizedBox(height: 10),
            SizedBox(
              height: 218,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: destinations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _DestinationCard(item: destinations[index]),
              ),
            ),
            const SizedBox(height: 24),
            SectionHeader(title: context.tr('recommendedPackages'), action: context.tr('viewAll'), onAction: () => onNavigate('packages')),
            const SizedBox(height: 10),
            ...tourPackages.take(2).map((package) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _PackagePreview(package: package))),
          ],
        ),
      );

  void _showTrip(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MapPreview(height: 230),
                const SizedBox(height: 18),
                const ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Icon(Icons.person_rounded)), title: Text('Adeel Khan', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('Toyota Corolla 2022 · AJK-4821'), trailing: StatusPill(label: '4.9 ★')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo call started with Adeel Khan.'))),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo driver chat opened.'))),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('Message'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.title, required this.icon, required this.color, required this.onTap});
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 56) / 3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: width,
        height: 112,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
          const Spacer(),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, height: 1.12, color: AppColors.navy)),
        ]),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.item});
  final DestinationItem item;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: PremiumCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Stack(
              children: [
                Positioned.fill(child: Image.asset(item.image, fit: BoxFit.cover)),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.navy.withValues(alpha: .88)])))),
                Positioned(left: 13, right: 13, bottom: 13, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Row(children: [const Icon(Icons.star_rounded, color: AppColors.accent, size: 16), Text(' ${item.rating}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)), const Spacer(), const Icon(Icons.schedule_rounded, color: Colors.white70, size: 14), Text(' ${item.travelTime}', style: const TextStyle(color: Colors.white70, fontSize: 11))])])),
              ],
            ),
          ),
        ),
      );
}

class _PackagePreview extends StatelessWidget {
  const _PackagePreview({required this.package});
  final TourPackage package;
  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(package: package))),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(17), child: Image.asset(package.image, width: 98, height: 98, fit: BoxFit.cover)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [StatusPill(label: '${package.days} days'), const SizedBox(height: 8), Text(package.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(package.route, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)), const SizedBox(height: 9), Text('PKR ${package.price}', style: const TextStyle(color: AppColors.primaryDark, fontSize: 16, fontWeight: FontWeight.w900))])),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      );
}
