/// Whether the app-wide driver tracking should stand down.
///
/// A counter in a file of its own, and that is the whole point of it.
///
/// Two places publish a driver's position: [DriverLocationCoordinator], which
/// runs for as long as the driver is in driver mode, and the live navigation
/// screen, which runs while that screen is open. Both must not publish the same
/// trip at once — the driver pays for it twice in battery and data.
///
/// The switch used to be a pair of statics on the coordinator itself, which
/// made the navigation screen fail to compile against any older copy of that
/// file. Here, neither file needs the other: the navigation screen raises the
/// flag, the coordinator reads it, and a build where one of them is out of date
/// still compiles and still works — it simply publishes twice until the other
/// file catches up, which is a cost, not a breakage.
library;

class DriverTrackingSuspension {
  const DriverTrackingSuspension._();

  /// A count rather than a flag: two live screens can briefly overlap while one
  /// is being pushed over the other, and a flag would be cleared by the first
  /// of them to close.
  static int _depth = 0;

  /// True while something else is publishing this driver's position.
  static bool get isSuspended => _depth > 0;

  static void suspend() => _depth++;

  static void resume() {
    if (_depth > 0) _depth--;
  }
}
