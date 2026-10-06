import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_models.dart' show ApiException;
import 'trip_operations_repository.dart';

/// Trips the driver completed while the phone had no internet.
///
/// "Complete trip" with no signal used to spin for 25 seconds and then fail,
/// and the trip stayed open on the server — the driver counted as busy and
/// was offered no further rides. Now the completion is kept on the phone and
/// sent the moment the connection is back: from the live screen while it is
/// open, and from the app-wide driver tracker every twenty seconds and on
/// every return to the app, so it goes out even after the app was closed.
///
/// Sending is safe to repeat. If UDrive completed the trip from the admin
/// panel in the meantime, the server answers that it was already completed.
class TripCompletionQueue {
  const TripCompletionQueue._();

  static const _key = 'udrive_pending_trip_completions_v1';

  /// Completions older than this are dropped: by then UDrive has dealt with
  /// the trip from the admin panel, and an old completion is only noise.
  static const Duration _maxAge = Duration(days: 2);

  static bool _sending = false;

  /// Keeps a completion to send later.
  static Future<void> keep(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final items = _read(prefs)
      ..removeWhere((item) => item['bookingId'] == bookingId)
      ..add({
        'bookingId': bookingId,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
    await prefs.setStringList(_key, items.map(jsonEncode).toList());
  }

  /// Whether a completion for this trip is still waiting to be sent.
  static Future<bool> isPending(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).any((item) => item['bookingId'] == bookingId);
  }

  static Future<void> forget(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final items = _read(prefs)
      ..removeWhere((item) => item['bookingId'] == bookingId);
    await prefs.setStringList(_key, items.map(jsonEncode).toList());
  }

  /// Sends every waiting completion. Returns the ids that went through (or
  /// that the server no longer needs). Stops at the first one that gets no
  /// answer — the signal is still gone.
  static Future<List<String>> sendAll(TripOperationsRepository repository) async {
    if (_sending) return const [];
    _sending = true;
    final done = <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = _read(prefs);
      for (final item in List<Map<String, dynamic>>.from(items)) {
        final bookingId = '${item['bookingId']}';
        final at = '${item['completedAt'] ?? ''}';
        try {
          await repository
              .driverStatus(
                bookingId,
                'TripCompleted',
                reason: 'Completed by the driver at $at (sent when the '
                    'phone was back online).',
              )
              .timeout(const Duration(seconds: 15));
          done.add(bookingId);
        } on ApiException catch (error) {
          final code = error.statusCode;
          if (code == null || code >= 500) break;
          // Refused for good (cancelled meanwhile, no longer this driver's
          // trip): nothing to send any more.
          done.add(bookingId);
        } catch (_) {
          break;
        }
      }
      if (done.isNotEmpty) {
        final fresh = _read(prefs)
          ..removeWhere((item) => done.contains('${item['bookingId']}'));
        await prefs.setStringList(_key, fresh.map(jsonEncode).toList());
      }
    } catch (_) {
      // Storage unavailable: try again next time.
    } finally {
      _sending = false;
    }
    return done;
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    final cutoff = DateTime.now().toUtc().subtract(_maxAge);
    final out = <Map<String, dynamic>>[];
    for (final raw in prefs.getStringList(_key) ?? const <String>[]) {
      try {
        final item = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final at = DateTime.tryParse('${item['completedAt']}');
        if (item['bookingId'] != null && at != null && at.isAfter(cutoff)) {
          out.add(item);
        }
      } catch (_) {
        // Unreadable: dropped.
      }
    }
    return out;
  }
}
