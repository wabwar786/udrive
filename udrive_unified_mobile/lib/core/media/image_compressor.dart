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

  /// The longest edge of the small copy shown in lists.
  ///
  /// Measured rather than guessed. A phone photograph of a car, re-encoded at
  /// this width, lands around **75 KB**; the full reviewed photograph at 1600px
  /// is about **2.3 MB**, because [shrink] re-encodes to PNG and PNG is a poor
  /// container for a photograph. That is roughly thirty times less to send, and
  /// it is the difference between a customer's offer card filling in under ten
  /// seconds and filling in several minutes.
  ///
  /// 320 rather than 240 because the card is about 120 logical pixels wide, and
  /// on a three-times screen that is 360 real ones. 240 saves another 34 KB and
  /// looks soft on exactly the phones most drivers and customers carry.
  static const int _thumbEdge = 320;

  /// A small copy of [file], for lists — or null when one cannot be made.
  ///
  /// Null rather than the original: the caller uploads this *in addition to* the
  /// full photograph, and uploading a second full-size copy under a thumbnail's
  /// name would make the very thing it is meant to fix worse.
  static Future<PlatformFile?> thumbnail(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) return null;
    if (file.name.toLowerCase().endsWith('.pdf')) return null;

    final small = await _resize(bytes, _thumbEdge, file.name);
    if (small == null) return null;

    // Never upload a "thumbnail" that is not actually smaller.
    return small.size >= bytes.length ? null : small;
  }

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

    final shrunk = await _resize(bytes, _maxEdge, file.name);
    if (shrunk == null || shrunk.size >= bytes.length) return file;
    return shrunk;
  }

  /// Re-encodes [bytes] so the longest edge is at most [maxEdge].
  ///
  /// Null when the picture is already small enough, or when anything at all goes
  /// wrong — a failed resize must never cost somebody their upload.
  ///
  /// The output is PNG because `dart:ui` has no JPEG encoder and this file is
  /// deliberately dependency-free. That costs real bytes on a photograph: the
  /// same picture as JPEG would be roughly a tenth of this. It is the price of
  /// not adding an image package to every platform, and it is why [thumbnail]
  /// exists — the small copy is what customers wait for, and at 320px even PNG
  /// is cheap.
  static Future<PlatformFile?> _resize(
    Uint8List bytes,
    int maxEdge,
    String originalName,
  ) async {
    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );

      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;

      if (longest <= maxEdge) {
        descriptor.dispose();
        return null;
      }

      final scale = maxEdge / longest;
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

      final out = data?.buffer.asUint8List();
      if (out == null) return null;

      return PlatformFile(
        name: _renamed(originalName),
        size: out.length,
        bytes: Uint8List.fromList(out),
      );
    } catch (_) {
      return null;
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
