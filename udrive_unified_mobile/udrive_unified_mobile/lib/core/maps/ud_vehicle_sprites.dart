import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The shapes drawn for a vehicle sitting on the map.
enum UdVehicleSprite { car, bike, van }

/// Top-down vehicle sprites, drawn rather than shipped as images.
///
/// A marker that reads as a car from directly above — rotated to the direction
/// the driver is facing — is what makes a map feel live. A stack of identical
/// teardrop pins does not: it says "something is here" when the customer is
/// asking "is there a car near me, and which way is it going?".
///
/// These are painted with [Canvas] instead of shipped as PNGs for two reasons.
/// They stay crisp at any device pixel ratio, where a fixed asset either blurs
/// on a dense screen or wastes bytes on a cheap one. And they take their colours
/// from the theme, so the sprites cannot drift out of step with the rest of the
/// app the way a hand-exported image quietly does.
class UdVehicleSprites {
  UdVehicleSprites._();

  /// Logical size of a sprite, before the device pixel ratio is applied.
  ///
  /// Roughly the footprint of a real car at the zoom Home opens at. Bigger and
  /// four vehicles on one street merge into a blob; smaller and the shape stops
  /// reading as a car at all.
  static const Size _size = Size(26, 52);

  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  /// PNG bytes for a sprite, cached per shape and pixel ratio.
  ///
  /// The cache matters: Home redraws its markers on every presence poll, and
  /// rasterising a picture per vehicle per poll is work that shows up as jank
  /// on exactly the cheap phones most of these customers are using.
  static Future<Uint8List> bytes(
    UdVehicleSprite sprite, {
    required double pixelRatio,
  }) async {
    // Quantised so a ratio of 2.625 and 2.63 share one entry rather than
    // filling the cache with near-duplicates.
    final ratio = (pixelRatio.clamp(1.0, 4.0) * 4).round() / 4;
    final key = '${sprite.name}@$ratio';

    final cached = _cache[key];
    if (cached != null) return cached;

    final width = (_size.width * ratio).round();
    final height = (_size.height * ratio).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(ratio);
    _paint(canvas, sprite);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    final result = data!.buffer.asUint8List();
    _cache[key] = result;
    return result;
  }

  /// Logical width and height, for the offline renderer which draws the same
  /// shapes as a widget rather than a bitmap.
  static Size get size => _size;

  /// Paints a sprite into an already-scaled canvas.
  ///
  /// Shared by both renderers so the online and offline maps cannot end up
  /// showing different cars.
  static void _paint(Canvas canvas, UdVehicleSprite sprite) {
    switch (sprite) {
      case UdVehicleSprite.car:
        _paintCar(canvas);
      case UdVehicleSprite.bike:
        _paintBike(canvas);
      case UdVehicleSprite.van:
        _paintVan(canvas);
    }
  }

  static const _body = Color(0xFFEDF1F3);
  static const _bodyEdge = Color(0xFF9FB0B8);
  static const _glass = Color(0xFF2B3A42);
  static const _shadow = Color(0x59000000);

  static void _paintCar(Canvas canvas) {
    final w = _size.width;
    final h = _size.height;

    // A soft drop below the body. Without it the sprite looks pasted onto the
    // map instead of sitting on it.
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .17, h * .09, w * .87, h * .97, w * .30, w * .30),
      Paint()
        ..color = _shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );

    final body = RRect.fromLTRBXY(
      w * .13,
      h * .04,
      w * .87,
      h * .96,
      w * .30,
      w * .30,
    );
    canvas.drawRRect(body, Paint()..color = _body);
    canvas.drawRRect(
      body,
      Paint()
        ..color = _bodyEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );

    // Windscreen, roof and rear window as one dark band broken by the roof.
    // Read from above, that split is the single clearest signal of which end
    // of the car is the front.
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .22, h * .22, w * .78, h * .40, w * .14, w * .14),
      Paint()..color = _glass,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .24, h * .60, w * .76, h * .76, w * .13, w * .13),
      Paint()..color = _glass,
    );

    // Wing mirrors. Small, but they finish the silhouette.
    final mirror = Paint()..color = _body;
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .03, h * .40, w * .16, h * .48, 2, 2),
      mirror,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .84, h * .40, w * .97, h * .48, 2, 2),
      mirror,
    );

    // Headlights, so the nose is unmistakable at a glance.
    final lamp = Paint()..color = AppColors.secondary;
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .20, h * .06, w * .35, h * .12, 2, 2),
      lamp,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .65, h * .06, w * .80, h * .12, 2, 2),
      lamp,
    );
  }

  static void _paintBike(Canvas canvas) {
    final w = _size.width;
    final h = _size.height;

    canvas.drawRRect(
      RRect.fromLTRBXY(w * .34, h * .16, w * .70, h * .92, w * .18, w * .18),
      Paint()
        ..color = _shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
    );

    // Wheels first, so the frame sits over them.
    final tyre = Paint()..color = _glass;
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .44, h * .10, w * .56, h * .30, 2.5, 2.5),
      tyre,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .44, h * .70, w * .56, h * .90, 2.5, 2.5),
      tyre,
    );

    canvas.drawRRect(
      RRect.fromLTRBXY(w * .38, h * .28, w * .62, h * .74, w * .12, w * .12),
      Paint()..color = _body,
    );

    // Handlebars — the crossbar is what stops this reading as a stray dash.
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .22, h * .26, w * .78, h * .33, 2.5, 2.5),
      Paint()..color = _body,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .42, h * .06, w * .58, h * .12, 2, 2),
      Paint()..color = AppColors.secondary,
    );
  }

  static void _paintVan(Canvas canvas) {
    final w = _size.width;
    final h = _size.height;

    canvas.drawRRect(
      RRect.fromLTRBXY(w * .13, h * .06, w * .91, h * .99, w * .18, w * .18),
      Paint()
        ..color = _shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );

    // Squarer and fuller than the car: a Coster or Hiace read from above is
    // mostly roof, and the boxier outline is what separates the two at a
    // glance without needing a label.
    final body = RRect.fromLTRBXY(
      w * .09,
      h * .02,
      w * .91,
      h * .98,
      w * .18,
      w * .18,
    );
    canvas.drawRRect(body, Paint()..color = _body);
    canvas.drawRRect(
      body,
      Paint()
        ..color = _bodyEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );

    canvas.drawRRect(
      RRect.fromLTRBXY(w * .18, h * .13, w * .82, h * .27, w * .10, w * .10),
      Paint()..color = _glass,
    );
    // A long roof panel rather than a rear window — vans have no glass there.
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .20, h * .35, w * .80, h * .88, w * .07, w * .07),
      Paint()..color = _bodyEdge.withValues(alpha: .35),
    );

    canvas.drawRRect(
      RRect.fromLTRBXY(w * .16, h * .04, w * .32, h * .10, 2, 2),
      Paint()..color = AppColors.secondary,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(w * .68, h * .04, w * .84, h * .10, 2, 2),
      Paint()..color = AppColors.secondary,
    );
  }
}

/// Paints a sprite into a widget, for the offline map.
///
/// `flutter_map` takes widgets rather than bitmaps, so the same drawing code is
/// reused through a painter instead of rasterising and decoding a PNG for no
/// reason.
class UdVehicleSpritePainter extends CustomPainter {
  const UdVehicleSpritePainter(this.sprite);

  final UdVehicleSprite sprite;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / UdVehicleSprites.size.width,
      size.height / UdVehicleSprites.size.height,
    );
    UdVehicleSprites._paint(canvas, sprite);
    canvas.restore();
  }

  @override
  bool shouldRepaint(UdVehicleSpritePainter oldDelegate) =>
      oldDelegate.sprite != sprite;
}
