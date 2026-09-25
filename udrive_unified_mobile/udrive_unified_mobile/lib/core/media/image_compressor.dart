import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

/// Shrinks a photograph before it is uploaded.
///
/// A modern phone camera produces four to eight megabytes per shot. On a mobile
/// connection in Azad Kashmir that is a minute of waiting per document, four
/// documents to send, and an upload that fails halfway leaves the driver with
/// nothing to show for it. The server also refuses anything over ten megabytes,
/// so a phone with a good camera could simply not register.
///
/// None of that detail is needed to read a CNIC or a number plate. Sixteen
/// hundred pixels on the long edge is more than a reviewer looks at.
///
/// Deliberately dependency-free. Adding an image library for this would mean a
/// new package on every platform for one resize, so it uses the codec that
/// Flutter already has.
class ImageCompressor {
  const ImageCompressor._();

  /// Longest edge, in pixels, after shrinking.
  static const int _maxEdge = 1600;

  /// Files at or under this are sent untouched.
  ///
  /// A small photograph does not need re-encoding, and re-encoding it would
  /// risk making it *larger* — PNG is lossless, and a lossless copy of a JPEG
  /// usually is.
  static const int _leaveAloneBytes = 900 * 1024;

  /// Returns a smaller version of [file], or [file] itself.
  ///
  /// Never throws and never returns something bigger. A resize that fails, or
  /// one that produces a larger file than it started with, keeps the original —
  /// a slow upload is a far smaller problem than a document that will not send
  /// at all.
  static Future<PlatformFile> shrink(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.length <= _leaveAloneBytes) return file;

    final name = file.name.toLowerCase();
    if (name.endsWith('.pdf')) return file;

    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );

      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;

      // Already small enough in pixels: re-encoding would only lose quality.
      if (longest <= _maxEdge) {
        descriptor.dispose();
        return file;
      }

      final scale = _maxEdge / longest;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );

      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();

      final shrunk = data?.buffer.asUint8List();
      if (shrunk == null || shrunk.length >= bytes.length) return file;

      return PlatformFile(
        name: _renamed(file.name),
        size: shrunk.length,
        bytes: Uint8List.fromList(shrunk),
      );
    } catch (_) {
      return file;
    }
  }

  /// The re-encoded bytes are PNG, so the name has to say so.
  ///
  /// The server picks the content type from the extension, and a PNG called
  /// `.jpg` is served as `image/jpeg` — which some viewers refuse outright.
  static String _renamed(String original) {
    final dot = original.lastIndexOf('.');
    final stem = dot <= 0 ? original : original.substring(0, dot);
    return '$stem.png';
  }
}
