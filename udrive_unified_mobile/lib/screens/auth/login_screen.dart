import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController(text: '03001234567');
  bool _accepted = true;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 46),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const UDriveWordmark(compact: true),
                          const Spacer(),
                          _LanguageButton(code: 'en', label: 'EN'),
                          const SizedBox(width: 6),
                          _LanguageButton(code: 'ur', label: 'اردو'),
                        ],
                      ),
                      const SizedBox(height: 46),
                      Container(
                        height: 205,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          gradient: const LinearGradient(colors: [Color(0xFF0B4D3E), AppColors.primary]),
                        ),
                        child: Stack(
                          children: [
                            const Positioned(right: 22, top: 26, child: Icon(Icons.landscape_rounded, color: Colors.white24, size: 145)),
                            Positioned(
                              left: 24,
                              right: 24,
                              bottom: 24,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const UDriveMark(size: 62),
                                  const SizedBox(height: 14),
                                  Text(context.tr('tagline'), style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(context.tr('welcomeBack'), style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: -.7, color: AppColors.navy)),
                      const SizedBox(height: 8),
                      Text(context.tr('loginSubtitle'), style: const TextStyle(height: 1.45, color: AppColors.muted, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(labelText: context.tr('phone'), prefixIcon: const Icon(Icons.phone_iphone_rounded), prefixText: '+92  '),
                        validator: (value) => (value ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? context.tr('invalidPhone') : null,
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _accepted,
                        onChanged: (value) => setState(() => _accepted = value ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('${context.tr('terms')} · ${context.tr('privacy')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _accepted ? _continue : null,
                        child: Text(context.tr('continue')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => AppControllerScope.of(context).login(),
                        icon: const Icon(Icons.person_rounded),
                        label: Text(context.tr('demoLogin')),
                      ),
                      const SizedBox(height: 30),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.shield_outlined, size: 17, color: AppColors.muted),
                        const SizedBox(width: 7),
                        Text(context.tr('dummyReady'), style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtpScreen(phone: _phone.text)));
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.code, required this.label});
  final String code;
  final String label;
  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final selected = controller.locale.languageCode == code;
    return InkWell(
      onTap: () => controller.setLanguage(code),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: selected ? AppColors.primary.withValues(alpha: .12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(color: selected ? AppColors.primaryDark : AppColors.muted, fontSize: 12, fontWeight: FontWeight.w900)),
      ),
    );
  }
}
