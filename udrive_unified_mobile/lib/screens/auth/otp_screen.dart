import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../models/auth_models.dart';

/// Verification code entry.
///
/// Four separate boxes rather than one wide field with letter-spacing: the
/// customer can see exactly how many digits are expected and which one they are
/// on. A single hidden input still owns the text, so paste and SMS autofill keep
/// working.
class OtpScreen extends StatefulWidget {
  const OtpScreen({required this.phone, required this.fullName, super.key});

  final String phone;
  final String fullName;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _length = 4;
  static const _resendSeconds = 30;

  final _otp = TextEditingController();
  final _focus = FocusNode();
  Timer? _resendTimer;
  int _secondsLeft = _resendSeconds;
  String? _error;

  @override
  void initState() {
    super.initState();
    _otp.addListener(() => setState(() {}));
    _startResendCountdown();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otp.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _resendTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final urdu = controller.locale.languageCode == 'ur';
    final complete = _otp.text.trim().length == _length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Backdrop(),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 0, 0),
                    child: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppText.primary,
                      tooltip: 'Back',
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: UDriveMark(size: 66)),
                        const SizedBox(height: 24),
                        Text(
                          urdu
                              ? 'تصدیقی کوڈ درج کریں'
                              : 'Enter your verification code',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                            color: AppText.primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          urdu
                              ? 'کوڈ اس نمبر پر بھیجا گیا ہے'
                              : 'We sent a code to',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppText.secondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.phone,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _CodeBoxes(
                          value: _otp.text,
                          length: _length,
                          hasError: _error != null,
                          onTap: _focus.requestFocus,
                        ),
                        // Real input, kept off-screen so autofill and paste work
                        // while the boxes above do the presentation.
                        SizedBox(
                          height: 0,
                          child: Offstage(
                            child: TextField(
                              controller: _otp,
                              focusNode: _focus,
                              keyboardType: TextInputType.number,
                              maxLength: _length,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (value) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                                if (value.length == _length) _verify();
                              },
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
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
                                    _error!,
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
                        const SizedBox(height: 26),
                        FilledButton.icon(
                          onPressed: controller.authBusy || !complete
                              ? null
                              : _verify,
                          icon: controller.authBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppText.onBrand),
                                )
                              : const Icon(Icons.verified_rounded),
                          label:
                              Text(urdu ? 'تصدیق کریں' : 'Verify and continue'),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: _secondsLeft > 0
                              ? Text(
                                  urdu
                                      ? 'دوبارہ بھیجیں ${_secondsLeft}s میں'
                                      : 'Resend in ${_secondsLeft}s',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppText.disabled,
                                  ),
                                )
                              : TextButton(
                                  onPressed:
                                      controller.authBusy ? null : _resend,
                                  child: Text(urdu
                                      ? 'کوڈ دوبارہ بھیجیں'
                                      : 'Request a new code'),
                                ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.all(AppRadii.card),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 15, color: AppText.disabled),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  urdu
                                      ? 'ٹیسٹنگ کے لیے کوڈ 1234 استعمال کریں۔'
                                      : 'Use code 1234 during testing.',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                    color: AppText.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
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

  Future<void> _verify() async {
    if (_otp.text.trim().length != _length) {
      setState(() => _error = 'Enter the four-digit code.');
      return;
    }
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    try {
      await AppControllerScope.of(context).verifyOtp(
        phoneNumber: widget.phone,
        code: _otp.text.trim(),
        fullName: widget.fullName,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Verification failed. Please try again.');
      }
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await AppControllerScope.of(context).requestOtp(widget.phone);
      if (!mounted) return;
      _startResendCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code was requested.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }
}

/// One box per digit. The box being typed into is outlined in brand green.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.value,
    required this.length,
    required this.hasError,
    required this.onTap,
  });

  final String value;
  final int length;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (index) {
          final filled = index < value.length;
          final active = index == value.length;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 60,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasError
                      ? AppColors.danger
                      : active
                          ? AppColors.secondary
                          : AppColors.border,
                  width: active || hasError ? 1.8 : 1,
                ),
              ),
              child: Text(
                filled ? value[index] : '',
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: AppText.primary,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

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
          top: -size.width * .35,
          left: -size.width * .25,
          child: IgnorePointer(
            child: Container(
              width: size.width * .9,
              height: size.width * .9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: .09),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
