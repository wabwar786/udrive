import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/accent_store.dart';
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
          const SizedBox(height: 26),
          const Text(
            'App colour',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 10),
          const AccentPicker(),

          const SizedBox(height: 26),
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

/// Lets the customer choose the app's accent colour.
///
/// Moved here off the home screen. It is a personalisation someone sets once,
/// and it was sitting above the thing they open the app to do.
///
/// Three swatches, not a colour wheel. A free picker lets someone land on a
/// colour that fails contrast against the dark surfaces, or one that collides
/// with the red used for danger and the green used for success — and then every
/// warning in the app quietly stops reading as a warning.
class AccentPicker extends StatelessWidget {
  const AccentPicker({super.key});

  @override
  Widget build(BuildContext context) {
    // Listens to the store rather than reading it once.
    //
    // Without this the swatches appeared and selecting one did nothing
    // visible: the store notified, but nothing in this subtree was subscribed,
    // so the ring never moved to the colour just chosen.
    return AnimatedBuilder(
      animation: AccentStore.instance,
      builder: (context, _) => _swatches(),
    );
  }

  Widget _swatches() {
    final current = AccentStore.instance.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.panel),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'App colour',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppText.secondary,
              ),
            ),
          ),
          for (final accent in AppAccent.values)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Semantics(
                button: true,
                selected: accent == current,
                label: accent.label,
                child: GestureDetector(
                  onTap: () => AccentStore.instance.select(accent),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.seed,
                      shape: BoxShape.circle,
                      // A ring rather than a tick inside the swatch: the tick
                      // needs a colour of its own, and on three different
                      // backgrounds one of them always reads badly.
                      border: Border.all(
                        color: accent == current
                            ? AppText.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded block on the page.
///
/// The sheet is two of these — what you are booking, then where you are going.
/// Grouping them this way is what makes the screen readable at a glance: one
/// long column of controls all on the same surface gave the eye nowhere to
/// stop.
/// What tour drivers around here charge per day.
///
/// Shown instead of a recommended fare, because there is no recommendation to
/// make: tourism is priced by each driver for their own vehicle, and the
/// platform quoting a figure would be inventing a price nobody set.
///
/// The range is the honest shape of that. A single average would read as an
/// official rate and hide that a Coster and a car are different propositions.
