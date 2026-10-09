/// The five kinds of vehicle a customer can ask for.
///
/// A driver registers a vehicle under any of a dozen names (Motorcycle,
/// Scooter, Sedan, SUV, 7-Seater, Auto Rickshaw, Coaster...); a customer picks
/// Car, Bike, Rickshaw, Hiace or Coster. [vehicleClassOf] turns either into the
/// same five names, so a car request shows cars and a bike request shows bikes.
///
/// Same rule as `udrive.vehicle_class()` on the server (migration 082). Keep the
/// two equal: the server decides which drivers receive a request, this decides
/// which vehicles the map draws.
enum VehicleClass { car, bike, rickshaw, hiace, coster }

VehicleClass vehicleClassOf(String? category) {
  final c = (category ?? '').toLowerCase();
  if (c.contains('coaster') || c.contains('coster') || c.contains('bus')) {
    return VehicleClass.coster;
  }
  if (c.contains('hiace') || c.contains('van')) return VehicleClass.hiace;
  if (c.contains('bike') || c.contains('motor') || c.contains('scoot')) {
    return VehicleClass.bike;
  }
  if (c.contains('rickshaw') ||
      c.contains('auto') ||
      c.contains('tuk') ||
      c.contains('qingqi') ||
      c.contains('chingchi')) {
    return VehicleClass.rickshaw;
  }
  return VehicleClass.car;
}

/// The class the server sent (`vehicleClass`), or one worked out from the name.
VehicleClass vehicleClassFromApi(Object? serverClass, String? category) {
  final value = '${serverClass ?? ''}'.trim();
  return value.isEmpty ? vehicleClassOf(category) : vehicleClassOf(value);
}
