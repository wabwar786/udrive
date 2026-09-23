import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../models/booking_models.dart';
import 'live_create_package_screen.dart';

class LiveDriverPackagesScreen extends StatefulWidget {
  const LiveDriverPackagesScreen({super.key});
  @override State<LiveDriverPackagesScreen> createState()=>_LiveDriverPackagesScreenState();
}

class _LiveDriverPackagesScreenState extends State<LiveDriverPackagesScreen>{
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>_refresh());}
  Future<void> _refresh()=>AppControllerScope.of(context).loadDriverMarketplace();
  @override Widget build(BuildContext context){
    final c=AppControllerScope.of(context);
    return RefreshIndicator(onRefresh:_refresh,child:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,90),children:[
      PremiumCard(color:const Color(0xFF0D4337),child:Row(children:[const Icon(Icons.luggage_rounded,color:Colors.white,size:38),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_t(context,'Your tourism marketplace','آپ کی ٹورزم مارکیٹ پلیس'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:19)),const SizedBox(height:4),Text(_t(context,'Create packages, manage approvals, inventory and customer offers.','پیکجز بنائیں، منظوری، نشستیں اور کسٹمر آفرز منظم کریں۔'),style:const TextStyle(color:Colors.white70,fontSize:12))]))])),
      const SizedBox(height:14),FilledButton.icon(onPressed:()=>_create(context),icon:const Icon(Icons.add_rounded),label:Text(_t(context,'Create live tour package','لائیو ٹور پیکج بنائیں'))),
      const SizedBox(height:20),SectionHeader(title:_t(context,'My live packages','میرے لائیو پیکجز')),const SizedBox(height:8),
      if(c.liveDriverPackages.isEmpty) PremiumCard(child:Text(_t(context,'No database package yet. Create a package and submit it for Admin approval.','ابھی کوئی ڈیٹابیس پیکج نہیں۔ پیکج بنائیں اور ایڈمن منظوری کے لیے جمع کریں۔'),style:const TextStyle(color:AppColors.muted,height:1.4))) else ...c.liveDriverPackages.map((p)=>Padding(padding:const EdgeInsets.only(bottom:12),child:_DriverPackageCard(package:p,onRefresh:_refresh))),
      const SizedBox(height:20),SectionHeader(title:_t(context,'Customer package offers','کسٹمر پیکج آفرز')),const SizedBox(height:8),
      if(c.liveDriverPackageOffers.isEmpty) PremiumCard(child:Text(_t(context,'No open customer offers.','کوئی کھلی کسٹمر آفر نہیں۔'),style:const TextStyle(color:AppColors.muted))) else ...c.liveDriverPackageOffers.map((o)=>Padding(padding:const EdgeInsets.only(bottom:10),child:_OfferCard(offer:o,onReviewed:_refresh))),
    ]));
  }
  Future<void> _create(BuildContext context) async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>const LiveCreatePackageScreen()));if(mounted)await _refresh();}
  String _t(BuildContext context,String en,String ur)=>AppControllerScope.of(context).locale.languageCode=='ur'?ur:en;
}

class _DriverPackageCard extends StatelessWidget{
 const _DriverPackageCard({required this.package,required this.onRefresh});final LiveTourPackage package;final Future<void> Function() onRefresh;
 @override Widget build(BuildContext context)=>PremiumCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(package.title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17))),StatusPill(label:package.status,color:_statusColor(package.status))]),const SizedBox(height:7),Text('${package.startingCity} → ${package.destination}',style:const TextStyle(color:AppColors.muted,fontWeight:FontWeight.w700)),const SizedBox(height:10),Wrap(spacing:12,runSpacing:7,children:[_Fact(Icons.calendar_month_rounded,DateFormat('dd MMM yyyy').format(package.departureAt)),_Fact(Icons.event_seat_rounded,'${package.availableSeats}/${package.totalSeats} available'),_Fact(Icons.payments_rounded,'PKR ${NumberFormat('#,###').format(package.pricePerSeat)}/seat')]),if(package.reviewNotes?.isNotEmpty==true)...[const SizedBox(height:10),Text(package.reviewNotes!,style:const TextStyle(color:AppColors.danger,fontSize:12,fontWeight:FontWeight.w700))],const SizedBox(height:14),Row(children:[if(['Draft','ChangesRequired','Rejected'].contains(package.status))Expanded(child:FilledButton(onPressed:()=>_submit(context),child:const Text('Submit approval'))),if(package.status=='Active')Expanded(child:OutlinedButton(onPressed:()=>_toggle(context,false),child:const Text('Pause'))),if(package.status=='Paused')Expanded(child:FilledButton(onPressed:()=>_toggle(context,true),child:const Text('Activate'))),if(package.status=='PendingApproval')const Expanded(child:Text('Admin review in progress',textAlign:TextAlign.center,style:TextStyle(color:AppColors.warning,fontWeight:FontWeight.w800)))]) ]));
 Future<void> _submit(BuildContext context)async{try{await AppControllerScope.of(context).submitLiveDriverPackage(package.id);await onRefresh();if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Package submitted for Admin approval.')));}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
 Future<void> _toggle(BuildContext context,bool active)async{try{await AppControllerScope.of(context).toggleLiveDriverPackage(package.id,active);await onRefresh();}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
 Color _statusColor(String s)=>s=='Active'?AppColors.success:s=='Rejected'?AppColors.danger:s=='PendingApproval'?AppColors.warning:AppColors.primary;
}

class _OfferCard extends StatelessWidget{
 const _OfferCard({required this.offer,required this.onReviewed});final LivePackageOffer offer;final Future<void> Function() onReviewed;
 @override Widget build(BuildContext context)=>PremiumCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(offer.packageTitle,style:const TextStyle(fontWeight:FontWeight.w900))),StatusPill(label:offer.status)]),const SizedBox(height:7),Text('${offer.customerName} · ${offer.bookingType} · ${offer.seatsRequested} seat(s)',style:const TextStyle(color:AppColors.muted)),const SizedBox(height:8),Text('Customer offer: PKR ${NumberFormat('#,###').format(offer.offeredAmount)}',style:const TextStyle(fontWeight:FontWeight.w900,color:AppColors.primaryDark)),if(offer.counterAmount!=null)Text('Your counter: PKR ${NumberFormat('#,###').format(offer.counterAmount)}'),if(['Pending','Countered'].contains(offer.status))...[const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_review(context,'reject'),child:const Text('Reject'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>_review(context,'accept'),child:const Text('Accept'))),const SizedBox(width:8),IconButton.filledTonal(onPressed:()=>_counter(context),icon:const Icon(Icons.swap_horiz_rounded))])]]) );
 Future<void> _review(BuildContext context,String decision,{double? counter})async{try{await AppControllerScope.of(context).reviewLivePackageOffer(offerId:offer.id,decision:decision,counterAmount:counter,message:decision=='counter'?'Driver counteroffer':null);await onReviewed();}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
 Future<void> _counter(BuildContext context)async{final input=TextEditingController(text:(offer.offeredAmount*1.1).round().toString());await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Counteroffer'),content:TextField(controller:input,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Counter amount (PKR)')),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel')),FilledButton(onPressed:()async{Navigator.pop(dialog);await _review(context,'counter',counter:double.tryParse(input.text));},child:const Text('Send'))]));}
}
class _Fact extends StatelessWidget{const _Fact(this.icon,this.text);final IconData icon;final String text;@override Widget build(BuildContext context)=>Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:16,color:AppColors.muted),const SizedBox(width:5),Text(text,style:const TextStyle(color:AppColors.muted,fontSize:11,fontWeight:FontWeight.w700))]);}
