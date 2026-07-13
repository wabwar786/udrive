import 'package:flutter/material.dart';
import '../core/app_language.dart';
import 'earnings_screen.dart';
import 'home_screen.dart';
import 'packages_screen.dart';
import 'profile_screen.dart';
import 'requests_screen.dart';
class DriverShell extends StatefulWidget { const DriverShell({super.key}); @override State<DriverShell> createState()=>_DriverShellState(); }
class _DriverShellState extends State<DriverShell> {
  int index=0; final screens=const [DriverHomeScreen(), RequestsScreen(), PackagesScreen(), EarningsScreen(), DriverProfileScreen()];
  @override Widget build(BuildContext context)=>Scaffold(body:IndexedStack(index:index,children:screens), bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:[
    NavigationDestination(icon:const Icon(Icons.home_outlined),selectedIcon:const Icon(Icons.home),label:DS.of(context,'home')),
    NavigationDestination(icon:const Icon(Icons.notifications_active_outlined),selectedIcon:const Icon(Icons.notifications_active),label:DS.of(context,'requests')),
    NavigationDestination(icon:const Icon(Icons.card_travel_outlined),selectedIcon:const Icon(Icons.card_travel),label:DS.of(context,'packages')),
    NavigationDestination(icon:const Icon(Icons.account_balance_wallet_outlined),selectedIcon:const Icon(Icons.account_balance_wallet),label:DS.of(context,'earnings')),
    NavigationDestination(icon:const Icon(Icons.person_outline),selectedIcon:const Icon(Icons.person),label:DS.of(context,'profile')),
  ]));
}
