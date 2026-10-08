import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:udrive_mobile/core/state/app_controller.dart';
import 'package:udrive_mobile/core/widgets/ud_input.dart';
import 'package:udrive_mobile/main.dart' as app;

import 'support/reporter.dart';

/// Customer city ride, on the staging API, watched live in Admin → Live testing.
///
/// Run (GitHub Actions does this on an emulator — see .github/workflows/app-tests.yml):
///   flutter test integration_test/customer_flow_test.dart
///
/// Signs in with the Google Play reviewer number and code. It searches and
/// reads a fare but never books a ride.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The number and code typed into the Run workflow form; empty = the ones
  // the app carries (AppController.demoPhoneNumber / demoReviewerCode).
  const phoneDefine = String.fromEnvironment('TEST_PHONE');
  const otpDefine = String.fromEnvironment('TEST_OTP');
  final phone = phoneDefine.trim().isEmpty ? AppController.demoPhoneNumber : phoneDefine.trim();
  final otp = otpDefine.trim().isEmpty ? AppController.demoReviewerCode : otpDefine.trim();
  const place = String.fromEnvironment('TEST_DESTINATION', defaultValue: 'Secretariat');

  testWidgets('City ride (app)', (tester) async {
    final originalOnError = FlutterError.onError;
    final screenErrors = <String>[];
    final live = LiveReporter('City ride (app)',
        phone: phone, code: otp, title: 'Customer: login → manzil → kiraya');
    await live.start();

    final loginButton = find.text('Send verification code');
    final verifyButton = find.text('Verify and continue');
    final home = find.byWidgetPredicate((w) =>
        w is Text && (w.data == 'Where to?' || w.data == 'Where are you going?'));

    await live.step(tester, 'App khuli', () async {
      app.main();
      // Screen errors (a missing picture, an overflow) are noted, not fatal:
      // the run should show every screen, not stop at the first warning.
      FlutterError.onError = (details) {
        screenErrors.add(details.exceptionAsString().split('\n').first);
        // ignore: avoid_print
        print('[live] screen error: ${details.exceptionAsString()}');
      };
      await waitFor(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'Send verification code' || w.data == 'Where to?' || w.data == 'Where are you going?')), timeout: const Duration(seconds: 60));
    });

    if (loginButton.evaluate().isNotEmpty) {
      await live.step(tester, 'Mobile number + shara\'it', () async {
        await waitFor(tester, find.byType(TextField));
        var field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '03001234567');
        // Name first, number second.
        if (field.evaluate().isEmpty) field = find.byType(TextField).last;
        await tester.enterText(field, phone);
        await tester.pump();
        // The terms row (UdCheckboxRow): ticked through its own callback, so a
        // tap landing on the Terms / Privacy links cannot open a document.
        final agree = find.byType(UdCheckboxRow);
        await waitFor(tester, agree);
        final row = tester.widget<UdCheckboxRow>(agree.first);
        if (!row.value) row.onChanged?.call(true);
        await settle(tester, const Duration(milliseconds: 600));
      });

      await live.step(tester, 'OTP bheja', () async {
        await tester.tap(loginButton);
        await waitFor(tester, verifyButton, timeout: const Duration(seconds: 40));
      });

      await live.step(tester, 'OTP daala → home', () async {
        // The code field is Offstage (the boxes above only draw it), so it is
        // filled through its own controller and onChanged, as autofill does.
        final input = find.byType(TextField, skipOffstage: false);
        await waitFor(tester, input);
        final field = tester.widget<TextField>(input.first);
        field.controller?.text = otp;
        field.onChanged?.call(otp);
        await tester.pump();
        await settle(tester, const Duration(seconds: 1));
        if (verifyButton.evaluate().isNotEmpty && home.evaluate().isEmpty) {
          await tester.tap(verifyButton);
        }
        await waitFor(tester, home, timeout: const Duration(seconds: 60));
        await settle(tester, const Duration(seconds: 3));
      });
    } else {
      await live.info(tester, 'Pehle se signed in');
    }

    await live.step(tester, 'Manzil search: $place', () async {
      await waitFor(tester, home);
      await tester.tap(home.first);
      await settle(tester, const Duration(seconds: 2));
      final input = find.byType(TextField);
      await waitFor(tester, input);
      await tester.enterText(input.first, place);
      await settle(tester, const Duration(seconds: 5));
    });

    await live.step(tester, 'Manzil chuni', () async {
      // The first suggestion that names the place (the field itself is excluded).
      final hits = find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? '').toLowerCase().contains(place.toLowerCase()) &&
          w.data != place);
      await waitFor(tester, hits, timeout: const Duration(seconds: 20));
      await tester.tap(hits.first, warnIfMissed: false);
      await settle(tester, const Duration(seconds: 6));
    });

    await live.step(tester, 'Kiraya dikha (Rs, PKR 500,000 nahi)', () async {
      final fare = find.byWidgetPredicate((w) =>
          w is Text && RegExp(r'(Rs|PKR)\s?[0-9]').hasMatch(w.data ?? ''));
      await waitFor(tester, fare, timeout: const Duration(seconds: 30));
      final absurd = find.byWidgetPredicate((w) =>
          w is Text && RegExp(r'(Rs|PKR)\s?[0-9]{3},?[0-9]{3}').hasMatch(w.data ?? '') &&
          int.parse(RegExp(r'[0-9][0-9,]*').firstMatch(w.data!)!.group(0)!.replaceAll(',', '')) > 50000);
      if (absurd.evaluate().isNotEmpty) {
        throw TestFailure('Kiraya bohat zyada: ${(absurd.evaluate().first.widget as Text).data}');
      }
    });

    if (screenErrors.isNotEmpty) {
      await live.info(tester, 'Screen errors: ${screenErrors.length}',
          detail: screenErrors.toSet().take(5).join(' | '));
    }
    await live.finish();
    FlutterError.onError = originalOnError;
    expect(live.hasFailed, isFalse, reason: 'Admin → Live testing par fail wala qadam dekhein.');
  });
}
