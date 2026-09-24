import 'package:intl/intl.dart';

/// One way to print an amount of money.
///
/// The app had three in a single screen — `NumberFormat('#,###')`, a
/// hand-written digit grouper, and a bare `'PKR ${value.round()}'` — plus
/// `NumberFormat('#,##0')` and `NumberFormat.decimalPattern()` elsewhere. They
/// disagree in two ways that reach the customer:
///
///  * `'#,###'` formats zero as an EMPTY STRING, so a fully paid booking showed
///    "PKR " with nothing after it.
///  * some sites print the currency and some do not, so the same number appears
///    twice on one screen with and without its unit.
///
/// Both are fixed by going through here. Existing call sites are being moved
/// over as their screens are touched rather than in one sweep.
class Money {
  const Money._();

  static final NumberFormat _grouped = NumberFormat('#,##0');

  /// "12,500" — no currency. For a column that carries its unit in the header.
  static String plain(num value) => _grouped.format(value);

  /// "PKR 12,500". The default for anything a customer reads as a price.
  ///
  /// Named `amount` rather than `format` on purpose: `format` is what every
  /// DateFormat and NumberFormat instance in the app is called with, and a
  /// static of the same name makes both unreadable at the call site.
  static String amount(num value, {String currency = 'PKR'}) =>
      '$currency ${_grouped.format(value)}';

  /// "PKR 12,500" or a dash when there is genuinely no amount.
  ///
  /// For values that may legitimately be absent. An em-dash says "not
  /// applicable"; a zero says "free", and the two are not the same promise.
  static String orDash(num? value, {String currency = 'PKR'}) =>
      value == null ? '—' : amount(value, currency: currency);
}
