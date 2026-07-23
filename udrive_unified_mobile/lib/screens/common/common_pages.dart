import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: notifications
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: PremiumCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 46, height: 46, decoration: BoxDecoration(color: item.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(item.icon, color: item.color)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900))), if (item.unread) const Icon(Icons.circle, size: 8, color: AppColors.primary)]), const SizedBox(height: 4), Text(item.body, style: const TextStyle(color: AppColors.muted, height: 1.35, fontSize: 12)), const SizedBox(height: 6), Text(item.time, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700))])),
                      ],
                    ),
                  ),
                ))
            .toList(),
      );
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _message = TextEditingController();
  final List<(bool, String)> _chat = [(false, 'Welcome to uDrive support. How may we help you?')];
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
      for (final item in [(Icons.notifications_rounded, 'Notification preferences'), (Icons.lock_rounded, context.tr('privacy')), (Icons.description_rounded, context.tr('terms')), (Icons.info_rounded, context.tr('about'))]) Padding(padding: const EdgeInsets.only(bottom: 9), child: PremiumCard(onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.$2} opened with dummy content.'))), child: Row(children: [Icon(item.$1, color: AppColors.primaryDark), const SizedBox(width: 13), Expanded(child: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w900))), const Icon(Icons.chevron_right_rounded)]))),
      const SizedBox(height: 8),
      const Center(child: Text('uDrive Mobile 3.0.0 · Demo frontend', style: TextStyle(color: AppColors.muted, fontSize: 11))),
    ]);
  }
}
