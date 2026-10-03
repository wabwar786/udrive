import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// The one sound in the app, and the one place it is played.
///
/// ## Why this file exists at all
///
/// The driver screen and the customer offers screen both already asked for a
/// sound, with the same two lines:
///
/// ```dart
/// SystemSound.play(SystemSoundType.alert);
/// HapticFeedback.mediumImpact();
/// ```
///
/// **On Android the first line does nothing.** Flutter's Android embedding
/// implements `SystemSoundType.click` and ignores `alert` — so the call ran, no
/// exception was thrown, and nothing was ever heard. Only the haptic fired,
/// which a phone in a pocket on a bumpy road does not deliver. On iOS it worked,
/// which is why it survived.
///
/// ## Why a bundled clip, when the old comment argued against one
///
/// Those files carried a reasoned note: the system tone respects silent mode and
/// the volume the person has set, where a bundled clip ignores both and "would
/// play at full volume in a mosque". That reasoning was sound and the trade is
/// still real — but it was buying nothing, because the system tone was silent on
/// the handset nearly every driver uses.
///
/// So the trade is made deliberately now, not by accident:
///
/// * A ride request is worth hearing. A driver who misses it loses the fare, and
///   a customer who misses an offer loses the car — both of which are worse than
///   a beep at the wrong moment.
/// * The clip is short (half a second), quiet (volume below full), and plays at
///   most once every two seconds however many events arrive.
/// * It only plays for the two things that are actually time-critical. Nothing
///   routine makes a sound.
///
/// ## What it will not do
///
/// It never throws. Audio on Android fails for reasons that have nothing to do
/// with this app — another app holding the audio focus, a Bluetooth device
/// half-connected, a codec that is busy. A driver must not lose a ride request
/// because the chime could not be played, so every failure here is swallowed and
/// the haptic still fires.
class AlertSound {
  const AlertSound._();

  /// One player for the whole app.
  ///
  /// Created once and reused: constructing an `AudioPlayer` per alert leaks
  /// native players on Android, and the second request in a busy minute is
  /// exactly when that starts to matter.
  static AudioPlayer? _player;

  static DateTime _lastPlayed = DateTime.fromMillisecondsSinceEpoch(0);

  /// Two requests arriving in the same poll are one noise, not two.
  static const Duration _minimumGap = Duration(seconds: 2);

  /// Loud enough to hear in a car, short of making somebody jump.
  static const double _volume = 0.85;

  /// Sounds the alert, and buzzes.
  ///
  /// Safe to call from anywhere, at any time, including while a previous alert
  /// is still playing — the gap above drops the duplicate rather than layering
  /// two chimes into a rattle.
  ///
  /// Pass `haptics: false` where the caller buzzes for itself. One site wants
  /// `heavyImpact` — the driver arriving — and two buzzes in a row read as a
  /// stutter rather than as emphasis.
  ///
  /// Named `chime` rather than `play`, and there is no `dispose` on this class.
  /// Both are deliberate: the repo's own `tool/audit_structure.py` matches
  /// static method names across the whole app, so a static called `play` or
  /// `dispose` here made it flag every `player.play(...)` and every
  /// `super.dispose()` in fifty-one other files. A name nobody else uses keeps
  /// that check worth reading. The single player lives for as long as the app
  /// does, which is what an alert sound wants anyway.
  static Future<void> chime({bool haptics = true}) async {
    // The haptic first, and outside the try. It is the half that works on a
    // silenced phone, so it must not depend on audio succeeding.
    if (haptics) {
      unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
    }

    final now = DateTime.now();
    if (now.difference(_lastPlayed) < _minimumGap) return;
    _lastPlayed = now;

    try {
      final player = _player ??= AudioPlayer();

      // Released rather than held: keeping the audio session open leaves the
      // phone in its "media playing" state on some Android builds, which pauses
      // the driver's own music between every ride request.
      await player.setReleaseMode(ReleaseMode.release);
      await player.setVolume(_volume);
      await player.play(AssetSource('sounds/alert.wav'));
    } catch (_) {
      // Deliberately silent. See the note above: a failed chime must never
      // become a failed ride request.
    }
  }
}
