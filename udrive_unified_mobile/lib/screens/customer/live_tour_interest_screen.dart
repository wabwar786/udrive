import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';

class LiveTourInterestScreen extends StatefulWidget {
  const LiveTourInterestScreen({super.key});
  @override State<LiveTourInterestScreen> createState()=>_LiveTourInterestScreenState();
}

class _LiveTourInterestScreenState extends State<LiveTourInterestScreen> {
  static const destinations = <String,String>{
    '10000000-0000-0000-0000-000000000002':'Neelum Valley',
    '10000000-0000-0000-0000-000000000003':'Sharda',
    '10000000-0000-0000-0000-000000000004':'Rawalakot',
    '10000000-0000-0000-0000-000000000005':'Banjosa Lake',
    '10000000-0000-0000-0000-000000000006':'Pir Chinasi',
  };
  String _destinationId=destinations.keys.first;
  String _preference='Family';
  DateTime _date=DateTime.now().add(const Duration(days:7));
  int _persons=2;
  final _pickup=TextEditingController(text:'Muzaffarabad');
  final _budget=TextEditingController(text:'5000');
  bool _busy=false;
  @override void dispose(){_pickup.dispose();_budget.dispose();super.dispose();}

  @override Widget build(BuildContext context){
    final c=AppControllerScope.of(context);
    return RefreshIndicator(onRefresh:c.refreshPhase9Marketplace,child:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,30),children:[
      PremiumCard(color:const Color(0xFF0D4337),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.auto_awesome_rounded,color:AppColors.accent,size:34),const SizedBox(height:12),Text(_t(context,'Tell uDrive where you want to go','یو ڈرائیو کو بتائیں آپ کہاں جانا چاہتے ہیں'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:20)),const SizedBox(height:6),Text(_t(context,'We match your date, group, seats, budget and pickup city with approved Driver packages.','ہم آپ کی تاریخ، گروپ، نشستوں، بجٹ اور شہر کو منظور شدہ ڈرائیور پیکجز سے میچ کرتے ہیں۔'),style:const TextStyle(color:Colors.white70,height:1.4))])),
      const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:_destinationId,decoration:const InputDecoration(labelText:'Destination',prefixIcon:Icon(Icons.landscape_rounded)),items:destinations.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setState(()=>_destinationId=v!)),
      const SizedBox(height:10),TextField(controller:_pickup,decoration:const InputDecoration(labelText:'Pickup city',prefixIcon:Icon(Icons.location_city_rounded))),
      const SizedBox(height:10),InkWell(onTap:_pickDate,borderRadius:BorderRadius.circular(16),child:InputDecorator(decoration:const InputDecoration(labelText:'Preferred date',prefixIcon:Icon(Icons.calendar_month_rounded)),child:Text(DateFormat('dd MMM yyyy').format(_date)))),
      const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:_preference,decoration:const InputDecoration(labelText:'Group preference',prefixIcon:Icon(Icons.groups_rounded)),items:['Family','WomenOnly','Individual','Group'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setState(()=>_preference=v!)),
      const SizedBox(height:10),PremiumCard(child:Row(children:[const Expanded(child:Text('Tour persons',style:TextStyle(fontWeight:FontWeight.w900))),IconButton(onPressed:_persons>1?()=>setState(()=>_persons--):null,icon:const Icon(Icons.remove_circle_outline_rounded)),Text('$_persons',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),IconButton(onPressed:()=>setState(()=>_persons++),icon:const Icon(Icons.add_circle_outline_rounded))])),
      const SizedBox(height:10),TextField(controller:_budget,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Maximum budget per seat (PKR)',prefixIcon:Icon(Icons.payments_rounded))),
      const SizedBox(height:16),FilledButton.icon(onPressed:_busy?null:_register,icon:_busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.notifications_active_rounded),label:Text(_t(context,'Register & find matching tours','رجسٹر کریں اور میچنگ ٹور تلاش کریں'))),
      const SizedBox(height:22),const SectionHeader(title:'Matching departures'),const SizedBox(height:8),
      if(c.liveTourMatches.isEmpty) PremiumCard(child:Text(_t(context,'No active match yet. Your registration remains active and new approved packages can match later.','ابھی کوئی فعال میچ نہیں۔ آپ کی رجسٹریشن فعال رہے گی اور نئے منظور شدہ پیکجز بعد میں میچ ہو سکتے ہیں۔'),style:const TextStyle(color:AppColors.muted,height:1.4))) else ...c.liveTourMatches.map((m)=>Padding(padding:const EdgeInsets.only(bottom:10),child:PremiumCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[StatusPill(label:'${m.matchPercent}% match'),const Spacer(),Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:m.availableSeats<=2?const Color(0xFFFFE9C7):const Color(0xFFD9F8E9),borderRadius:BorderRadius.circular(999)),child:Text('${m.availableSeats} seats free',style:TextStyle(fontWeight:FontWeight.w900,fontSize:10,color:m.availableSeats<=2?const Color(0xFF9A5A00):const Color(0xFF087A4B))))]),const SizedBox(height:10),Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:11,vertical:10),decoration:BoxDecoration(color:const Color(0xFFEAF7F2),borderRadius:BorderRadius.circular(12)),child:Row(children:[const Icon(Icons.location_on_rounded,size:16,color:AppColors.primary),const SizedBox(width:6),Expanded(child:Text(m.destination,style:const TextStyle(color:AppColors.primaryDark,fontWeight:FontWeight.w900,fontSize:14)))])),const SizedBox(height:8),Text(m.packageTitle,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),Text(DateFormat('dd MMM').format(m.departureAt),style:const TextStyle(color:AppColors.muted,fontSize:10.5)),const SizedBox(height:10),Row(children:[Expanded(child:Text('${m.driverName} · Safety ${m.safetyScore}/100',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700))),Text('PKR ${NumberFormat('#,###').format(m.pricePerSeat)}',style:const TextStyle(fontWeight:FontWeight.w900,color:AppColors.primaryDark))])])))),
    ]));
  }
  Future<void> _pickDate() async {final v=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:365)));if(v!=null)setState(()=>_date=v);}
  Future<void> _register() async {setState(()=>_busy=true);try{await AppControllerScope.of(context).createLiveTourInterest({'destinationId':_destinationId,'preferredStartDate':DateFormat('yyyy-MM-dd').format(_date),'preferredEndDate':DateFormat('yyyy-MM-dd').format(_date.add(const Duration(days:5))),'persons':_persons,'groupPreference':_preference,'budgetPerSeat':double.tryParse(_budget.text),'pickupCity':_pickup.text.trim()});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Tour interest registered and matching completed.')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}finally{if(mounted)setState(()=>_busy=false);}}
  String _t(BuildContext context,String en,String ur)=>AppControllerScope.of(context).locale.languageCode=='ur'?ur:en;
}
