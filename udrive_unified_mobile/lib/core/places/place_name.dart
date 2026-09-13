/// The first meaningful part of a geocoded address.
///
/// Google returns "MV62+682 Unity Plaza, Margalla View Block B D-17,
/// Islamabad" and every screen that showed it in full showed a Plus Code and an
/// ellipsis instead of a name. The name is the part a person recognises.
///
/// Shared rather than copied: the home screen had its own version, the
/// destination screen had none, and the two drifted immediately.
String shortPlaceName(String address) {
  final parts = address
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return address.trim();

  var first = parts.first;

  // Leading Plus Codes are dropped. They are precise, machine-readable, and
  // mean nothing to the person standing there.
  final code = RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\s*');
  if (code.hasMatch(first)) {
    first = first.replaceFirst(code, '').trim();
    if (first.isEmpty) first = parts.length > 1 ? parts[1] : parts.first;
  }

  return first;
}
