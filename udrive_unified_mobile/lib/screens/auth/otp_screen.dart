import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';

/// Verification code entry. Design system v2, screen G-03.
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

class _OtpScreenState extends State<OtpScreen> with WidgetsBindingObserver {
  static const _length = 4;
  static const _resendSeconds = 30;

  final _otp = TextEditingController();
  final _focus = FocusNode();
  Timer? _resendTimer;

  /// When the Resend button becomes available again.
  ///
  /// A deadline, not a countdown. The old code decremented a counter on a
  /// one-second Timer.periodic, and both platforms suspend timers while the app
  /// is in the background — which is exactly where the customer goes to fetch
  /// the code. Ticks were lost, so a 30-second wait could still read "22s" a
  /// minute later and the button stayed locked long past its promise.
  DateTime _resendAt = DateTime.now();

  String? _error;

  int get _secondsLeft {
    final remaining = _resendAt.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _otp.addListener(() => setState(() {}));
    _startResendCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInput());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resendTimer?.cancel();
    _otp.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The whole point of this screen is that the customer leaves it to read the
    // code in WhatsApp. Coming back has to put the keyboard where it was.
    if (state == AppLifecycleState.resumed && mounted) {
      _focusInput(reacquire: true);
      setState(() {}); // Redraw the resend countdown against the real clock.
    }
  }

  /// Puts the cursor back in the hidden field and opens the keyboard.
  ///
  /// The unfocus first is the part that matters. Backgrounding the app tears
  /// down the platform keyboard but leaves FocusNode.hasFocus true, so a plain
  /// requestFocus() is a no-op: no focus change, no keyboard. That is why
  /// tapping the boxes after returning from WhatsApp did nothing at all.
  /// [reacquire] breaks the stale focus first. Only the resume path needs it;
  /// doing it on an ordinary tap makes the keyboard visibly animate down and
  /// back up for no reason.
  void _focusInput({bool reacquire = false}) {
    if (!mounted) return;
    if (reacquire && _focus.hasFocus) _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  /// Reads the clipboard on an explicit tap and submits a complete code.
  ///
  /// User-initiated only. Reading the clipboard on resume would raise the iOS
  /// paste prompt every time the customer came back, and on Android 10+ a
  /// background app cannot read it at all.
  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    // The first standalone run of exactly four digits — not the last four
    // digits of everything. Customers paste the whole message: "Your UDrive
    // code is 1234. Valid for 10 minutes." Stripping every non-digit and
    // taking the tail gives "3410", which then auto-submits and burns an
    // attempt on a code the customer can plainly see is right.
    //
    // Split rather than a lookaround regex: the runs are what we want, and
    // this cannot be got subtly wrong.
    final runs = RegExp(r'\d+')
        .allMatches(data?.text ?? '')
        .map((match) => match.group(0)!)
        .toList(growable: false);

    final exact = runs.where((run) => run.length == _length);
    final code = exact.isNotEmpty
        ? exact.first
        : (runs.isEmpty
            ? ''
            // Never longer than the field: the controller is set directly, so
            // the input formatters do not get a chance to trim it.
            : runs.first.substring(
                0,
                runs.first.length < _length ? runs.first.length : _length,
              ));

    if (code.isEmpty) {
      setState(() => _error = 'No code found in the clipboard.');
      return;
    }
    setState(() {
      _error = null;
      _otp.text = code;
      _otp.selection = TextSelection.collapsed(offset: code.length);
    });
    if (code.length == _length) await _verify();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() =>
        _resendAt = DateTime.now().add(const Duration(seconds: _resendSeconds)));
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        // Cancel rather than just returning: a timer that outlives its State
        // keeps firing for nothing.
        timer.cancel();
        return;
      }
      setState(() {});
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
      // AutofillGroup so the AutofillHints.oneTimeCode on the field below can
      // actually commit on Android — without an ancestor group the hint is
      // declared and then ignored. It only ever fires for an SMS-delivered
      // code, which UDrive does not send today, but it costs nothing and is
      // correct the day a second channel is added.
      body: AutofillGroup(
        child: Column(
          children: [
            UdTopBar(onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 4, AppSizes.sidePadding, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: UDriveMark(size: 46),
                    ),
                    const SizedBox(height: 24),

                    // Left-aligned, and large.
                    //
                    // Centred type reads as a splash screen. This is a form,
                    // and a form's question belongs at the left margin where
                    // the eye returns on every line — which matters more here
                    // than anywhere, because the next thing the person does is
                    // copy four digits across from a text message.
                    Text(
                      urdu
                          ? 'تصدیقی کوڈ درج کریں'
                          : 'Enter your\nverification code',
                      style: AppType.h1.copyWith(
                        fontSize: 30,
                        letterSpacing: -0.75,
                        height: 1.18,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      urdu
                          ? 'کوڈ اس نمبر پر بھیجا گیا ہے'
                          : 'We sent a code to',
                      style: AppType.body2.copyWith(color: AppText.secondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.phone,
                      style: AppType.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),

                    // Pushes the code boxes and the button to the bottom of the
                    // screen, under the thumb rather than under the eye. On a
                    // tall phone they sat in the middle with dead space
                    // beneath.
                    const SizedBox(height: 40),
                    _CodeBoxes(
                      value: _otp.text,
                      length: _length,
                      hasError: _error != null,
                      onTap: _focusInput,
                    ),
                    const SizedBox(height: 10),
                    // The code arrives in WhatsApp, which neither Android nor
                    // iOS will let an app read. Copy-and-paste is the whole of
                    // what the platforms allow, so it gets a button rather than
                    // a long-press on a field that is deliberately off-screen.
                    Center(
                      child: UdButton.ghost(
                        label: urdu ? 'کوڈ پیسٹ کریں' : 'Paste code',
                        icon: Icons.content_paste_rounded,
                        size: UdButtonSize.small,
                        expand: false,
                        onPressed: _pasteCode,
                      ),
                    ),
                    // Real input, kept off-screen so autofill and paste work
                    // while the boxes above do the presentation.
                    SizedBox(
                      height: 0,
                      child: Offstage(
                        child: TextField(
                          controller: _otp,
                          focusNode: _focus,
                          autofocus: true,
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
                      UdBanner(
                        tone: UdTone.err,
                        icon: Icons.error_outline_rounded,
                        text: _error!,
                      ),
                    ],
                    const SizedBox(height: 24),
                    UdButton.primary(
                      label: urdu ? 'تصدیق کریں' : 'Verify and continue',
                      icon: Icons.verified_outlined,
                      busy: controller.authBusy,
                      onPressed: complete ? _verify : null,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: _secondsLeft > 0
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              child: Text(
                                urdu
                                    ? 'دوبارہ بھیجیں ${_secondsLeft}s میں'
                                    : 'Resend in ${_secondsLeft}s',
                                style: AppType.caption
                                    .copyWith(color: AppText.caption),
                              ),
                            )
                          : UdButton.ghost(
                              label: urdu
                                  ? 'کوڈ دوبارہ بھیجیں'
                                  : 'Request a new code',
                              size: UdButtonSize.small,
                              expand: false,
                              onPressed: controller.authBusy ? null : _resend,
                            ),
                    ),
                    const SizedBox(height: 14),
                    // This panel has no build-mode guard — it renders in
                    // release Android too. It must therefore never name a code.
                    // Saying "use 1234" here handed every reader a working key
                    // to somebody else's account for as long as the Development
                    // provider was on, and it shipped to the Play Store.
                    UdBanner(
                      icon: Icons.info_outline_rounded,
                      text: urdu
                          ? 'کوڈ واٹس ایپ پر بھیجا جاتا ہے اور 5 منٹ میں ختم ہو جاتا ہے۔'
                          : 'The code is sent on WhatsApp and expires in 5 minutes.',
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
    setState(() {
      _error = null;
      // A new code goes into empty boxes. Leaving the old digits there invited
      // the customer to press Verify on a code that had just been replaced.
      _otp.clear();
    });
    try {
      await AppControllerScope.of(context).requestOtp(widget.phone);
      if (!mounted) return;
      _startResendCountdown();
      _focusInput();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code was requested.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      // A timeout or a dropped connection is not an ApiException, and the
      // field has already been cleared — without this the customer is left
      // with empty boxes, no countdown and no explanation.
      if (mounted) {
        setState(() => _error = 'Could not request a new code. Try again.');
      }
    }
  }
}

/// One box per digit, 60×68 on the surface grey.
///
/// The box being typed into takes the field's focus treatment — a 2px navy
/// border with the pale lime ring outside it — so the active box matches every
/// other focused input in the app rather than having a rule of its own.
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

          final Color border = hasError
              ? AppColors.danger
              : active
                  ? AppColors.navy
                  : AppColors.borderStrong;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 60,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.all(AppRadii.field),
                border: Border.all(
                  color: border,
                  width: active || hasError ? 2 : 1.5,
                ),
                boxShadow: active && !hasError
                    ? const [
                        BoxShadow(
                          color: AppColors.limeGlow,
                          spreadRadius: 4,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Text(
                filled ? value[index] : '',
                style: AppType.display.copyWith(
                  fontSize: 27,
                  letterSpacing: 0,
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
