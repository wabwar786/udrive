import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/udrive_logo.dart';
import '../../data/dummy_data.dart';
import '../packages/package_detail_screen.dart';
import '../ride/create_ride_screen.dart';
import '../hotels/hotel_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Row(
            children: [
              const UDriveLogo(compact: true),
              const Spacer(),
              IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
              const SizedBox(width: 6),
              const CircleAvatar(child: Text('SQ')),
            ],
          ),
          const SizedBox(height: 22),
          Text(S.of(context, 'greeting'), style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(S.of(context, 'whereTo'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
          const SizedBox(height: 18),
          _SearchCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRideScreen()))),
          const SizedBox(height: 18),
          const _MapPreview(),
          const SizedBox(height: 22),
          _ServiceGrid(onSelected: (service) {
            if (service == 'Hotels & Stays') { Navigator.push(context, MaterialPageRoute(builder: (_) => const HotelListScreen())); return; }
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRideScreen()));
          }),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(15)),
                    child: const Icon(Icons.warning_amber_rounded, color: AppColors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(S.of(context, 'roadAlert'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    const Text('Kel–Taobat route: 4×4 recommended after Sharda.', style: TextStyle(color: AppColors.muted)),
                  ])),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: Text(S.of(context, 'popular'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
            TextButton(onPressed: () {}, child: Text(S.of(context, 'viewAll'))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 238,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tourPackages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = tourPackages[index];
                return SizedBox(
                  width: 260,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(package: item))),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          height: 108,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Color(item.imageColor), Color(item.imageColor).withValues(alpha: .55)]),
                          ),
                          child: const Center(child: Icon(Icons.landscape_rounded, size: 56, color: Colors.white)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(item.route, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                            const SizedBox(height: 12),
                            Row(children: [
                              const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                              Text(' ${item.rating}'),
                              const Spacer(),
                              Text('PKR ${item.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.search_rounded, color: AppColors.primary)),
          const SizedBox(width: 13),
          Expanded(child: Text(S.of(context, 'whereTo'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          const Icon(Icons.arrow_forward_rounded),
        ]),
      ),
    ),
  );
}

class _MapPreview extends StatelessWidget {
  const _MapPreview();
  @override
  Widget build(BuildContext context) => Container(
    height: 185,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFDDEFE9), Color(0xFFDDE8FB)]),
    ),
    child: Stack(children: [
      ...List.generate(6, (i) => Positioned(left: 20.0 + i * 55, top: i.isEven ? 28 : 110, child: Container(width: 70, height: 3, transform: Matrix4.rotationZ(i.isEven ? .45 : -.35), color: Colors.white.withValues(alpha: .75)))),
      const Positioned(left: 55, top: 65, child: Icon(Icons.location_on_rounded, color: AppColors.secondary, size: 42)),
      const Positioned(right: 60, bottom: 35, child: Icon(Icons.directions_car_filled_rounded, color: AppColors.primary, size: 36)),
      Positioned(right: 12, top: 12, child: IconButton.filled(onPressed: () {}, icon: const Icon(Icons.my_location_rounded))),
      const Positioned(left: 16, bottom: 14, child: Chip(avatar: Icon(Icons.circle, size: 12, color: AppColors.primary), label: Text('Muzaffarabad'))),
    ]),
  );
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.onSelected});
  final ValueChanged<String> onSelected;
  @override Widget build(BuildContext context) {
    const services = [
      ('City-to-City Ride','Car • Bike • Rickshaw',Icons.local_taxi_rounded),
      ('Tours & Trips','Coaster • Car • Shared seats',Icons.route_rounded),
      ('Private Vehicle','Car • Coaster • Bike',Icons.directions_car_filled_rounded),
      ('Hotels & Stays','Rooms • Transport • Packages',Icons.hotel_rounded),
    ];
    return GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,mainAxisSpacing:9,crossAxisSpacing:9,childAspectRatio:1.42),itemCount:services.length,itemBuilder:(context,i){final x=services[i];return InkWell(borderRadius:BorderRadius.circular(16),onTap:()=>onSelected(x.$1),child:Container(padding:const EdgeInsets.all(11),decoration:BoxDecoration(color:const Color(0xFF1D292F),borderRadius:BorderRadius.circular(16)),child:Stack(children:[Positioned(right:-12,bottom:-18,child:Container(width:78,height:78,decoration:const BoxDecoration(color:Color(0xFF9BE43A),shape:BoxShape.circle))),Positioned(right:8,bottom:7,child:Icon(x.$3,size:40,color:const Color(0xFF17242B))),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(x.$3,size:17,color:const Color(0xFF9BE43A)),const Spacer(),Text(x.$1,maxLines:2,style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w900,height:1.05)),const SizedBox(height:3),Padding(padding:const EdgeInsets.only(right:48),child:Text(x.$2,maxLines:2,style:const TextStyle(color:Colors.white60,fontSize:8.5,height:1.15)))])])));});
  }
}
