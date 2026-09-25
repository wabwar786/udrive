import '../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';
import '../customer/package_detail_screen.dart';

class DriverRequestsScreen extends StatelessWidget {
  const DriverRequestsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(padding: const EdgeInsets.all(18), children: controller.requests.map((request) => Padding(padding: const EdgeInsets.only(bottom: 14), child: _RequestCard(request: request))).toList());
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});
  final RideRequest request;
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return PremiumCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [StatusPill(label: request.category, color: AppColors.secondary), Spacer(), Text(request.time, style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 13),
      _RouteLine(icon: Icons.trip_origin_rounded, color: AppColors.primary, text: request.pickup),
      const SizedBox(height: 8),
      _RouteLine(icon: Icons.location_on_rounded, color: AppColors.secondary, text: request.destination),
      const SizedBox(height: 13),
      Row(children: [const Icon(Icons.person_rounded, size: 18, color: AppColors.muted), Text(' ${request.customer} · ${request.passengers} passengers', style: const TextStyle(color: AppColors.muted, fontSize: 12)), const Spacer(), Text(request.distance, style: const TextStyle(fontWeight: FontWeight.w800))]),
      const Divider(height: 26),
      Row(children: [const Text('Customer offer', style: TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text('PKR ${request.offer}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
      if (request.status != 'New') ...[const SizedBox(height: 10), StatusPill(label: request.status, color: request.status == 'Accepted' ? AppColors.success : AppColors.warning)],
      const SizedBox(height: 14),
      Row(children: [Expanded(child: OutlinedButton(onPressed: request.status == 'New' ? () => _counter(context, request) : null, child: Text(context.tr('counterOffer')))), const SizedBox(width: 9), Expanded(child: FilledButton(onPressed: request.status == 'New' ? () { controller.acceptRequest(request); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride accepted. Customer notified.'))); } : null, child: Text(context.tr('accept'))))]),
    ]));
  }

  void _counter(BuildContext context, RideRequest request) {
    final field = TextEditingController(text: '${request.offer + 800}');
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('Send a counteroffer', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 14), TextField(controller: field, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your fare', prefixText: 'PKR ')), const SizedBox(height: 14), FilledButton(onPressed: () { final amount = int.tryParse(field.text) ?? request.offer; AppControllerScope.of(context).counterRequest(request, amount); Navigator.pop(context); }, child: const Text('Send counteroffer'))])));
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.icon, required this.color, required this.text});
  final IconData icon; final Color color; final String text;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 9), Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)))]);
}

// ActiveDriverTripScreen was here. Hardcoded "18 min · 12.4 km", a Message
// button that opened nothing, an "I have arrived" button that notified
// nobody, and an emergency button whose entire behaviour was a snackbar
// reading "Driver safety alert demo activated". The real one is
// LiveTripNavigationScreen, reached from the driver dashboard.

class DriverPackagesScreen extends StatelessWidget {
  const DriverPackagesScreen({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) {
    final packages = AppControllerScope.of(context).driverPackages;
    return ListView(padding: const EdgeInsets.all(18), children: [
      FilledButton.icon(onPressed: () => onNavigate('createPackage'), icon: const Icon(Icons.add_rounded), label: Text(context.tr('createPackage'))),
      const SizedBox(height: 16),
      ...packages.map((package) => Padding(padding: const EdgeInsets.only(bottom: 13), child: PremiumCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(package: package))), padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(23)), child: Image.asset(package.image, height: 150, width: double.infinity, fit: BoxFit.cover)), Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [StatusPill(label: package.status, color: package.status == 'Active' ? AppColors.success : AppColors.warning), const Spacer(), Text('PKR ${package.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]), const SizedBox(height: 10), Text(package.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text('${package.days} days · ${package.maxGuests} guests · ${package.vehicle}', style: const TextStyle(color: AppColors.muted, fontSize: 12)), const SizedBox(height: 12), const Row(children: [Expanded(child: _MiniStat(label: 'Views', value: '248')), SizedBox(width: 8), Expanded(child: _MiniStat(label: 'Offers', value: '12')), SizedBox(width: 8), Expanded(child: _MiniStat(label: 'Bookings', value: '5'))])]))])))),
    ]);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value}); final String label; final String value;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10))]));
}

// The older CreatePackageScreen was here, superseded by
// live_create_package_screen.dart. It duplicated the class name declared in
// create_package_screen.dart and carried "Dummy cover image selected".

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [AppColors.inkDeep, AppColors.primary])), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("This week's earnings", style: TextStyle(color: Colors.white70)), SizedBox(height: 6), Text('PKR 42,850', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)), SizedBox(height: 20), Row(children: [Expanded(child: _EarningStat(label: 'Trips', value: '17')), SizedBox(width: 8), Expanded(child: _EarningStat(label: 'Hours', value: '31.5')), SizedBox(width: 8), Expanded(child: _EarningStat(label: 'Rating', value: '4.9'))])])), const SizedBox(height: 18),
    PremiumCard(child: SizedBox(height: 180, child: CustomPaint(painter: _EarningsChart()))), const SizedBox(height: 18),
    SectionHeader(title: 'Recent earnings'), const SizedBox(height: 10),
    for (final e in const [('Islamabad → Muzaffarabad', 'Today · 4:30 PM', '7,200'), ('Pir Chinasi return trip', 'Today · 11:00 AM', '4,800'), ('Rawalpindi → Rawalakot', 'Yesterday', '8,600')]) Padding(padding: const EdgeInsets.only(bottom: 10), child: PremiumCard(child: Row(children: [const CircleAvatar(backgroundColor: AppTint.success, child: Icon(Icons.route_rounded, color: AppColors.primaryDark)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w900)), Text(e.$2, style: const TextStyle(color: AppColors.muted, fontSize: 11))])), Text('+ PKR ${e.$3}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success))]))),
  ]);
}
class _EarningStat extends StatelessWidget { const _EarningStat({required this.label, required this.value}); final String label; final String value; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))])); }
class _EarningsChart extends CustomPainter { @override void paint(Canvas canvas, Size size) { final grid = Paint()..color=AppColors.border..strokeWidth=1; for(var i=1;i<5;i++){final y=size.height*i/5;canvas.drawLine(Offset(0,y),Offset(size.width,y),grid);} final p=Paint()..color=AppColors.primary..strokeWidth=4..style=PaintingStyle.stroke..strokeCap=StrokeCap.round; final path=Path()..moveTo(0,size.height*.75)..cubicTo(size.width*.15,size.height*.55,size.width*.23,size.height*.72,size.width*.36,size.height*.42)..cubicTo(size.width*.5,size.height*.15,size.width*.62,size.height*.62,size.width*.75,size.height*.35)..cubicTo(size.width*.84,size.height*.2,size.width*.92,size.height*.3,size.width,size.height*.12); canvas.drawPath(path,p); } @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false; }

// The mock DriverWalletScreen and DriverDocumentsScreen that used to sit here
// have been removed. They were placeholders — hard-coded payout history, a
// "Dummy document selected for upload" snackbar — and the real screens now
// live in driver_wallet_screen.dart and driver_documents_screen.dart.
//
// Leaving them in place did not just duplicate work: two public classes with
// the same name in one package is an ambiguous import, and the build stopped
// dead the moment main_shell imported both files.

class DriverAvailabilityScreen extends StatefulWidget {
  const DriverAvailabilityScreen({super.key});

  @override
  State<DriverAvailabilityScreen> createState() => _DriverAvailabilityScreenState();
}

class _DriverAvailabilityScreenState extends State<DriverAvailabilityScreen> {
  final Set<int> selected = {1, 2, 3, 4, 5};
  bool nights = false;
  bool multi = true;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available days', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (i) {
                    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                    return FilterChip(
                      label: Text(names[i]),
                      selected: selected.contains(i + 1),
                      onSelected: (value) => setState(() {
                        if (value) {
                          selected.add(i + 1);
                        } else {
                          selected.remove(i + 1);
                        }
                      }),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: nights,
                  onChanged: (value) => setState(() => nights = value),
                  title: const Text('Night driving', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: multi,
                  onChanged: (value) => setState(() => multi = value),
                  title: const Text('Multi-day tours', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const PremiumCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.location_on_rounded, color: AppColors.primaryDark),
              title: Text('Operating areas', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('Islamabad · Rawalpindi · Muzaffarabad · Neelum Valley'),
              trailing: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Availability saved.')),
            ),
            child: Text(context.tr('save')),
          ),
        ],
      );
}

// DriverReviewsScreen was here. It showed every driver the same invented
// "4.9" over "846 trips" and three fabricated passenger reviews. The real
// figures live on DriverEarningsScreen.

class DriverProfileScreen extends StatelessWidget { const DriverProfileScreen({required this.onNavigate,super.key}); final ValueChanged<String> onNavigate; @override Widget build(BuildContext context){final c=AppControllerScope.of(context);return ListView(padding:const EdgeInsets.all(18),children:[PremiumCard(color:AppColors.navy,child:Column(children:[const CircleAvatar(radius:38,backgroundColor:Colors.white,child:Icon(Icons.person_rounded,size:42,color:AppColors.primaryDark)),const SizedBox(height:12),Text(c.currentUserName,style:const TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:4),Text(c.currentUserPhone,style:const TextStyle(color:Colors.white70,fontSize:11)),const SizedBox(height:13),StatusPill(label:c.driverVerificationStatus,color:c.driverApproved?AppColors.success:AppColors.warning)])),const SizedBox(height:15),FilledButton.icon(onPressed:()=>c.switchMode(UserMode.customer),icon:const Icon(Icons.person_rounded),label:Text(context.tr('switchCustomer'))),const SizedBox(height:13),for(final item in [('vehicles',Icons.directions_car_filled_rounded,context.tr('vehicles')),('documents',Icons.fact_check_rounded,context.tr('documents')),('availability',Icons.calendar_month_rounded,context.tr('availability')),('reviews',Icons.star_rounded,context.tr('reviews')),('settings',Icons.settings_rounded,context.tr('settings'))]) Padding(padding:const EdgeInsets.only(bottom:9),child:PremiumCard(onTap:()=>onNavigate(item.$1),child:Row(children:[Icon(item.$2,color:AppColors.primaryDark),const SizedBox(width:13),Expanded(child:Text(item.$3,style:const TextStyle(fontWeight:FontWeight.w900))),const Icon(Icons.chevron_right_rounded)]))) ]);}}
