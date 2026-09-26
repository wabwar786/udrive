import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// Clears the data the app keeps on the phone between sessions.
///
/// The app caches things that rarely change — vehicle photographs, place
/// searches, map tiles — so screens open without waiting. When one of those
/// changes on the server, the phone can keep showing the old copy, and there
/// was no way to say "forget what you have and fetch it again" short of
/// reinstalling.
///
/// It does **not** sign anyone out. Losing a session because you wanted a fresh
/// photograph would be a poor trade, and on a weak signal signing back in is
/// not a small thing.
class CacheResetScreen extends StatefulWidget {
  const CacheResetScreen({super.key});

  @override
  State<CacheResetScreen> createState() => _CacheResetScreenState();
}

class _CacheResetScreenState extends State<CacheResetScreen> {
  bool _busy = false;
  String? _result;

  /// Preference keys that must survive.
  ///
  /// Everything else under SharedPreferences is a cache. These are the person's
  /// own settings, and clearing them would turn a refresh into a reset.
  static const _keep = {
    'udrive.accent',
    'udrive.locale',
    'udrive.mode',
  };

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _result = null;
    });

    var removed = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (_keep.contains(key)) continue;

        // Anything holding a token or a session stays, whatever it is called.
        // A hard-coded key list drifts out of date, and when it does the cost
        // should be a stale cache — never someone signed out mid-trip.
        final lower = key.toLowerCase();
        if (lower.contains('token') || lower.contains('session')) continue;

        await prefs.remove(key);
        removed++;
      }

      if (!mounted) return;
      // Pull everything down again, so the effect is visible here rather than
      // on whichever screen they happen to open next.
      await AppControllerScope.of(context).refreshAccount();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = 'Could not clear everything: '
            '${'$error'.replaceFirst('Exception: ', '')}';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = removed == 0
          ? 'Nothing was cached. You are already seeing the latest data.'
          : 'Cleared $removed cached item${removed == 1 ? '' : 's'}. '
              'Screens will fetch fresh data from now on.';
    });
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold and no AppBar: this screen is rendered inside `main_shell`,
    // which already draws a white bar for it. With its own bar as well, the
    // screen showed two stacked bars — the same thing Explore was doing.
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 12, AppSizes.sidePadding, 34),
      children: [
        const UdIconTile(
          icon: Icons.cleaning_services_rounded,
          size: UdIconTileSize.lg,
        ),
        const SizedBox(height: 16),
        Text(
          'Seeing something out of date?',
          style: AppType.h2.copyWith(color: AppText.primary),
        ),
        const SizedBox(height: 10),
        Text(
          'The app keeps copies of things that rarely change — vehicle '
          'photographs, place searches, map tiles — so screens open without '
          'waiting. Clearing them makes the app fetch everything again.',
          style: AppType.body2.copyWith(color: AppText.secondary),
        ),
        const SizedBox(height: 20),
        const UdBanner(
          tone: UdTone.gray,
          icon: Icons.lock_outline_rounded,
          text: 'You stay signed in. Your language and colour choice are kept '
              'too — only cached copies are removed.',
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          UdBanner(
            tone: UdTone.ok,
            icon: Icons.check_circle_outline_rounded,
            text: _result!,
          ),
        ],
        const SizedBox(height: 26),
        UdButton.primary(
          label: 'Clear cached data',
          icon: Icons.cleaning_services_rounded,
          busy: _busy,
          onPressed: _clear,
        ),
      ],
    );
  }
}
