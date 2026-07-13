import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/app_theme.dart';
class DriverProfileScreen extends StatelessWidget { const DriverProfileScreen({super.key});
  @override Widget build(BuildContext context){final lang=DriverLanguageScope.of(context);return SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
    Text(DS.of(context,'profile'),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),const SizedBox(height:16),
    const Card(child:Padding(padding:EdgeInsets.all(18),child:Row(children:[CircleAvatar(radius:34,backgroundColor:AppColors.primary,child:Text('UK',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900))),SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Usman Khan',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),Text('Toyota Corolla · LEA-219',style:TextStyle(color:AppColors.muted)),SizedBox(height:5),Text('★ 4.9 · 834 trips')]))]))),
    const SizedBox(height:12),
    ...[('Documents',Icons.badge_outlined,'All verified'),('Vehicle',Icons.directions_car_outlined,'Toyota Corolla 2022'),('Service areas',Icons.map_outlined,'Muzaffarabad, Neelum'),('Availability',Icons.calendar_month_outlined,'Open schedule')].map((i)=>Padding(padding:const EdgeInsets.only(bottom:9),child:Card(child:ListTile(leading:Icon(i.$2,color:AppColors.primary),title:Text(i.$1,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(i.$3),trailing:const Icon(Icons.chevron_right))))),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(DS.of(context,'language'),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:12),SegmentedButton<String>(segments:const [ButtonSegment(value:'en',label:Text('English')),ButtonSegment(value:'ur',label:Text('اردو'))],selected:{lang.locale.languageCode},onSelectionChanged:(v)=>lang.setLanguage(v.first))]))),
  ]));}
}
