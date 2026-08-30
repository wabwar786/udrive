import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/home_service.dart';
import '../../core/widgets/service_illustration.dart';
import '../../models/auth_models.dart';
import 'otp_screen.dart';

/// Sign-in.
///
/// The vehicle artwork fills the screen behind a dark scrim, and the form rides
/// on a raised sheet at the bottom. Content scrolls over the artwork rather than
/// sitting in a boxed hero, so the screen reads as one piece.
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
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BackdropArtwork(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(
                    children: [
                      const UDriveWordmark(compact: true),
                      const Spacer(),
                      const _LanguageToggle(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          urdu
                              ? 'کشمیر کا محفوظ اور آسان سفر'
                              : 'Your safer way to\nexplore Kashmir',
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1.18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.8,
                            color: AppText.primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          urdu
                              ? 'ایک ہی اکاؤنٹ سے کسٹمر اور منظور شدہ ڈرائیور موڈ استعمال کریں۔'
                              : 'One secure account for Customer mode and approved '
                                  'Driver mode.',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: AppText.secondary,
                          ),
                        ),
                        const SizedBox(height: 26),
                        _FormSheet(
                          formKey: _formKey,
                          name: _name,
                          phone: _phone,
                          urdu: urdu,
                          error: _error,
                          accepted: _accepted,
                          busy: controller.authBusy,
                          onAcceptedChanged: (value) =>
                              setState(() => _accepted = value),
                          onContinue: _continue,
                          onDemo: _demoLogin,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        builder: (_) =>
            OtpScreen(phone: _phone.text.trim(), fullName: _name.text.trim()),
      ));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not connect to UDrive. Please try again.');
      }
    }
  }

  Future<void> _demoLogin() async {
    setState(() => _error = null);
    try {
      await AppControllerScope.of(context).login();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Demo login failed. Check the API deployment.');
      }
    }
  }
}

/// Full-screen vehicle artwork behind a scrim.
///
/// Uses the same vector illustration the home hero does, so the car is sharp at
/// any screen size and needs no bundled photograph.
class _BackdropArtwork extends StatelessWidget {
  const _BackdropArtwork();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF14301F), AppColors.background],
            ),
          ),
        ),
        Positioned(
          top: -size.height * .04,
          right: -size.width * .30,
          child: IgnorePointer(
            child: Container(
              width: size.width * .95,
              height: size.width * .95,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: .10),
              ),
            ),
          ),
        ),
        // The car sits in the upper third, large and bleeding off the right
        // edge, then the scrim below keeps the form legible over it.
        Positioned(
          top: size.height * .10,
          left: -size.width * .12,
          right: -size.width * .12,
          height: size.height * .30,
          child: const IgnorePointer(
            child: Opacity(
              opacity: .85,
              child: ServiceIllustration(service: HomeService.car),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .34, .52, 1],
                  colors: [
                    Color(0x660B1417),
                    Color(0x330B1417),
                    Color(0xE60B1417),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormSheet extends StatelessWidget {
  const _FormSheet({
    required this.formKey,
    required this.name,
    required this.phone,
    required this.urdu,
    required this.error,
    required this.accepted,
    required this.busy,
    required this.onAcceptedChanged,
    required this.onContinue,
    required this.onDemo,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController phone;
  final bool urdu;
  final String? error;
  final bool accepted;
  final bool busy;
  final ValueChanged<bool> onAcceptedChanged;
  final VoidCallback onContinue;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.panel),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.panel,
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              urdu ? 'اپنا موبائل نمبر درج کریں' : 'Continue with mobile',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: urdu
                    ? 'پورا نام (نئے صارف کے لیے)'
                    : 'Full name (for a new account)',
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => value != null && value.length > 160
                  ? 'Maximum 160 characters.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
              ],
              decoration: InputDecoration(
                labelText: urdu ? 'پاکستانی موبائل نمبر' : 'Mobile number',
                hintText: '03001234567',
                prefixIcon: const Icon(Icons.phone_iphone_rounded),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 10 ? context.tr('invalidPhone') : null;
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTint.danger,
                  borderRadius: AppRadii.all(AppRadii.field),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: () => onAcceptedChanged(!accepted),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: accepted,
                        onChanged: (value) =>
                            onAcceptedChanged(value ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        '${context.tr('terms')} · ${context.tr('privacy')}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppText.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: !accepted || busy ? null : onContinue,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppText.onBrand),
                    )
                  : const Icon(Icons.sms_outlined),
              label: Text(urdu ? 'او ٹی پی بھیجیں' : 'Send verification code'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : onDemo,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(
                  urdu ? 'منظور شدہ ڈرائیور ڈیمو' : 'Use approved driver demo'),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 15, color: AppText.disabled),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    urdu
                        ? 'ٹیسٹنگ او ٹی پی 1234 ہے۔'
                        : 'Testing code is 1234. A live SMS provider replaces '
                            'it before public launch.',
                    style: const TextStyle(
                      color: AppText.disabled,
                      fontSize: 11.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// EN / اردو switch, styled to match the pill used on Home.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final english = controller.locale.languageCode != 'ur';

    Widget chip(String label, bool active, String code) => GestureDetector(
          onTap: () => controller.setLanguage(code),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active ? AppColors.secondary : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: active ? AppText.onBrand : AppText.secondary,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('EN', english, 'en'),
          const SizedBox(width: 3),
          chip('اردو', !english, 'ur'),
        ],
      ),
    );
  }
}
