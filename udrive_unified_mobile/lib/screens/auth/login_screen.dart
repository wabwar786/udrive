import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../common/legal_screen.dart';
import 'otp_screen.dart';

/// Whether the one-tap demo sign-in button shows.
///
/// Debug builds and the web build keep it; a release Android build — the one
/// that goes to Google Play — never does. It used to guard a second thing, a
/// line of text naming the fixed code, but no screen names a code any more:
/// the OTP screen's copy of that hint had no guard at all and shipped.
const bool _showTestingHelpers = kIsWeb || kDebugMode;

/// Sign-in. Design system v2, screen G-02.
///
/// White page, the mark small in the top-left corner, the question at the left
/// margin, and one grey sheet holding the two fields and the button. Nothing
/// here changed but the presentation: the same two controllers, the same
/// validators, the same `requestOtp` call and the same push to [OtpScreen].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  // Empty, deliberately. This used to open with '03001234567' already typed in.
  // It is not a hint — it is a real value in the field, so the first thing a
  // new user could do is tap "Send verification code" and post an OTP request
  // for a number that is not theirs. The hint text on the field is what tells
  // them the expected format. The design PNG shows that number in the box; on
  // data, the code wins.
  final _phone = TextEditingController();
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
      body: SafeArea(
        child: Column(
          children: [
            // The mark, small, top left. Nothing else up here.
            //
            // The language switch was the only thing in this row, and it is a
            // setting somebody changes once — on the first screen of the app it
            // was the most prominent control on a page whose whole job is to
            // collect a name and a number.
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSizes.sidePadding, 14, 16, 0),
              child: Row(
                children: [
                  UDriveMark(size: 40),
                  Spacer(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 8, AppSizes.sidePadding, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left-aligned, and no second logo.
                    //
                    // The mark was repeated here at 72px under the one in the
                    // header — two logos on one screen, neither of which then
                    // reads as the mark. This is a form, so it opens with its
                    // question rather than with branding.
                    const SizedBox(height: 26),
                    Text(
                      urdu ? 'خوش آمدید' : 'Welcome',
                      style: AppType.h1.copyWith(
                        fontSize: 32,
                        letterSpacing: -0.8,
                        height: 1.15,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      urdu
                          ? 'کشمیر کا محفوظ اور آسان سفر'
                          : 'Your safer way to explore Kashmir',
                      style: AppType.body2.copyWith(
                        height: 1.5,
                        color: AppText.secondary,
                      ),
                    ),
                    const SizedBox(height: 24),
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

/// The grey sheet holding the form.
///
/// `.card.tint`: the surface grey, no border and no shadow. The separation from
/// the page comes from the white fields inside it, which is the inversion v2
/// makes everywhere — grey marks what is recessed, not what is raised.
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
    return UdCard(
      tone: UdCardTone.tint,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              urdu ? 'اپنا موبائل نمبر درج کریں' : 'Continue with mobile',
              style: AppType.h3.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 18),
            UdTextField(
              controller: name,
              label: urdu ? 'پورا نام' : 'Full name',
              labelSuffix: urdu ? '(نئے صارف کے لیے)' : '(for a new account)',
              hint: urdu ? 'علی رضا' : 'Ali Raza',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  value != null && value.length > 160
                      ? 'Maximum 160 characters.'
                      : null,
            ),
            const SizedBox(height: 16),
            UdTextField(
              controller: phone,
              label: urdu ? 'پاکستانی موبائل نمبر' : 'Mobile number',
              hint: '03001234567',
              icon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
              ],
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 10 ? context.tr('invalidPhone') : null;
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 14),
              UdBanner(
                tone: UdTone.err,
                icon: Icons.error_outline_rounded,
                text: error!,
              ),
            ],
            const SizedBox(height: 6),
            UdCheckboxRow(
              value: accepted,
              onChanged: onAcceptedChanged,
              semanticLabel: urdu
                  ? 'شرائط و ضوابط سے اتفاق'
                  : 'Agree to the terms and the privacy policy',
              // Both halves open the document. This is the moment the customer
              // is agreeing to them, so it is the one place they must be
              // reachable — it used to be plain text you could tap all day
              // without anything happening.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LegalLink(label: context.tr('terms'), document: 'terms'),
                  Text(
                    '  ·  ',
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                  _LegalLink(
                    label: context.tr('privacy'),
                    document: 'privacy-policy',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            UdButton.primary(
              label: urdu ? 'او ٹی پی بھیجیں' : 'Send verification code',
              icon: Icons.sms_outlined,
              busy: busy,
              onPressed: accepted ? onContinue : null,
            ),
            // The demo account and the fixed testing code exist for our own
            // browser testing. A published Android build must not offer either:
            // a reviewer sees a "demo" door into the product, and the code is a
            // way into somebody else's account while the old provider is on.
            if (_showTestingHelpers) ...[
              const SizedBox(height: 10),
              UdButton.outline(
                label:
                    urdu ? 'منظور شدہ ڈرائیور ڈیمو' : 'Use approved driver demo',
                icon: Icons.verified_user_outlined,
                onPressed: busy ? null : onDemo,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 17, color: AppText.caption),
                const SizedBox(width: 9),
                // One line in every build. The test-build variant used to name
                // the code, which meant a screen recording, a screenshot in a
                // bug report or a shared web build gave it away — and the code
                // it named worked on every phone number on the platform, not
                // just a test one.
                //
                // 13px, up from 11.5. Nothing in v2 goes below 12.5, and this
                // is the line that tells somebody which app to go and look in.
                Expanded(
                  child: Text(
                    urdu
                        ? 'کوڈ آپ کے واٹس ایپ نمبر پر بھیجا جائے گا۔'
                        : 'A 4-digit code is sent to this number on WhatsApp.',
                    style: AppType.caption.copyWith(
                      height: 1.4,
                      color: AppText.caption,
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

/// One tappable legal link on the consent row.
///
/// Its own widget so the tap target is the word itself rather than the whole
/// row: tapping the row is how you toggle the checkbox, and a link that steals
/// that tap would stop people agreeing.
class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.document});

  final String label;
  final String document;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => LegalScreen.open(context, document),
      child: Text(
        label,
        style: AppType.caption.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.brandInk,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.brandInk,
        ),
      ),
    );
  }
}
