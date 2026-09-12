import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Clear cached data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
        children: [
          const Text(
            'Seeing something out of date?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'The app keeps copies of things that rarely change — vehicle '
            'photographs, place searches, map tiles — so screens open without '
            'waiting. Clearing them makes the app fetch everything again.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.all(AppRadii.panel),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 18, color: AppText.disabled),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'You stay signed in. Your language and colour choice are '
                    'kept too — only cached copies are removed.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppText.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTint.success,
                borderRadius: AppRadii.all(AppRadii.row),
              ),
              child: Text(
                _result!,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppTint.successText,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _clear,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Clear cached data'),
          ),
        ],
      ),
    );
  }
}
