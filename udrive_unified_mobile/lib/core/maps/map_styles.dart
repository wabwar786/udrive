/// Map styling for Google Maps.
///
/// Two palettes. [light] is the default the customer sees; [dark] is kept for
/// the driver screens, which sit on a dark chrome.
///
/// The customer map used to be dark too, on the argument that it should match
/// the app. That was the wrong trade: the map is the one part of the screen a
/// person is reading rather than looking at — street names, junctions, which
/// side of the road a pin is on — and a dark tint costs legibility on a phone
/// held at arm's length in daylight. The panels around it carry the theme
/// instead.
///
/// Points of interest and transit labels stay off in both: the map exists to
/// show a route and nearby vehicles, and every extra label competes with the
/// markers that matter.
class MapStyles {
  const MapStyles._();

  /// The customer's map: a plain, readable light surface.
  ///
  /// Deliberately close to Google's own default. Anything more styled is a
  /// designer's preference paid for by the person trying to find their street.
  static const String light = '''
[
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#E8F3E8"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#55606B"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#D9E9F2"}]}
]
''';

  static const String dark = '''
[
  {"elementType":"geometry","stylers":[{"color":"#16232D"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#9FB3BB"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0E1A21"}]},

  {"featureType":"administrative","elementType":"geometry",
   "stylers":[{"color":"#2B3F4C"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill",
   "stylers":[{"color":"#B9CBD3"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill",
   "stylers":[{"color":"#D6E3E8"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill",
   "stylers":[{"color":"#8FA6B0"}]},

  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},

  {"featureType":"landscape.natural","elementType":"geometry",
   "stylers":[{"color":"#18262F"}]},
  {"featureType":"landscape.man_made","elementType":"geometry",
   "stylers":[{"color":"#1A2A34"}]},

  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2A3D49"}]},
  {"featureType":"road","elementType":"geometry.stroke",
   "stylers":[{"color":"#22323E"}]},
  {"featureType":"road","elementType":"labels.text.fill",
   "stylers":[{"color":"#94AAB5"}]},
  {"featureType":"road.arterial","elementType":"geometry",
   "stylers":[{"color":"#324856"}]},
  {"featureType":"road.highway","elementType":"geometry",
   "stylers":[{"color":"#3C5666"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke",
   "stylers":[{"color":"#2A3D49"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill",
   "stylers":[{"color":"#C2D4DD"}]},
  {"featureType":"road.local","elementType":"geometry",
   "stylers":[{"color":"#243642"}]},

  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0E2833"}]},
  {"featureType":"water","elementType":"labels.text.fill",
   "stylers":[{"color":"#4C7186"}]}
]
''';
}
