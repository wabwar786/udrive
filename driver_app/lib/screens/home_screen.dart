import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/app_theme.dart';
import '../data/dummy_data.dart';
class DriverHomeScreen extends StatefulWidget { const DriverHomeScreen({super.key}); @override State<DriverHomeScreen> createState()=>_DriverHomeScreenState(); }
class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool online=true;
  @override Widget build(BuildContext context)=>SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
    Row(children:[Container(width:44,height:44,decoration:BoxDecoration(gradient:const LinearGradient(colors:[AppColors.primary,AppColors.secondary]),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.route,color:Colors.white)),const SizedBox(width:10),const Text('UDrive Driver',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),const Spacer(),const CircleAvatar(child:Text('UK'))]),
    const SizedBox(height:22),
    Card(child:Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:12,height:12,decoration:BoxDecoration(color:online?Colors.green:Colors.grey,shape:BoxShape.circle)),const SizedBox(width:10),Expanded(child:Text(online?DS.of(context,'online'):DS.of(context,'offline'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))),Switch(value:online,onChanged:(v)=>setState(()=>online=v))]))),
    const SizedBox(height:14),
    Container(height:190,decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Color(0xFFDDEFE9),Color(0xFFDDE8FB)])),child:const Stack(children:[Positioned(left:55,top:55,child:Icon(Icons.location_on,color:AppColors.secondary,size:40)),Center(child:Icon(Icons.directions_car_filled,color:AppColors.primary,size:44)),Positioned(right:18,top:16,child:Chip(label:Text('3 nearby requests')))])),
    const SizedBox(height:18),
    Row(children:[Expanded(child:_stat('PKR 8,450','Today earnings',Icons.payments_outlined)),const SizedBox(width:10),Expanded(child:_stat('6','Trips today',Icons.route_outlined))]),
    const SizedBox(height:22),
    Row(children:[Text(DS.of(context,'newRequests'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const Spacer(),TextButton(onPressed:(){},child:const Text('View all'))]),
    ...rideRequests.take(2).map((r)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(contentPadding:const EdgeInsets.all(14),leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(r.route,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('${r.type} · ${r.distance} · ${r.passengers} passengers'),trailing:Text('PKR ${r.offer}',style:const TextStyle(fontWeight:FontWeight.w900,color:AppColors.primary))))),
  ]));
  Widget _stat(String value,String label,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:AppColors.primary),const SizedBox(height:12),Text(value,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),Text(label,style:const TextStyle(color:AppColors.muted))])));
}
