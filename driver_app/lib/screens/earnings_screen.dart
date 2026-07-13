import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/app_theme.dart';
class EarningsScreen extends StatelessWidget { const EarningsScreen({super.key}); @override Widget build(BuildContext context)=>SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
  Text(DS.of(context,'earnings'),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),const SizedBox(height:18),
  Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[AppColors.primary,AppColors.secondary]),borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Available balance',style:TextStyle(color:Colors.white70)),SizedBox(height:8),Text('PKR 42,850',style:TextStyle(color:Colors.white,fontSize:32,fontWeight:FontWeight.w900)),SizedBox(height:18),Row(children:[Expanded(child:Text('This week\nPKR 18,200',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700))),Expanded(child:Text('Commission\nPKR 2,730',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700)))])])),
  const SizedBox(height:18),FilledButton.icon(onPressed:(){},icon:const Icon(Icons.account_balance),label:const Text('Request payout')),const SizedBox(height:20),
  const Text('Recent transactions',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:10),
  ...['Neelum Valley ride  +5,200','UDrive commission  -780','Rawalakot package  +36,000','Payout to bank  -20,000'].map((e)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.payments_outlined)),title:Text(e),subtitle:const Text('13 Jul 2026'),trailing:const Icon(Icons.chevron_right)))),
])); }
