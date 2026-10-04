import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

/// What the customer is looking for: where, which nights, how many.
class HotelQuery {
  const HotelQuery({
    required this.query,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.rooms,
  });

  final String query;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final int rooms;

  int get nights => checkOut.difference(checkIn).inDays;

  HotelQuery copyWith({
    String? query,
    DateTime? checkIn,
    DateTime? checkOut,
    int? guests,
    int? rooms,
  }) =>
      HotelQuery(
        query: query ?? this.query,
        checkIn: checkIn ?? this.checkIn,
        checkOut: checkOut ?? this.checkOut,
        guests: guests ?? this.guests,
        rooms: rooms ?? this.rooms,
      );

  /// "Mon 5 – Wed 7 Oct · 2 guests · 1 room"
  String get summary =>
      '${hotelRange(checkIn, checkOut)} · $guests '
      '${guests == 1 ? 'guest' : 'guests'} · $rooms '
      '${rooms == 1 ? 'room' : 'rooms'}';
}

DateTime hotelDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String hotelDate(DateTime value) => DateFormat('EEE d MMM').format(value);

String hotelRange(DateTime from, DateTime to) {
  final sameMonth = from.month == to.month && from.year == to.year;
  return sameMonth
      ? '${DateFormat('EEE d').format(from)} – ${DateFormat('EEE d MMM').format(to)}'
      : '${hotelDate(from)} – ${hotelDate(to)}';
}

/// "14:00" → "2:00 PM". Anything unreadable is shown as given.
String hotelTimeLabel(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return 'Not given';
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return hhmm;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
}

/// The owner's photograph, or a plain tile with a building on it.
class HotelPhoto extends StatelessWidget {
  const HotelPhoto({
    required this.url,
    this.width,
    this.height,
    this.radius = 18,
    this.iconSize = 44,
    super.key,
  });

  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final link = ApiConfig.absoluteUrl(url?.trim());
    final Widget fallback = Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(Icons.apartment_rounded,
          size: iconSize, color: AppColors.navy),
    );
    final Widget image = link.isEmpty
        ? fallback
        : Image.network(
            link,
            fit: BoxFit.cover,
            cacheWidth: 720,
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : fallback,
          );
    return ClipRRect(
      borderRadius: AppRadii.all(radius),
      child: SizedBox(width: width, height: height, child: image),
    );
  }
}

/// Opens the dialer on the hotel's number.
Future<void> callHotel(BuildContext context, String phone) async {
  final number = phone.trim();
  if (number.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This hotel has not added a phone number.')),
    );
    return;
  }
  final opened = await launchUrl(Uri(scheme: 'tel', path: number));
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the dialer.')),
    );
  }
}

/// Hands the drive to the phone's own Google Maps app.
///
/// Free: it is the customer's Maps app doing the routing, not a Routes call
/// on our key.
Future<void> navigateToHotel(
  BuildContext context,
  double latitude,
  double longitude,
) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=$latitude,$longitude&travelmode=driving',
  );
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open directions.')),
    );
  }
}

/// Small grey label used on cards: "Overline".
TextStyle hotelOverline() => AppType.caption.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: .3,
      color: AppText.secondary,
    );

/// A big lime action, 64px tall — the one thing to press on a screen.
class HotelPrimaryButton extends StatelessWidget {
  const HotelPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Material(
      color: enabled ? AppColors.brand : AppColors.surfaceAlt,
      borderRadius: AppRadii.all(18),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: AppRadii.all(18),
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.navy,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 21,
                    color: enabled ? AppColors.navy : AppText.disabled),
              if (busy || icon != null) const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.button.copyWith(
                    fontWeight: FontWeight.w800,
                    color: enabled ? AppColors.navy : AppText.disabled,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain outlined action, 52px — "Call hotel", "My stays".
class HotelOutlineButton extends StatelessWidget {
  const HotelOutlineButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(16),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.navy),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square white back button for screens without a top bar.
class HotelBackButton extends StatelessWidget {
  const HotelBackButton({this.onTap, this.dark = false, super.key});

  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: dark ? AppColors.navyLine : AppColors.background,
        borderRadius: AppRadii.all(14),
        child: InkWell(
          onTap: onTap ?? () => Navigator.maybePop(context),
          borderRadius: AppRadii.all(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.chevron_left_rounded,
                size: 26, color: dark ? AppText.onInk : AppColors.navy),
          ),
        ),
      ),
    );
  }
}
