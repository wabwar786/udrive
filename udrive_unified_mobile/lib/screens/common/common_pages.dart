import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/communication/communication_repository.dart';
import '../../models/communication_models.dart';
import 'offline_maps_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState()=>_NotificationsScreenState();
}
class _NotificationsScreenState extends State<NotificationsScreen>{
 late final CommunicationRepository repo;bool loading=true;String? error;NotificationPage page=const NotificationPage([],0);
 @override void initState(){super.initState();repo=CommunicationRepository(ApiClient(SessionStore()));load();}
 Future<void> load()async{setState((){loading=true;error=null;});try{final x=await repo.notifications();if(mounted)setState(()=>page=x);}catch(e){if(mounted)setState(()=>error='Notifications could not be loaded. Pull down to retry.');}finally{if(mounted)setState(()=>loading=false);}}
 IconData icon(String type){final t=type.toLowerCase();if(t.contains('message'))return Icons.chat_bubble_rounded;if(t.contains('offer'))return Icons.local_offer_rounded;if(t.contains('driver'))return Icons.directions_car_rounded;if(t.contains('complaint')||t.contains('dispute'))return Icons.support_agent_rounded;if(t.contains('payment')||t.contains('payout'))return Icons.account_balance_wallet_rounded;return Icons.notifications_rounded;}
 String time(DateTime x){final d=DateTime.now().difference(x.toLocal());if(d.inMinutes<1)return 'Now';if(d.inHours<1)return '${d.inMinutes} min ago';if(d.inDays<1)return '${d.inHours} hr ago';return '${d.inDays} day${d.inDays==1?'':'s'} ago';}
 @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[Row(children:[Expanded(child:Text('${page.unreadCount} unread',style:const TextStyle(fontWeight:FontWeight.w800,color:AppColors.muted))),if(page.unreadCount>0)TextButton(onPressed:()async{await repo.markAllRead();await load();},child:const Text('Mark all read'))]),if(error!=null)Card(color:Colors.red.shade50,child:Padding(padding:const EdgeInsets.all(12),child:Text(error!))),if(page.items.isEmpty)const Padding(padding:EdgeInsets.only(top:80),child:Column(children:[Icon(Icons.notifications_none_rounded,size:56,color:AppColors.muted),SizedBox(height:12),Text('No notifications yet',style:TextStyle(fontWeight:FontWeight.w900,fontSize:17)),SizedBox(height:5),Text('Trip, offer and account updates will appear here.',style:TextStyle(color:AppColors.muted))])),...page.items.map((item)=>Padding(padding:const EdgeInsets.only(bottom:10),child:PremiumCard(onTap:()async{if(!item.isRead){await repo.markRead(item.id);await load();}},color:item.isRead?Colors.white:const Color(0xFFF1FAF6),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(width:43,height:43,decoration:BoxDecoration(color:AppColors.primary.withValues(alpha:.11),borderRadius:BorderRadius.circular(13)),child:Icon(icon(item.type),color:AppColors.primaryDark,size:21)),const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(item.title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:13.5))),if(!item.isRead)const Icon(Icons.circle,size:8,color:AppColors.primary)]),const SizedBox(height:4),Text(item.body,style:const TextStyle(color:AppColors.muted,height:1.35,fontSize:12)),const SizedBox(height:6),Text(time(item.createdAt),style:const TextStyle(color:AppColors.muted,fontSize:10,fontWeight:FontWeight.w700))]))]))))]));
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _message = TextEditingController();
  final List<(bool, String)> _chat = [(false, 'Welcome to Udrive support. How may we help you?')];
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(18), children: [
          PremiumCard(color: const Color(0xFFF1FAF6), child: const Row(children: [Icon(Icons.support_agent_rounded, color: AppColors.primaryDark, size: 34), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('24/7 tourism support', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('Dummy chat, ticket and emergency help options are active.', style: TextStyle(color: AppColors.muted, fontSize: 12))]))])),
          const SizedBox(height: 16),
          ..._chat.map((m) => Align(alignment: m.$1 ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76), decoration: BoxDecoration(color: m.$1 ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(17), border: m.$1 ? null : Border.all(color: AppColors.border)), child: Text(m.$2, style: TextStyle(color: m.$1 ? Colors.white : AppColors.navy, fontWeight: FontWeight.w600))))),
        ])),
        SafeArea(child: Container(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), color: Colors.white, child: Row(children: [IconButton.filledTonal(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dummy attachment selected.'))), icon: const Icon(Icons.attach_file_rounded)), const SizedBox(width: 8), Expanded(child: TextField(controller: _message, decoration: const InputDecoration(hintText: 'Write a message…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))), const SizedBox(width: 8), IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded))]))),
      ]);
  void _send() {
    final value = _message.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _chat.add((true, value));
      _chat.add((false, 'Thanks. A demo support ticket has been created.'));
      _message.clear();
    });
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return ListView(padding: const EdgeInsets.all(18), children: [
      SectionHeader(title: context.tr('language')),
      const SizedBox(height: 10),
      PremiumCard(child: Column(children: [RadioListTile<String>(value: 'en', groupValue: controller.locale.languageCode, onChanged: (value) => controller.setLanguage(value!), title: Text(context.tr('english'), style: const TextStyle(fontWeight: FontWeight.w800))), RadioListTile<String>(value: 'ur', groupValue: controller.locale.languageCode, onChanged: (value) => controller.setLanguage(value!), title: Text(context.tr('urdu'), style: const TextStyle(fontWeight: FontWeight.w800)))])),
      const SizedBox(height: 18),
      SectionHeader(title: context.tr('settings')),
      const SizedBox(height: 10),
      PremiumCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineMapsScreen())), child: const Row(children: [Icon(Icons.map_outlined, color: AppColors.primaryDark), SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Offline Maps', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 3), Text('Download, update and manage route maps', style: TextStyle(color: AppColors.muted, fontSize: 11))])), Icon(Icons.chevron_right_rounded)])),
      const SizedBox(height: 9),
      for (final item in [(Icons.notifications_rounded, 'Notification preferences'), (Icons.lock_rounded, context.tr('privacy')), (Icons.description_rounded, context.tr('terms')), (Icons.info_rounded, context.tr('about'))]) Padding(padding: const EdgeInsets.only(bottom: 9), child: PremiumCard(onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.$2} opened with dummy content.'))), child: Row(children: [Icon(item.$1, color: AppColors.primaryDark), const SizedBox(width: 13), Expanded(child: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w900))), const Icon(Icons.chevron_right_rounded)]))),
      const SizedBox(height: 8),
      const Center(child: Text('Udrive Mobile 4.0.0 · Tourism demo frontend', style: TextStyle(color: AppColors.muted, fontSize: 11))),
    ]);
  }
}
