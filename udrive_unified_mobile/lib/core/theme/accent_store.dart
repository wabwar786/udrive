import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three accent colours a customer can choose between.
///
/// Three, not a colour wheel. A free picker lets someone land on a colour that
/// fails contrast against the dark surfaces, or one that collides with the red
/// used for danger and the green used for success — and then every warning in
/// the app quietly stops reading as a warning. These three were each checked
/// against those, and against the ink placed on top of them.
enum AppAccent {
  /// The default. Warm, and far enough from both danger red and success green.
  amber(
    label: 'Amber',
    seed: Color(0xFFF5A524),
    ink: Color(0xFF1A1200),
    wash: Color(0xFF3A2A0E),
  ),

  /// Cooler, for anyone who finds amber loud.
  sky(
    label: 'Sky',
    seed: Color(0xFF4CA6FF),
    ink: Color(0xFF04131F),
    wash: Color(0xFF0E2C42),
  ),

  /// Closest to the original lime, kept for people who liked it.
  lime(
    label: 'Lime',
    seed: Color(0xFFA6E22E),
    ink: Color(0xFF11190A),
    wash: Color(0xFF22320F),
  );

  const AppAccent({
    required this.label,
    required this.seed,
    required this.ink,
    required this.wash,
  });

  final String label;

  /// The accent itself: buttons, selected states, the fare.
  final Color seed;

  /// Text and icons placed on top of [seed].
  ///
  /// Stored rather than computed, because all three of these are light colours
  /// and white on them fails contrast at button sizes.
  final Color ink;

  /// A low-saturation version for selected tiles and quiet backgrounds.
  final Color wash;
}

/// Remembers which accent the customer picked.
///
/// Local only. This is a preference about their own screen, not something the
/// platform needs to know, and sending it to a server would mean a round trip
/// before the app could finish painting.
class AccentStore extends ChangeNotifier {
  AccentStore._();

  /// One instance, because the theme is read during `build` all over the app
  /// and passing it down by constructor would touch every screen.
  static final AccentStore instance = AccentStore._();

  static const _key = 'udrive.accent';

  AppAccent _accent = AppAccent.amber;
  AppAccent get accent => _accent;

  /// Restores the saved choice. Called once, before the app paints.
  ///
  /// Failure is silent and leaves the default. A preference that cannot be read
  /// is not a reason to refuse to start.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      final match = AppAccent.values.where((value) => value.name == saved);
      if (match.isNotEmpty) {
        _accent = match.first;
        notifyListeners();
      }
    } catch (_) {
      // Keep the default.
    }
  }

  Future<void> select(AppAccent accent) async {
    if (_accent == accent) return;
    _accent = accent;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, accent.name);
    } catch (_) {
      // The choice still applies for this session; it just will not persist.
    }
  }
}
