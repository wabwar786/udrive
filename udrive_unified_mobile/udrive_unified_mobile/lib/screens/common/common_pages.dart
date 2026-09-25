import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/communication/communication_repository.dart';
import '../../models/communication_models.dart';
import '../../core/config/app_config.dart';
import 'delete_account_screen.dart';
import 'legal_screen.dart';

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
 @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[Row(children:[Expanded(child:Text('${page.unreadCount} unread',style:const TextStyle(fontWeight:FontWeight.w800,color:AppColors.muted))),if(page.unreadCount>0)TextButton(onPressed:()async{await repo.markAllRead();await load();},child:const Text('Mark all read'))]),if(error!=null)Card(color:Colors.red.shade50,child:Padding(padding:const EdgeInsets.all(12),child:Text(error!))),if(page.items.isEmpty)const Padding(padding:EdgeInsets.only(top:80),child:Column(children:[Icon(Icons.notifications_none_rounded,size:56,color:AppColors.muted),SizedBox(height:12),Text('No notifications yet',style:TextStyle(fontWeight:FontWeight.w900,fontSize:17)),SizedBox(height:5),Text('Trip, offer and account updates will appear here.',style:TextStyle(color:AppColors.muted))])),...page.items.map((item)=>Padding(padding:const EdgeInsets.only(bottom:10),child:PremiumCard(onTap:()async{if(!item.isRead){await repo.markRead(item.id);await load();}},color:item.isRead?Colors.white:AppColors.surface,child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(width:43,height:43,decoration:BoxDecoration(color:AppColors.primary.withValues(alpha:.11),borderRadius:BorderRadius.circular(13)),child:Icon(icon(item.type),color:AppColors.primaryDark,size:21)),const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(item.title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:13.5))),if(!item.isRead)const Icon(Icons.circle,size:8,color:AppColors.primary)]),const SizedBox(height:4),Text(item.body,style:const TextStyle(color:AppColors.muted,height:1.35,fontSize:12)),const SizedBox(height:6),Text(time(item.createdAt),style:const TextStyle(color:AppColors.muted,fontSize:10,fontWeight:FontWeight.w700))]))]))))]));
}

// SupportScreen was here. It told the person on screen that "Dummy chat,
// ticket and emergency help options are active", and answered anything
// they typed with "a demo support ticket has been created". Support now
// opens FeedbackCenterScreen, which files a real case.

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
      const SizedBox(height: 9),
      // Privacy and Terms open inside the app, from the copy bundled with it,
      // so they work with no connection — which is the state somebody is most
      // likely to be in when they suddenly want to know what we do with their
      // CNIC. The same documents are served by the API at /privacy and /terms,
      // which is the URL on the Play listing, and the reader has an "open
      // online" button for that.
      for (final item in [
        (Icons.lock_rounded, context.tr('privacy'), 'privacy-policy'),
        (Icons.description_rounded, context.tr('terms'), 'terms'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: PremiumCard(
            onTap: () => LegalScreen.open(context, item.$3),
            child: Row(children: [
              Icon(item.$1, color: AppColors.primaryDark),
              const SizedBox(width: 13),
              Expanded(child: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w900))),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: PremiumCard(
          onTap: () => showAboutDialog(
            context: context,
            applicationName: AppConfig.appName,
            applicationVersion: AppConfig.buildLabel,
            applicationLegalese: '© Tech Geni Ltd.',
          ),
          child: Row(children: [
            const Icon(Icons.info_rounded, color: AppColors.primaryDark),
            const SizedBox(width: 13),
            Expanded(child: Text(context.tr('about'), style: const TextStyle(fontWeight: FontWeight.w900))),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      const SectionHeader(title: 'Account'),
      const SizedBox(height: 10),
      PremiumCard(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
        ),
        child: const Row(children: [
          Icon(Icons.delete_forever_rounded, color: AppColors.danger),
          SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delete account', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.danger)),
              SizedBox(height: 3),
              Text('Permanently remove your account and personal data',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded),
        ]),
      ),
      const SizedBox(height: 14),
      Center(
        child: Text('${AppConfig.appName} · ${AppConfig.buildLabel}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      ),
    ]);
  }
}
