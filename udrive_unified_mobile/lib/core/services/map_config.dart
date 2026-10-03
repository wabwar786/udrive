class MapConfig {
  const MapConfig._();

  static const bool liveGoogleMapsEnabled = bool.fromEnvironment(
    'GOOGLE_MAPS_ENABLED',
    defaultValue: false,
  );

  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static bool get hasLiveConfiguration =>
      liveGoogleMapsEnabled && googleMapsApiKey.trim().isNotEmpty;
}
