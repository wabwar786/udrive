import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/app_theme.dart';
import '../data/dummy_data.dart';
import '../models/models.dart';
class RequestsScreen extends StatelessWidget { const RequestsScreen({super.key});
  @override Widget build(BuildContext context)=>SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
    Text(DS.of(context,'requests'),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),const SizedBox(height:18),
    ...rideRequests.map((r)=>Padding(padding:const EdgeInsets.only(bottom:12),child:_card(context,r))),
  ]));
  Widget _card(BuildContext context,RideRequest r)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Chip(label:Text(r.type)),const Spacer(),Text(r.time,style:const TextStyle(color:AppColors.muted))]),const SizedBox(height:10),
    Text(r.route,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text('${r.distance} · ${r.passengers} passengers · ${r.customer}',style:const TextStyle(color:AppColors.muted)),
    const Divider(height:28),Row(children:[Text('Customer offer  PKR ${r.offer}',style:const TextStyle(fontWeight:FontWeight.w900,color:AppColors.primary)),const Spacer(),IconButton(onPressed:(){},icon:const Icon(Icons.chat_bubble_outline))]),
    const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_counter(context,r),child:Text(DS.of(context,'counter')))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>_message(context,'Ride accepted'),child:Text(DS.of(context,'accept'))))]),
  ])));
  void _counter(BuildContext context,RideRequest r){ final c=TextEditingController(text:'${r.offer+500}'); showDialog(context:context,builder:(context)=>AlertDialog(title:const Text('Submit counteroffer'),content:TextField(controller:c,keyboardType:TextInputType.number,decoration:const InputDecoration(prefixText:'PKR ')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){Navigator.pop(context);_message(context,'Counteroffer sent');},child:const Text('Send'))])); }
  void _message(BuildContext context,String text)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
}
