/// Central, build-time configuration for UDrive.
///
/// Anything that a product owner may want to change without hunting through
/// widget code belongs here. Secrets are intentionally NOT stored here — see
/// [placesProxyPath] for how Google Places/Geocoding keys stay server side.
class AppConfig {
  const AppConfig._();

  // ---------------------------------------------------------------- branding
  static const String appName = 'UDrive';
  static const String referralShareUrl = 'https://udrive.pk/app';

  // ------------------------------------------------------------- tour policy
  /// Minimum share of the total fare a customer must pay up front when booking
  /// a tour. The customer may choose to pay more, never less.
  ///
  /// Business rule confirmed with the product owner: 20% minimum.
  static const double tourAdvancePercent = 0.20;

  /// Window during which a confirmed tour booking can be cancelled free of
  /// charge, starting the moment the advance payment succeeds.
  static const Duration tourFreeCancellationWindow = Duration(minutes: 5);

  // ---------------------------------------------------------------- defaults
  /// Muzaffarabad — used until the device reports a real position.
  static const double fallbackLatitude = 34.3700;
  static const double fallbackLongitude = 73.4711;
  static const double defaultMapZoom = 14.8;
  static const double focusedMapZoom = 15.8;

  /// Street level. The home map never zooms out past this, because below it
  /// road names disappear and the map stops helping anyone.
  static const double homeMinZoom = 11.0;

  /// Zoom used when the app first fixes the customer's position.
  static const double pickupZoom = 16.2;

  // ------------------------------------------------------------------- maps
  /// The Maps SDK key CANNOT be supplied at runtime — Google requires it in
  /// AndroidManifest.xml / AppDelegate.swift at build time. Pass it in with:
  ///
  ///   flutter build apk --dart-define=MAPS_ANDROID_KEY=AIza...
  ///
  /// so the key never gets committed to source control. This constant only
  /// lets the app detect whether a key was supplied, so it can show a helpful
  /// message instead of a blank grey map.
  static const String mapsAndroidKey =
      String.fromEnvironment('MAPS_ANDROID_KEY', defaultValue: '');

  static bool get hasMapsKey => mapsAndroidKey.trim().isNotEmpty;

  // --------------------------------------------------------------- geocoding
  /// Places autocomplete and geocoding are proxied through the UDrive API so
  /// the Google key lives on the server, where an admin can set or rotate it
  /// without shipping a new app build. If the proxy is unavailable the client
  /// falls back to OpenStreetMap Nominatim, which needs no key at all.
  static const String placesProxyPath = '/api/v1/places/autocomplete';
  static const String geocodeProxyPath = '/api/v1/places/reverse';

  static const Duration searchDebounce = Duration(milliseconds: 350);
  static const Duration networkTimeout = Duration(seconds: 12);

  // ------------------------------------------------- nearby vehicles (home)
  /// Radius of the "vehicles around you" ring on Home.
  static const double nearbyVehiclesRadiusKm = 5;

  /// How often the home map refreshes vehicle positions.
  ///
  /// Ten seconds is a deliberate balance: fast enough that the map feels live,
  /// slow enough that a phone left open on Home does not drain battery or
  /// hammer the API. Google does not bill for this — Maps charges per map load,
  /// not per marker update — so the cost here is ours, not theirs.
  static const Duration nearbyVehiclesPoll = Duration(seconds: 10);

  /// Markers to draw before the map stops adding more.
  static const int nearbyVehiclesLimit = 40;

  // ------------------------------------------------------------- near me
  static const List<double> nearMeRadiiKm = [1, 3, 5, 10];
  static const double nearMeDefaultRadiusKm = 3;

  // ------------------------------------------------------------------ motion
  static const Duration panelSwitch = Duration(milliseconds: 220);
  static const Duration pillExpand = Duration(milliseconds: 250);
}
