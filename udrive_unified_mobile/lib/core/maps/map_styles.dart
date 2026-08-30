/// Dark map styling for Google Maps.
///
/// A default Google map is light grey. Against a near-black app it looks like a
/// window into a different product, and the brand-green route is hard to pick
/// out on pale roads. This palette is built from the app's own surfaces so the
/// map reads as part of the screen.
///
/// Points of interest and transit labels are turned off deliberately: the map
/// exists to show a route and nearby vehicles, and every extra label competes
/// with the markers that matter.
class MapStyles {
  const MapStyles._();

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
