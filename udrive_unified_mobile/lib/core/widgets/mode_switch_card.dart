import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class ModeSwitchCard extends StatelessWidget {
  const ModeSwitchCard({required this.targetMode, super.key});
  final UserMode targetMode;
  @override Widget build(BuildContext context) {
    final c=AppControllerScope.of(context);
    final isDriver=targetMode==UserMode.driver; final isHotel=targetMode==UserMode.hotel;
    final title=isDriver?'Switch to Driver Mode':isHotel?'Switch to Hotel Mode':'Switch to Customer Mode';
    final subtitle=isDriver?'Manage rides, vehicles and earnings.':isHotel?'Add hotels, rooms and manage bookings.':'Book rides, hotels and Kashmir trips.';
    final icon=isDriver?Icons.drive_eta_rounded:isHotel?Icons.hotel_rounded:Icons.person_rounded;
    return Container(decoration:BoxDecoration(gradient:LinearGradient(colors:isHotel?const[Color(0xFF24362F),Color(0xFF5E8B3D)]:isDriver?const[AppColors.primary,AppColors.secondary]:const[AppColors.secondary,Color(0xFF4F46E5)]),borderRadius:BorderRadius.circular(20)),child:Material(color:Colors.transparent,child:InkWell(borderRadius:BorderRadius.circular(20),onTap:()=>_switch(context,c),child:Padding(padding:const EdgeInsets.all(15),child:Row(children:[Container(width:46,height:46,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.16),borderRadius:BorderRadius.circular(14)),child:Icon(icon,color:Colors.white,size:25)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w900)),const SizedBox(height:3),Text(subtitle,style:TextStyle(color:Colors.white.withValues(alpha:.78),fontSize:10,height:1.3))])),const Icon(Icons.arrow_forward_rounded,color:Colors.white,size:19)])))));
  }
  Future<void> _switch(BuildContext context,AppController c)async{if(targetMode==UserMode.driver&&!c.driverApproved){await showDialog<void>(context:context,builder:(x)=>AlertDialog(title:const Text('Driver approval required'),content:const Text('Complete driver verification before using Driver Mode.'),actions:[TextButton(onPressed:()=>Navigator.pop(x),child:const Text('Close'))]));return;}await c.switchMode(targetMode);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Mode changed.')));}
}
