import 'dart:async';

class SimulatedLocationPoint {
  const SimulatedLocationPoint({required this.label, required this.progress, required this.etaMinutes});
  final String label;
  final double progress;
  final int etaMinutes;
}

class SimulatedLocationService {
  const SimulatedLocationService();

  Stream<SimulatedLocationPoint> watchTrip({Duration interval = const Duration(seconds: 3)}) async* {
    const points = <SimulatedLocationPoint>[
      SimulatedLocationPoint(label: 'Ghari Pan, Muzaffarabad', progress: .08, etaMinutes: 132),
      SimulatedLocationPoint(label: 'Kohala Road', progress: .24, etaMinutes: 114),
      SimulatedLocationPoint(label: 'Near Pattika', progress: .38, etaMinutes: 96),
      SimulatedLocationPoint(label: 'Near Athmuqam', progress: .58, etaMinutes: 66),
      SimulatedLocationPoint(label: 'Approaching Keran', progress: .82, etaMinutes: 28),
      SimulatedLocationPoint(label: 'Keran, Neelum Valley', progress: 1, etaMinutes: 0),
    ];

    for (final point in points) {
      await Future<void>.delayed(interval);
      yield point;
    }
  }
}
