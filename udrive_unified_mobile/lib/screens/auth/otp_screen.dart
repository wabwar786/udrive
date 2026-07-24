import 'package:flutter/material.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../models/auth_models.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({required this.phone, required this.fullName, super.key});
  final String phone;
  final String fullName;
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otp = TextEditingController(text: '1234');
  String? _error;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final urdu = controller.locale.languageCode == 'ur';
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: UDriveMark(size: 82)),
              const SizedBox(height: 28),
              Text(
                urdu ? 'تصدیقی کوڈ درج کریں' : 'Enter your verification code',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                '${urdu ? 'کوڈ اس نمبر کے لیے بنایا گیا ہے' : 'Code requested for'}\n${widget.phone}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                style: const TextStyle(fontSize: 31, letterSpacing: 18, fontWeight: FontWeight.w900),
                decoration: InputDecoration(counterText: '', errorText: _error, hintText: '••••'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: controller.authBusy ? null : _verify,
                icon: controller.authBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_rounded),
                label: Text(urdu ? 'تصدیق کریں' : 'Verify and continue'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: controller.authBusy ? null : _resend,
                child: Text(urdu ? 'کوڈ دوبارہ بھیجیں' : 'Request a new code'),
              ),
              const SizedBox(height: 12),
              Text(
                urdu ? 'ٹیسٹنگ کے لیے کوڈ 1234 استعمال کریں۔' : 'Use code 1234 during Phase 8 testing.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verify() async {
    if (_otp.text.trim().length != 4) {
      setState(() => _error = 'Enter the four-digit code.');
      return;
    }
    setState(() => _error = null);
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
      if (mounted) setState(() => _error = 'Verification failed. Please try again.');
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await AppControllerScope.of(context).requestOtp(widget.phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A new code was requested.')));
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }
}
