import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({required this.phone, super.key});
  final String phone;
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: UDriveMark(size: 82)),
                const SizedBox(height: 28),
                Text(context.tr('otpTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.navy)),
                const SizedBox(height: 8),
                Text('${context.tr('otpSubtitle')}\n+92 ${widget.phone}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.5)),
                const SizedBox(height: 30),
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  style: const TextStyle(fontSize: 31, letterSpacing: 18, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(counterText: '', errorText: _error, hintText: '••••'),
                ),
                const SizedBox(height: 18),
                FilledButton(onPressed: _verify, child: Text(context.tr('verify'))),
              ],
            ),
          ),
        ),
      );

  Future<void> _verify() async {
    if (_otp.text.trim() != '1234') {
      setState(() => _error = context.tr('invalidOtp'));
      return;
    }
    await AppControllerScope.of(context).login();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
