import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/alert_sound.dart';
import 'live_route.dart';
import 'route_tracker.dart';

/// What the banner at the top of the driver's map shows.
class TurnBanner {
  const TurnBanner({
    required this.icon,
    required this.urdu,
    required this.distanceLabel,
    required this.distanceMeters,
  });

  final IconData icon;

  /// The instruction in Urdu, e.g. "بائیں مڑیں".
  final String urdu;

  /// "200 میٹر", "1.4 کلومیٹر" — empty when the turn is here.
  final String distanceLabel;

  final double distanceMeters;
}

/// One kind of turn: its arrow, its Urdu line and the clip that speaks it.
class _Move {
  const _Move(this.clip, this.icon, this.urdu);
  final String clip;
  final IconData icon;
  final String urdu;
}

/// Turns the stored route into Urdu turn-by-turn: a banner and a voice.
///
/// Works entirely on the phone. The route arrives once with every turn in it;
/// after that the banner and the voice are worked out from the car's distance
/// along the road, so a valley with no signal changes nothing.
///
/// The voice is the driver's own recordings (assets/sounds/ur), played two at
/// a time — "دو سو میٹر بعد" then "بائیں مڑیں". A missing clip falls back to
/// the alert chime, so the app works before the recordings are in.
class TurnGuide {
  TurnGuide({required this.route, required this.tracker})
      : _stepAlong = [
          for (final step in route.steps) tracker.alongOf(step.point),
        ];

  final LiveRoute route;
  final RouteTracker tracker;

  /// Where each turn sits along the road, in metres from the start.
  final List<double> _stepAlong;

  /// Announcements already made, as "step:threshold", so each is said once.
  final Set<String> _spoken = <String>{};

  bool _arrivalSpoken = false;

  /// Google's maneuver names that are not a turn worth announcing.
  static const _silent = {
    'DEPART',
    'NAME_CHANGE',
    'MANEUVER_UNSPECIFIED',
    'FERRY',
    'FERRY_TRAIN',
  };

  static const Map<String, _Move> _moves = {
    'TURN_LEFT': _Move('turn_left', Icons.turn_left, 'بائیں مڑیں'),
    'TURN_RIGHT': _Move('turn_right', Icons.turn_right, 'دائیں مڑیں'),
    'TURN_SLIGHT_LEFT':
        _Move('slight_left', Icons.turn_slight_left, 'ہلکا سا بائیں'),
    'TURN_SLIGHT_RIGHT':
        _Move('slight_right', Icons.turn_slight_right, 'ہلکا سا دائیں'),
    'TURN_SHARP_LEFT':
        _Move('sharp_left', Icons.turn_sharp_left, 'تیزی سے بائیں مڑیں'),
    'TURN_SHARP_RIGHT': _Move(
        'sharp_right', Icons.turn_sharp_right, 'تیزی سے دائیں مڑیں'),
    'UTURN_LEFT': _Move('uturn', Icons.u_turn_left, 'یو ٹرن لیں'),
    'UTURN_RIGHT': _Move('uturn', Icons.u_turn_right, 'یو ٹرن لیں'),
    'STRAIGHT': _Move('straight', Icons.straight, 'سیدھا چلتے رہیں'),
    'MERGE': _Move('straight', Icons.merge, 'سیدھا چلتے رہیں'),
    'RAMP_LEFT': _Move('keep_left', Icons.fork_left, 'بائیں جانب رہیں'),
    'FORK_LEFT': _Move('keep_left', Icons.fork_left, 'بائیں جانب رہیں'),
    'RAMP_RIGHT':
        _Move('keep_right', Icons.fork_right, 'دائیں جانب رہیں'),
    'FORK_RIGHT':
        _Move('keep_right', Icons.fork_right, 'دائیں جانب رہیں'),
    'ROUNDABOUT_LEFT':
        _Move('roundabout', Icons.roundabout_left, 'آگے گول چکر ہے'),
    'ROUNDABOUT_RIGHT':
        _Move('roundabout', Icons.roundabout_right, 'آگے گول چکر ہے'),
  };

  /// Distance thresholds with their clips, furthest first.
  static const _thresholds = <(double, String)>[
    (1000.0, 'd_1000'),
    (500.0, 'd_500'),
    (200.0, 'd_200'),
    (100.0, 'd_100'),
  ];

  /// The banner for [fix], or null when there is no turn ahead.
  ///
  /// [toPickup] picks the wording when the next thing is the end of the leg.
  TurnBanner? banner(RouteFix fix, {required bool toPickup}) {
    final next = _nextStep(fix.alongMeters);
    if (next == null) {
      if (fix.remainingMeters > 2000) return null;
      return TurnBanner(
        icon: Icons.flag_rounded,
        urdu: toPickup ? 'سواری کی جگہ' : 'منزل',
        distanceLabel: distanceLabel(fix.remainingMeters),
        distanceMeters: fix.remainingMeters,
      );
    }

    final move = _moves[route.steps[next].maneuver]!;
    final distance = math.max(0.0, _stepAlong[next] - fix.alongMeters);
    return TurnBanner(
      icon: move.icon,
      urdu: move.urdu,
      distanceLabel: distance < 30 ? '' : distanceLabel(distance),
      distanceMeters: distance,
    );
  }

  /// The clips to say now, if any. Each announcement is returned once.
  ///
  /// [speedMps] decides how early "ابھی" comes: three seconds ahead of the
  /// turn, but never closer than 30 metres.
  List<String> announcements(
    RouteFix fix, {
    required double speedMps,
    required bool toPickup,
  }) {
    if (fix.remainingMeters <= 60) {
      if (_arrivalSpoken) return const [];
      _arrivalSpoken = true;
      return [toPickup ? 'arrived_pickup' : 'arrived_destination'];
    }

    final next = _nextStep(fix.alongMeters);
    if (next == null) return const [];

    final move = _moves[route.steps[next].maneuver]!;
    final distance = _stepAlong[next] - fix.alongMeters;
    final nowDistance = math.max(30.0, speedMps * 3);

    if (distance <= nowDistance) {
      final key = '$next:now';
      if (_spoken.add(key)) {
        // Anything further out for this turn is now pointless.
        for (final (metres, _) in _thresholds) {
          _spoken.add('$next:${metres.toInt()}');
        }
        return ['d_now', move.clip];
      }
      return const [];
    }

    // The tightest threshold the car is inside. Saying "500" and "200" back
    // to back because the turn came up quickly would be noise, so only the
    // closest one is spoken and the wider ones are marked as done.
    for (final (metres, clip) in _thresholds.reversed) {
      if (distance <= metres) {
        final key = '$next:${metres.toInt()}';
        if (_spoken.contains(key)) return const [];
        for (final (wider, _) in _thresholds) {
          if (wider >= metres) _spoken.add('$next:${wider.toInt()}');
        }
        // "200" and "100" back to back is one warning too many; "100" is
        // only for a turn that first comes into view that close.
        if (metres == 200) _spoken.add('$next:100');
        // A 1 km warning on a slow road is a minute and a half of waiting;
        // only worth it when the car is moving quickly.
        if (metres == 1000 && speedMps < 11) return const [];
        return [clip, move.clip];
      }
    }
    return const [];
  }

  /// Index of the next turn worth announcing, ahead of [along].
  int? _nextStep(double along) {
    for (var i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      if (_silent.contains(step.maneuver)) continue;
      if (!_moves.containsKey(step.maneuver)) continue;
      // Five metres of slack: a turn the car is on top of has been taken.
      if (_stepAlong[i] > along + 5) return i;
    }
    return null;
  }

  /// "200 میٹر", "1.4 کلومیٹر".
  static String distanceLabel(double metres) {
    if (metres < 1000) {
      final rounded = metres < 100
          ? (metres / 10).round() * 10
          : (metres / 50).round() * 50;
      return '${math.max(10, rounded)} میٹر';
    }
    final km = metres / 1000;
    return '${km < 10 ? km.toStringAsFixed(1) : km.round()} کلومیٹر';
  }
}

/// Plays the driver's Urdu clips, one after another.
///
/// One player, one queue. A new announcement replaces whatever has not been
/// said yet — "200 میٹر بعد" is useless once the car is at the turn.
class UrduVoice {
  UrduVoice._();

  static final UrduVoice instance = UrduVoice._();

  static const _mutedKey = 'nav_voice_muted_v1';

  AudioPlayer? _player;
  List<String> _queue = const [];
  bool _playing = false;
  bool _muted = false;
  bool _loaded = false;

  bool get muted => _muted;

  Future<void> prepare() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool(_mutedKey) ?? false;
    } catch (_) {
      // Default to speaking.
    }
  }

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (value) {
      _queue = const [];
      try {
        await _player?.stop();
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mutedKey, value);
    } catch (_) {}
  }

  /// Says [clips] in order, dropping anything still waiting from before.
  void say(List<String> clips) {
    if (_muted || clips.isEmpty) return;
    _queue = List<String>.of(clips);
    if (!_playing) unawaited(_drain());
  }

  Future<void> _drain() async {
    _playing = true;
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);

      while (_queue.isNotEmpty && !_muted) {
        final clip = _queue.first;
        _queue = _queue.sublist(1);
        try {
          final done = player.onPlayerComplete.first;
          await player.play(AssetSource('sounds/ur/$clip.mp3'));
          await done.timeout(const Duration(seconds: 5));
        } catch (_) {
          // The recording is not in the app yet, or the player failed. A
          // chime says "look at the screen", which is still worth having.
          _queue = const [];
          await AlertSound.chime(haptics: false);
        }
      }
    } finally {
      _playing = false;
    }
  }

  Future<void> stop() async {
    _queue = const [];
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
