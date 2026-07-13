import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/app_theme.dart';
import '../data/dummy_data.dart';
import 'create_package_screen.dart';
class PackagesScreen extends StatelessWidget { const PackagesScreen({super.key});
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
    Row(children:[Expanded(child:Text(DS.of(context,'myPackages'),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900))),IconButton.filled(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CreatePackageScreen())),icon:const Icon(Icons.add))]),
    const SizedBox(height:8),const Text('Create and manage your own tourism packages.',style:TextStyle(color:AppColors.muted)),const SizedBox(height:18),
    ...driverPackages.map((p)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text(p.title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900))),Chip(label:Text(p.status))]),const SizedBox(height:6),Text(p.route,style:const TextStyle(color:AppColors.muted)),const SizedBox(height:14),
      Row(children:[Text('${p.days} days'),const SizedBox(width:18),Text('${p.bookings} bookings'),const Spacer(),Text('PKR ${p.price}',style:const TextStyle(fontWeight:FontWeight.w900,color:AppColors.primary))]),
    ]))))),
  ])),floatingActionButton:FloatingActionButton.extended(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CreatePackageScreen())),icon:const Icon(Icons.add),label:Text(DS.of(context,'createPackage'))));
}
