import 'package:flutter/material.dart';
import '../driver/driver_requests_screen.dart';
import 'driver_operations_screen.dart';
class DriverOperationsHubScreen extends StatelessWidget{const DriverOperationsHubScreen({super.key});@override Widget build(BuildContext context)=>DefaultTabController(length:2,child:Scaffold(appBar:AppBar(toolbarHeight:0,bottom:const TabBar(tabs:[Tab(text:'Dispatch'),Tab(text:'Marketplace')])),body:const TabBarView(children:[DriverOperationsScreen(),DriverRequestsScreen()])));}
