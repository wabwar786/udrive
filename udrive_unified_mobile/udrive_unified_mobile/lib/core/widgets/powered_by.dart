import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// "Powered by Wabwar", at the foot of the sign-in screens.
///
/// Quiet on purpose. It is a maker's mark, not a call to action — full weight
/// and full contrast here would compete with the button directly above it,
/// which is the one thing the person is meant to press.
///
/// Only on the two screens before sign-in. Once somebody is using the app, who
/// built it is no longer information they need on every screen.
class PoweredByWabwar extends StatelessWidget {
  const PoweredByWabwar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 18, bottom: 6),
      child: Center(
        child: Text(
          'Powered by Wabwar',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: .3,
            fontWeight: FontWeight.w600,
            color: AppText.disabled,
          ),
        ),
      ),
    );
  }
}
