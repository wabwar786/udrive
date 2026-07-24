import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../models/auth_models.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '03001234567');
  bool _accepted = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final urdu = controller.locale.languageCode == 'ur';
    return Scaffold(
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
                    const SizedBox(height: 34),
                    Container(
                      height: 190,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: const LinearGradient(colors: [Color(0xFF063F32), AppColors.primary]),
                      ),
                      child: Stack(
                        children: [
                          const Positioned(right: 18, top: 18, child: Icon(Icons.landscape_rounded, color: Colors.white24, size: 150)),
                          Positioned(
                            left: 24,
                            right: 24,
                            bottom: 22,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const UDriveMark(size: 58),
                                const SizedBox(height: 12),
                                Text(
                                  urdu ? 'کشمیر کا محفوظ اور آسان سفر' : 'Your safer way to explore Kashmir',
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      urdu ? 'اپنا موبائل نمبر درج کریں' : 'Continue with your mobile number',
                      style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.6, color: AppColors.navy),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      urdu
                          ? 'ایک ہی اکاؤنٹ سے کسٹمر اور منظور شدہ ڈرائیور موڈ استعمال کریں۔'
                          : 'Use one secure account for Customer mode and approved Driver mode.',
                      style: const TextStyle(height: 1.45, color: AppColors.muted, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: urdu ? 'پورا نام (نئے صارف کے لیے)' : 'Full name (for a new account)',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) => value != null && value.length > 160 ? 'Maximum 160 characters.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: urdu ? 'پاکستانی موبائل نمبر' : 'Pakistan mobile number',
                        hintText: '03001234567',
                        prefixIcon: const Icon(Icons.phone_iphone_rounded),
                      ),
                      validator: (value) {
                        final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                        return digits.length < 10 ? context.tr('invalidPhone') : null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: _accepted,
                      onChanged: (value) => setState(() => _accepted = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('${context.tr('terms')} · ${context.tr('privacy')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: !_accepted || controller.authBusy ? null : _continue,
                      icon: controller.authBusy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sms_outlined),
                      label: Text(urdu ? 'او ٹی پی بھیجیں' : 'Send verification code'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: controller.authBusy ? null : _demoLogin,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(urdu ? 'منظور شدہ ڈرائیور ڈیمو' : 'Use approved driver demo'),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFEAF7F1), borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline_rounded, color: AppColors.primaryDark),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              urdu
                                  ? 'ٹیسٹنگ او ٹی پی 1234 ہے۔ اصل ایس ایم ایس فراہم کنندہ اگلے مرحلے میں جوڑا جائے گا۔'
                                  : 'Testing OTP is 1234. A live SMS provider will replace it before public launch.',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await AppControllerScope.of(context).requestOtp(_phone.text.trim());
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpScreen(phone: _phone.text.trim(), fullName: _name.text.trim()),
      ));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect to uDrive API. Please try again.');
    }
  }

  Future<void> _demoLogin() async {
    setState(() => _error = null);
    try {
      await AppControllerScope.of(context).login();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Demo login failed. Check the API deployment.');
    }
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
