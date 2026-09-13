import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/powered_by.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../models/auth_models.dart';
import 'otp_screen.dart';

/// Sign-in.
///
/// Logo centred, form directly beneath it, drawn shapes behind. One thing to
/// look at, then one thing to do.
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
                // The mark, small, top left. Nothing else up here.
                //
                // The language switch was the only thing in this row, and it is
                // a setting somebody changes once — on the first screen of the
                // app it was the most prominent control on a page whose whole
                // job is to collect a name and a number.
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 16, 0),
                  child: Row(
                    children: [
                      UDriveMark(size: 44),
                      Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left-aligned, and no second logo.
                        //
                        // The mark was repeated here at 72px under the one in
                        // the header — two logos on one screen, neither of
                        // which then reads as the mark. This is a form, so it
                        // opens with its question rather than with branding.
                        const SizedBox(height: 26),
                        Text(
                          urdu ? 'خوش آمدید' : 'Welcome',
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.8,
                            color: AppText.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          urdu
                              ? 'کشمیر کا محفوظ اور آسان سفر'
                              : 'Your safer way to explore Kashmir',
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
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
                        const PoweredByWabwar(),
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
/// The background behind the sign-in form.
///
/// No photograph. The car illustration used to sit in the upper third and the
/// form sheet rode over the top of it, so the vehicle was cut in half by a
/// panel edge on almost every screen size — the artwork and the form were each
/// laid out as though the other were not there.
///
/// What replaces it is drawn rather than placed: a vertical wash and two soft
/// brand circles, all of it out at the edges. Shapes have no fixed proportions
/// to protect, so nothing can be cropped through the middle no matter how tall
/// the phone or how far the keyboard pushes the form up.
/// Plain white behind the sign-in form.
///
/// This painted a dark green gradient with soft shapes over it — the app's old
/// palette, on the first screen anyone sees. A person's first impression of the
/// app was a colour scheme the rest of it no longer uses.
///
/// White, and nothing else. The green belongs on the button they are about to
/// press, not behind the fields they are about to fill.
class _BackdropArtwork extends StatelessWidget {
  const _BackdropArtwork();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: AppColors.background, child: SizedBox.expand());
}

class _Glow extends StatelessWidget {
  const _Glow({required this.diameter, required this.opacity});

  final double diameter;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.secondary.withValues(alpha: opacity),
        ),
      );
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
                  ? SizedBox(
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
