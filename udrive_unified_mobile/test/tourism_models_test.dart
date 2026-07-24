import 'package:flutter_test/flutter_test.dart';
import 'package:udrive_mobile/data/models.dart';

void main() {
  test('mountain-ready vehicle receives a high readiness score', () {
    final vehicle = VehicleRecord(
      id: 'V-TEST',
      make: 'Toyota',
      model: 'Prado',
      year: 2024,
      color: 'White',
      registration: 'AJK-100',
      category: '4×4 Jeep',
      seats: 7,
      luggage: 5,
      airConditioning: true,
      fourWheelDrive: true,
      heating: true,
      firstAidKit: true,
      fireExtinguisher: true,
      spareTyre: true,
      snowChains: true,
      childSeat: true,
      status: VerificationStatus.verified,
      documents: const {'Registration document': true},
    );

    expect(vehicle.mountainReady, isTrue);
    expect(vehicle.readinessScore, greaterThanOrEqualTo(90));
  });

  test('live trip progress stays within valid range', () {
    final trip = LiveTripSession(
      id: 'TR-1',
      route: 'A to B',
      driver: 'Driver',
      vehicle: 'SUV',
      registration: 'AJK-1',
      destination: 'B',
      etaMinutes: 30,
      currentLocation: 'A',
      progress: .5,
    );

    expect(trip.progress, inInclusiveRange(0, 1));
  });
}
