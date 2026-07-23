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
      Row(children: [StatusPill(label: request.category, color: AppColors.secondary), const Spacer(), Text(request.time, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700))]),
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

class ActiveDriverTripScreen extends StatelessWidget {
  const ActiveDriverTripScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const MapPreview(height: 270),
    const SizedBox(height: 16),
    PremiumCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [StatusPill(label: 'Driving to pickup', color: AppColors.info), Spacer(), Text('18 min · 12.4 km', style: TextStyle(fontWeight: FontWeight.w900))]), const SizedBox(height: 15), const _RouteLine(icon: Icons.trip_origin_rounded, color: AppColors.primary, text: 'F-8 Markaz, Islamabad'), const SizedBox(height: 9), const _RouteLine(icon: Icons.location_on_rounded, color: AppColors.secondary, text: 'Muzaffarabad, Azad Kashmir'), const Divider(height: 26), const ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Icon(Icons.person_rounded)), title: Text('Hassan Ali', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('3 passengers · 2 bags'), trailing: Icon(Icons.call_rounded, color: AppColors.primaryDark))])),
    const SizedBox(height: 14),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo customer chat opened.'))), icon: const Icon(Icons.chat_rounded), label: const Text('Message'))), const SizedBox(width: 9), Expanded(child: FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arrival notification sent to customer.'))), icon: const Icon(Icons.notifications_active_rounded), label: const Text('I have arrived')))]),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => _otp(context), icon: const Icon(Icons.pin_rounded), label: const Text('Start trip with OTP')),
    const SizedBox(height: 10),
    OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver safety alert demo activated.'))), icon: const Icon(Icons.sos_rounded, color: AppColors.danger), label: const Text('Driver emergency support')),
  ]);
  void _otp(BuildContext context) { final c = TextEditingController(text: '6421'); showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Enter customer OTP'), content: TextField(controller: c, keyboardType: TextInputType.number, maxLength: 4), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip started successfully.'))); }, child: const Text('Start trip'))])); }
}

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

class CreatePackageScreen extends StatefulWidget {
  const CreatePackageScreen({super.key});
  @override State<CreatePackageScreen> createState() => _CreatePackageScreenState();
}
class _CreatePackageScreenState extends State<CreatePackageScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Neelum Valley Family Adventure');
  final _route = TextEditingController(text: 'Islamabad · Muzaffarabad · Keran · Sharda');
  final _price = TextEditingController(text: '62000');
  final _description = TextEditingController(text: 'A private, flexible family tour with scenic stops and a verified tourism driver.');
  int _days = 3; int _guests = 6; bool _offers = true; String _vehicle = 'Honda BR-V';
  final List<String> _itinerary = [
    'Day 1: Islamabad to Keran',
    'Day 2: Sharda and Upper Neelum',
    'Day 3: Return via Muzaffarabad',
  ];
  @override void dispose() { _title.dispose(); _route.dispose(); _price.dispose(); _description.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Form(key: _form, child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
    UploadTile(label: 'Package cover image', uploaded: true, icon: Icons.image_rounded, onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dummy cover image selected.')))), const SizedBox(height: 12),
    TextFormField(controller: _title, decoration: InputDecoration(labelText: context.tr('packageTitle')), validator: _required), const SizedBox(height: 12),
    TextFormField(controller: _route, maxLines: 2, decoration: InputDecoration(labelText: context.tr('startLocation')), validator: _required), const SizedBox(height: 12),
    DropdownButtonFormField<String>(value: _vehicle, decoration: InputDecoration(labelText: context.tr('vehicle')), items: const ['Honda BR-V', 'Toyota Corolla', 'Toyota Prado', 'Hiace Grand Cabin'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (value) => setState(() => _vehicle = value!)), const SizedBox(height: 12),
    Row(children: [Expanded(child: _NumberField(label: context.tr('duration'), value: _days, suffix: 'days', onChanged: (v) => setState(() => _days = v))), const SizedBox(width: 10), Expanded(child: _NumberField(label: context.tr('maxGuests'), value: _guests, suffix: 'guests', onChanged: (v) => setState(() => _guests = v)))]), const SizedBox(height: 12),
    TextFormField(controller: _price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('packagePrice'), prefixText: 'PKR '), validator: _required), const SizedBox(height: 12),
    TextFormField(controller: _description, maxLines: 4, decoration: InputDecoration(labelText: context.tr('description')), validator: _required), const SizedBox(height: 12),
    SwitchListTile(value: _offers, onChanged: (v) => setState(() => _offers = v), contentPadding: const EdgeInsets.symmetric(horizontal: 4), title: Text(context.tr('allowOffers'), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Customers can send a different package price.')), const SizedBox(height: 12),
    PremiumCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('itinerary'), style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 10), for (var index = 0; index < _itinerary.length; index++) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [const Icon(Icons.drag_indicator_rounded, color: AppColors.muted), const SizedBox(width: 6), Expanded(child: Text(_itinerary[index], style: const TextStyle(fontWeight: FontWeight.w700))), IconButton(onPressed: () => _editItineraryDay(index), icon: const Icon(Icons.edit_outlined, size: 18))])), OutlinedButton.icon(onPressed: _addItineraryDay, icon: const Icon(Icons.add_rounded), label: const Text('Add itinerary day'))])), const SizedBox(height: 16),
    Row(children: [Expanded(child: OutlinedButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package saved as draft.'))), child: Text(context.tr('saveDraft')))), const SizedBox(width: 10), Expanded(flex: 2, child: FilledButton(onPressed: _submit, child: Text(context.tr('submitApproval'))))]),
  ]));
  String? _required(String? v) => (v ?? '').trim().isEmpty ? context.tr('required') : null;
  Future<void> _addItineraryDay() async {
    final field = TextEditingController(text: 'Day ${_itinerary.length + 1}: New destination or activity');
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add itinerary day'),
        content: TextField(controller: field, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    field.dispose();
    if (value != null && value.isNotEmpty && mounted) setState(() => _itinerary.add(value));
  }

  Future<void> _editItineraryDay(int index) async {
    final field = TextEditingController(text: _itinerary[index]);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit itinerary day'),
        content: TextField(controller: field, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    field.dispose();
    if (value != null && value.isNotEmpty && mounted) setState(() => _itinerary[index] = value);
  }

  void _submit() { if (!_form.currentState!.validate()) return; AppControllerScope.of(context).addPackage(TourPackage(id: 'P-${DateTime.now().millisecondsSinceEpoch}', title: _title.text, route: _route.text, days: _days, price: int.parse(_price.text), image: 'assets/images/neelum.png', driver: 'Shahzad Ahmad', rating: 4.9, maxGuests: _guests, vehicle: _vehicle, description: _description.text, inclusions: const ['Private vehicle', 'Fuel and tolls', 'Driver services'], itinerary: List<String>.from(_itinerary), allowOffers: _offers, status: 'Pending')); showDialog(context: context, builder: (_) => AlertDialog(icon: const Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 48), title: const Text('Submitted for approval'), content: const Text('The package is now visible in your dashboard with Pending status.'), actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))])); }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.value, required this.suffix, required this.onChanged}); final String label; final int value; final String suffix; final ValueChanged<int> onChanged;
  @override Widget build(BuildContext context) => PremiumCard(padding: const EdgeInsets.all(12), child: Column(children: [Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), const SizedBox(height: 9), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton.filledTonal(onPressed: value > 1 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove, size: 17)), Text('$value\n$suffix', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), IconButton.filledTonal(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add, size: 17))]) ]));
}

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF0A493A), AppColors.primary])), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("This week's earnings", style: TextStyle(color: Colors.white70)), SizedBox(height: 6), Text('PKR 42,850', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)), SizedBox(height: 20), Row(children: [Expanded(child: _EarningStat(label: 'Trips', value: '17')), SizedBox(width: 8), Expanded(child: _EarningStat(label: 'Hours', value: '31.5')), SizedBox(width: 8), Expanded(child: _EarningStat(label: 'Rating', value: '4.9'))])])), const SizedBox(height: 18),
    PremiumCard(child: SizedBox(height: 180, child: CustomPaint(painter: _EarningsChart()))), const SizedBox(height: 18),
    SectionHeader(title: 'Recent earnings'), const SizedBox(height: 10),
    for (final e in const [('Islamabad → Muzaffarabad', 'Today · 4:30 PM', '7,200'), ('Pir Chinasi return trip', 'Today · 11:00 AM', '4,800'), ('Rawalpindi → Rawalakot', 'Yesterday', '8,600')]) Padding(padding: const EdgeInsets.only(bottom: 10), child: PremiumCard(child: Row(children: [const CircleAvatar(backgroundColor: Color(0xFFEAF8F3), child: Icon(Icons.route_rounded, color: AppColors.primaryDark)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w900)), Text(e.$2, style: const TextStyle(color: AppColors.muted, fontSize: 11))])), Text('+ PKR ${e.$3}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success))]))),
  ]);
}
class _EarningStat extends StatelessWidget { const _EarningStat({required this.label, required this.value}); final String label; final String value; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))])); }
class _EarningsChart extends CustomPainter { @override void paint(Canvas canvas, Size size) { final grid = Paint()..color=AppColors.border..strokeWidth=1; for(var i=1;i<5;i++){final y=size.height*i/5;canvas.drawLine(Offset(0,y),Offset(size.width,y),grid);} final p=Paint()..color=AppColors.primary..strokeWidth=4..style=PaintingStyle.stroke..strokeCap=StrokeCap.round; final path=Path()..moveTo(0,size.height*.75)..cubicTo(size.width*.15,size.height*.55,size.width*.23,size.height*.72,size.width*.36,size.height*.42)..cubicTo(size.width*.5,size.height*.15,size.width*.62,size.height*.62,size.width*.75,size.height*.35)..cubicTo(size.width*.84,size.height*.2,size.width*.92,size.height*.3,size.width,size.height*.12); canvas.drawPath(path,p); } @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false; }

class DriverWalletScreen extends StatelessWidget {
  const DriverWalletScreen({super.key});
  @override Widget build(BuildContext context) { final c=AppControllerScope.of(context); return ListView(padding: const EdgeInsets.all(18), children: [Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors:[Color(0xFF1B365D),AppColors.secondary])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[const Text('Available for payout',style:TextStyle(color:Colors.white70)),const SizedBox(height:5),Text('PKR ${c.walletBalance}',style:const TextStyle(color:Colors.white,fontSize:32,fontWeight:FontWeight.w900)),const SizedBox(height:20),FilledButton(onPressed:()=>_payout(context,c),style:FilledButton.styleFrom(backgroundColor:Colors.white,foregroundColor:AppColors.secondary),child:Text(context.tr('withdraw')))])),const SizedBox(height:18),PremiumCard(child:const Column(children:[ListTile(contentPadding:EdgeInsets.zero,leading:Icon(Icons.account_balance_rounded,color:AppColors.secondary),title:Text('Meezan Bank',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('**** 4821 · Shahzad Ahmad'),trailing:StatusPill(label:'Primary')),Divider(),ListTile(contentPadding:EdgeInsets.zero,leading:Icon(Icons.qr_code_rounded,color:AppColors.primaryDark),title:Text('Raast ID',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('+92 300 1234567'),trailing:StatusPill(label:'Verified',color:AppColors.success))])),const SizedBox(height:18),SectionHeader(title:'Payout history'),const SizedBox(height:10),for(final x in const [('PKR 25,000','10 Jul 2026','Completed'),('PKR 18,500','03 Jul 2026','Completed')]) Padding(padding:const EdgeInsets.only(bottom:10),child:PremiumCard(child:Row(children:[const Icon(Icons.south_west_rounded,color:AppColors.success),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(x.$1,style:const TextStyle(fontWeight:FontWeight.w900)),Text(x.$2,style:const TextStyle(color:AppColors.muted,fontSize:11))])),StatusPill(label:x.$3,color:AppColors.success)]))) ]); }
  void _payout(BuildContext context,AppController c){final f=TextEditingController(text:'5000');showModalBottomSheet(context:context,isScrollControlled:true,builder:(_)=>Padding(padding:EdgeInsets.fromLTRB(20,20,20,MediaQuery.viewInsetsOf(context).bottom+20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('Request payout',style:TextStyle(fontSize:21,fontWeight:FontWeight.w900)),const SizedBox(height:14),TextField(controller:f,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Amount',prefixText:'PKR ')),const SizedBox(height:14),FilledButton(onPressed:(){c.requestPayout(int.tryParse(f.text)??0);Navigator.pop(context);},child:const Text('Submit payout request'))])));}
}

class DriverDocumentsScreen extends StatelessWidget { const DriverDocumentsScreen({super.key}); @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[PremiumCard(color:const Color(0xFFF1FAF6),child:const Row(children:[Icon(Icons.verified_user_rounded,color:AppColors.success,size:36),SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Identity verified',style:TextStyle(fontWeight:FontWeight.w900)),SizedBox(height:4),Text('Your driver account can receive ride and package bookings.',style:TextStyle(color:AppColors.muted,fontSize:12))]))])),const SizedBox(height:16),...driverDocuments.map((d)=>Padding(padding:const EdgeInsets.only(bottom:10),child:PremiumCard(child:Row(children:[Container(width:45,height:45,decoration:BoxDecoration(color:verificationColor(d.status).withValues(alpha:.11),borderRadius:BorderRadius.circular(14)),child:Icon(Icons.description_rounded,color:verificationColor(d.status))),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(d.title,style:const TextStyle(fontWeight:FontWeight.w900)),Text('${d.number} · Expiry: ${d.expiry}',style:const TextStyle(color:AppColors.muted,fontSize:11))])),StatusPill(label:verificationLabel(context,d.status),color:verificationColor(d.status))])))),OutlinedButton.icon(onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Dummy driver document selected and queued for review.'))),icon:const Icon(Icons.upload_file_rounded),label:const Text('Upload another document'))]); }

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

class DriverReviewsScreen extends StatelessWidget { const DriverReviewsScreen({super.key}); @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[Row(children:const [MetricTile(icon:Icons.star_rounded,label:'Overall rating',value:'4.9',color:AppColors.accent),SizedBox(width:10),MetricTile(icon:Icons.route_rounded,label:'Total trips',value:'846',color:AppColors.primary)]),const SizedBox(height:18),for(final r in const [('Ayesha Noor','Excellent safe driver and very clean vehicle.','5.0'),('Hassan Ali','Punctual and knows the Kashmir routes very well.','4.9'),('Waqar Ahmed','Great family trip and flexible stops.','4.8')]) Padding(padding:const EdgeInsets.only(bottom:11),child:PremiumCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const CircleAvatar(child:Icon(Icons.person_rounded)),const SizedBox(width:10),Expanded(child:Text(r.$1,style:const TextStyle(fontWeight:FontWeight.w900))),StatusPill(label:'${r.$3} ★',color:AppColors.accent)]),const SizedBox(height:10),Text(r.$2,style:const TextStyle(color:AppColors.muted,height:1.4))]))) ]); }

class DriverProfileScreen extends StatelessWidget { const DriverProfileScreen({required this.onNavigate,super.key}); final ValueChanged<String> onNavigate; @override Widget build(BuildContext context){final c=AppControllerScope.of(context);return ListView(padding:const EdgeInsets.all(18),children:[PremiumCard(color:const Color(0xFF0D4337),child:const Column(children:[CircleAvatar(radius:38,backgroundColor:Colors.white,child:Icon(Icons.person_rounded,size:42,color:AppColors.primaryDark)),SizedBox(height:12),Text('Shahzad Ahmad Qureshi',style:TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w900)),SizedBox(height:4),Text('Driver ID UD-00941 · 4.9 ★',style:TextStyle(color:Colors.white70,fontSize:11)),SizedBox(height:13),StatusPill(label:'Approved driver',color:AppColors.success)])),const SizedBox(height:15),FilledButton.icon(onPressed:()=>c.switchMode(UserMode.customer),icon:const Icon(Icons.person_rounded),label:Text(context.tr('switchCustomer'))),const SizedBox(height:13),for(final item in [('vehicles',Icons.directions_car_filled_rounded,context.tr('vehicles')),('documents',Icons.fact_check_rounded,context.tr('documents')),('availability',Icons.calendar_month_rounded,context.tr('availability')),('reviews',Icons.star_rounded,context.tr('reviews')),('settings',Icons.settings_rounded,context.tr('settings'))]) Padding(padding:const EdgeInsets.only(bottom:9),child:PremiumCard(onTap:()=>onNavigate(item.$1),child:Row(children:[Icon(item.$2,color:AppColors.primaryDark),const SizedBox(width:13),Expanded(child:Text(item.$3,style:const TextStyle(fontWeight:FontWeight.w900))),const Icon(Icons.chevron_right_rounded)]))) ]);}}
