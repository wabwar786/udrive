import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import 'family_tour_planner_screen.dart';
import 'join_tour_screen.dart';
import 'package_detail_screen.dart';
import 'tourism_booking_screen.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          cacheExtent: 900,
          children: [
            const _CustomerHeader(),
            const SizedBox(height: 18),
            _QuickSearch(onTap: () => _openBooking(context)),
            const SizedBox(height: 18),
            _PrimaryActionGrid(onNavigate: onNavigate),
            const SizedBox(height: 20),
            const _TourismSafetyStrip(),
            const SizedBox(height: 22),
            SectionHeader(title: context.tr('quickServices')),
            const SizedBox(height: 10),
            SizedBox(
              height: 94,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) => _QuickService(item: services[index]),
              ),
            ),
            const SizedBox(height: 22),
            SectionHeader(title: context.tr('departingSoon'), action: context.tr('viewAll'), onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinTourScreen()))),
            const SizedBox(height: 10),
            _DepartingSoonCard(tour: sharedTours.first),
            const SizedBox(height: 22),
            const _RoadAdvisoryCard(),
            const SizedBox(height: 22),
            SectionHeader(title: context.tr('popularPlaces'), action: context.tr('viewAll'), onAction: () => onNavigate('explore')),
            const SizedBox(height: 10),
            SizedBox(
              height: 218,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: destinations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => RepaintBoundary(child: _DestinationCard(item: destinations[index])),
              ),
            ),
            const SizedBox(height: 22),
            SectionHeader(title: context.tr('recommendedPackages'), action: context.tr('viewAll'), onAction: () => onNavigate('packages')),
            const SizedBox(height: 10),
            ...tourPackages.take(2).map((package) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _PackagePreview(package: package))),
          ],
        ),
      );

  void _openBooking(BuildContext context, {BookingType? type, String? destination}) => Navigator.push(context, MaterialPageRoute(builder: (_) => TourismBookingScreen(initialType: type, initialDestination: destination)));
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader();
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.border)), child: const Icon(Icons.person_rounded, color: AppColors.primaryDark)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('goodMorning'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy)), const SizedBox(height: 3), Row(children: [const Icon(Icons.location_on_rounded, size: 15, color: AppColors.primary), const SizedBox(width: 3), Flexible(child: Text(context.tr('currentLocationDemo'), overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)))])])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: const Color(0xFFEAF8F2), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.cloud_done_rounded, size: 15, color: AppColors.primaryDark), const SizedBox(width: 5), Text(context.tr('offlineReady'), style: const TextStyle(color: AppColors.primaryDark, fontSize: 10, fontWeight: FontWeight.w900))])),
        ],
      );
}

class _QuickSearch extends StatelessWidget {
  const _QuickSearch({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF063F32), Color(0xFF129E6A)]), borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('whereTo'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 21)),
            const SizedBox(height: 5),
            Text(context.tr('homeSearchSubtitle'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)), child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primaryDark), const SizedBox(width: 9), Expanded(child: Text(context.tr('searchDestination'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))), const Icon(Icons.arrow_forward_rounded, color: AppColors.navy)])),
          ]),
        ),
      );
}

class _PrimaryActionGrid extends StatelessWidget {
  const _PrimaryActionGrid({required this.onNavigate});
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final actions = <_HomeAction>[
      _HomeAction(context.tr('bookVehicle'), context.tr('bookVehicleHint'), Icons.directions_car_filled_rounded, AppColors.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TourismBookingScreen()))),
      _HomeAction(context.tr('joinTour'), context.tr('joinTourHint'), Icons.groups_rounded, const Color(0xFF7C3AED), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinTourScreen()))),
      _HomeAction(context.tr('familyTour'), context.tr('familyTourHint'), Icons.family_restroom_rounded, const Color(0xFFEA580C), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FamilyTourPlannerScreen()))),
      _HomeAction(context.tr('explore'), context.tr('exploreHint'), Icons.explore_rounded, AppColors.secondary, () => onNavigate('explore')),
      _HomeAction(context.tr('trips'), context.tr('tripsHint'), Icons.route_rounded, const Color(0xFF0284C7), () => onNavigate('trips')),
      _HomeAction(context.tr('emergencySafety'), context.tr('safetyHint'), Icons.health_and_safety_rounded, AppColors.danger, () => onNavigate('safety')),
    ];
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.42),
      itemBuilder: (context, index) => _HomeActionCard(action: actions[index]),
    );
  }
}

class _HomeAction {
  const _HomeAction(this.title, this.subtitle, this.icon, this.color, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({required this.action});
  final _HomeAction action;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: action.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(action.icon, color: action.color, size: 21)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(action.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, height: 1.1)), const SizedBox(height: 4), Text(action.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9.5, height: 1.2))]))]),
        ),
      );
}

class _TourismSafetyStrip extends StatelessWidget {
  const _TourismSafetyStrip();
  @override
  Widget build(BuildContext context) => PremiumCard(
        color: const Color(0xFFFFF8E8),
        child: Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: .18), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.shield_rounded, color: Color(0xFF8A5B00))), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('safeTourismPromise'), style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(context.tr('safeTourismPromiseText'), style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.3))])), const Icon(Icons.chevron_right_rounded)]),
      );
}

class _QuickService extends StatelessWidget {
  const _QuickService({required this.item});
  final ServiceItem item;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          final type = item.id == 'perSeat' ? BookingType.perSeat : item.id == 'wholeVehicle' ? BookingType.wholeVehicle : null;
          Navigator.push(context, MaterialPageRoute(builder: (_) => TourismBookingScreen(initialType: type)));
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(width: 92, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: item.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(item.icon, color: item.color, size: 19)), const Spacer(), Text(context.tr(item.titleKey), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, height: 1.1))])),
      );
}

class _DepartingSoonCard extends StatelessWidget {
  const _DepartingSoonCard({required this.tour});
  final SharedTour tour;
  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinTourScreen())),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [StatusPill(label: '${tour.matchPercent}% ${context.tr('match')}'), const Spacer(), Text('${tour.availableSeats} ${context.tr('seatsLeft')}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
          const SizedBox(height: 11),
          Text(tour.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 5),
          Text('${tour.pickup} → ${tour.destination}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [const Icon(Icons.schedule_rounded, size: 17, color: AppColors.primaryDark), const SizedBox(width: 5), Text('${tour.departureDate} · ${tour.departureTime}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), const Spacer(), Text('PKR ${tour.pricePerSeat}/${context.tr('seat')}', style: const TextStyle(fontWeight: FontWeight.w900))]),
        ]),
      );
}

class _RoadAdvisoryCard extends StatelessWidget {
  const _RoadAdvisoryCard();
  @override
  Widget build(BuildContext context) => PremiumCard(
        color: const Color(0xFFFFF9E9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('muzaffarabadKeran'), style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(context.tr('roadAlertDemo'), style: const TextStyle(color: AppColors.muted, height: 1.35, fontSize: 12))])), StatusPill(label: context.tr('caution'), color: AppColors.warning)]),
      );
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.item});
  final DestinationItem item;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: PremiumCard(
          padding: EdgeInsets.zero,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TourismBookingScreen(initialDestination: item.name))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Stack(children: [
              Positioned.fill(child: Image.asset(item.image, fit: BoxFit.cover, cacheWidth: 500, filterQuality: FilterQuality.medium)),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.navy.withValues(alpha: .9)])))),
              Positioned(left: 13, right: 13, bottom: 13, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)), const SizedBox(height: 4), Row(children: [const Icon(Icons.star_rounded, color: AppColors.accent, size: 16), Text(' ${item.rating}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), const Spacer(), Text(item.travelTime, style: const TextStyle(color: Colors.white70, fontSize: 11))]), const SizedBox(height: 5), Row(children: [const Icon(Icons.shield_rounded, color: AppColors.success, size: 14), const SizedBox(width: 4), Text('${item.safetyScore}/100', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800))])])),
            ]),
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
        child: Row(children: [ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset(package.image, width: 82, height: 82, fit: BoxFit.cover, cacheWidth: 260)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(package.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))), StatusPill(label: '${package.safetyScore}/100')]), const SizedBox(height: 5), Text('${package.days} days · ${package.vehicle}', style: const TextStyle(color: AppColors.muted, fontSize: 11)), const SizedBox(height: 7), Row(children: [Text('PKR ${package.pricePerSeat ?? package.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)), Text(package.pricePerSeat != null ? '/${context.tr('seat')}' : '', style: const TextStyle(color: AppColors.muted, fontSize: 10)), const Spacer(), const Icon(Icons.chevron_right_rounded)])]))]),
      );
}
