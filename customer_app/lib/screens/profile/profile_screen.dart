import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = AppLanguageScope.of(context);
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      Text(S.of(context, 'profile'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)), const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
        const CircleAvatar(radius: 34, backgroundColor: AppColors.primary, child: Text('SQ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
        const SizedBox(width: 14),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Shahzad Ahmad Qureshi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('+92 300 1234567', style: TextStyle(color: AppColors.muted))])),
        IconButton(onPressed: () {}, icon: const Icon(Icons.edit_outlined)),
      ]))),
      const SizedBox(height: 14),
      _tile(context, Icons.account_balance_wallet_outlined, S.of(context, 'wallet'), 'PKR 2,500'),
      _tile(context, Icons.bookmark_border_rounded, S.of(context, 'savedPlaces'), 'Home, Office'),
      _tile(context, Icons.health_and_safety_outlined, S.of(context, 'safety'), '2 trusted contacts'),
      _tile(context, Icons.support_agent_rounded, S.of(context, 'support'), 'Open help centre'),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.of(context, 'language'), style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 12),
        SegmentedButton<String>(segments: [ButtonSegment(value: 'en', label: Text(S.of(context, 'english'))), ButtonSegment(value: 'ur', label: Text(S.of(context, 'urdu')))], selected: {lang.locale.languageCode}, onSelectionChanged: (v) => lang.setLanguage(v.first)),
      ]))),
    ]));
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(leading: Icon(icon, color: AppColors.primary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right))));
}
