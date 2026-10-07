import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/money.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/tour_rent/tour_rent_repository.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../listing/my_vehicles_screen.dart';
import 'driver_home_screen.dart';

/// The driver's dashboard: the Tour & Rent home for a driver whose vehicles
/// only do tours or rent-a-car, the city-rides dashboard for everyone else.
///
/// Decided once per app session from the server, so it does not flicker
/// between the two on every rebuild.
class DriverStartScreen extends StatefulWidget {
  const DriverStartScreen({super.key});

  @override
  State<DriverStartScreen> createState() => _DriverStartScreenState();
}

class _DriverStartScreenState extends State<DriverStartScreen> {
  static bool? _tourRentOnly;

  @override
  void initState() {
    super.initState();
    if (_tourRentOnly == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
    }
  }

  Future<void> _decide() async {
    var only = false;
    try {
      final home =
          await TourRentRepository(AppControllerScope.of(context).apiClient)
              .home();
      only = home.tourRentOnly;
    } catch (_) {
      // Fall back to the ordinary dashboard.
    }
    if (!mounted) return;
    setState(() => _tourRentOnly = only);
  }

  @override
  Widget build(BuildContext context) {
    final only = _tourRentOnly;
    if (only == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return only ? const TourRentHomeScreen() : const DriverHomeScreen();
  }
}

/// Tour & Rent home (Driver mode): who booked, who is waiting, how full each
/// departure is. Bookings come in directly — nothing here to accept except a
/// waiting-list request once a place is free.
///
/// Sits inside the driver shell, which already has the bar and the drawer, so
/// there is no `Scaffold` here.
class TourRentHomeScreen extends StatefulWidget {
  const TourRentHomeScreen({super.key});

  @override
  State<TourRentHomeScreen> createState() => _TourRentHomeScreenState();
}

enum _Tab { all, tour, rent }

class _TourRentHomeScreenState extends State<TourRentHomeScreen> {
  late final TourRentRepository _repository =
      TourRentRepository(AppControllerScope.of(context).apiClient);

  TourRentHome? _home;
  String? _error;
  _Tab _tab = _Tab.all;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final home = await _repository.home();
      if (!mounted) return;
      setState(() {
        _home = home;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  bool _keep(String kind) =>
      _tab == _Tab.all ||
      (_tab == _Tab.tour && kind == 'tour') ||
      (_tab == _Tab.rent && kind == 'rent');

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(String id, Future<String> Function() action) async {
    setState(() => _busyId = id);
    try {
      _snack(await action());
      await _load();
    } on ApiException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null) {
      _snack('Customer ka number nahi mila.');
      return;
    }
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      _snack('Dialer nahi khul saka.');
    }
  }

  Future<void> _message(String? phone, String name) async {
    if (phone == null) {
      _snack('Customer ka number nahi mila.');
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final choice = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$name ko message',
              style: AppType.h3.copyWith(color: AppText.primary)),
          const SizedBox(height: 14),
          UdButton.primary(
            label: 'WhatsApp',
            icon: Icons.chat_rounded,
            onPressed: () => Navigator.pop(sheetContext, 'wa'),
          ),
          const SizedBox(height: 10),
          UdButton.outline(
            label: 'SMS',
            icon: Icons.sms_outlined,
            onPressed: () => Navigator.pop(sheetContext, 'sms'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final uri = choice == 'wa'
        ? Uri.parse('https://wa.me/$digits')
        : Uri(scheme: 'sms', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Message app nahi khul saka.');
    }
  }

  Future<void> _confirmNoShow(TourRentBooking booking) async {
    final yes = await showUdDialog<bool>(
      context: context,
      title: 'Customer nahi aaya?',
      message: '${booking.customerName} ki booking band ho jayegi aur '
          '${booking.isTour ? 'seats' : 'gaari'} khali ho jayegi — phir aap '
          'waiting list se kisi ko accept kar sakte hain.',
      actions: [
        UdButton.dark(
          label: 'Haan, nahi aaya',
          onPressed: () => Navigator.pop(context, true),
        ),
        const SizedBox(height: 8),
        UdButton.ghost(
          label: 'Wapas',
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );
    if (yes != true || !mounted) return;
    await _run(booking.id, () => _repository.noShow(booking));
  }

  Future<void> _decline(TourRentRequest request) async {
    final yes = await showUdDialog<bool>(
      context: context,
      title: 'Request mana karein?',
      message: '${request.customerName} ko bata diya jayega ke yeh request '
          'accept nahi ho saki.',
      actions: [
        UdButton.dark(
          label: 'Mana karein',
          onPressed: () => Navigator.pop(context, true),
        ),
        const SizedBox(height: 8),
        UdButton.ghost(
          label: 'Wapas',
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );
    if (yes != true || !mounted) return;
    await _run(request.id, () => _repository.decline(request));
  }

  void _openRentals() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyVehiclesScreen()),
      ).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final home = _home;
    if (home == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSizes.sidePadding),
              children: [
                UdEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Load nahi ho saka',
                  text: _error,
                  action: UdButton.outline(
                    label: 'Dobara koshish',
                    expand: false,
                    onPressed: _load,
                  ),
                ),
              ],
            );
    }

    final name = AppControllerScope.of(context).currentUserName.split(' ').first;
    final offers = home.waitlist.where((w) => _keep(w.kind)).toList();
    final bookings = home.bookings.where((b) => _keep(b.kind)).toList();
    final showDepartures = _tab != _Tab.rent && home.departures.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
        children: [
          _Header(
            name: name,
            vehicles: home.vehicles,
            wallet: home.walletBalance,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _Stat(value: '${home.newBookings}', label: 'Nayi bookings')),
              const SizedBox(width: 8),
              Expanded(
                  child: _Stat(value: '${home.waitingCount}', label: 'Waiting list')),
              const SizedBox(width: 8),
              Expanded(
                  child: _Stat(
                      value: _short(home.weekEarnings), label: 'Is hafte')),
            ],
          ),
          const SizedBox(height: 12),
          _Tabs(
            selected: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
          ),
          if (offers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Waiting list',
                style: AppType.section.copyWith(color: AppText.primary)),
            const SizedBox(height: 4),
            Text(
              'Gaari / seats book ho chuki. Agar booked customer cancel kare '
              'ya na aaye, to in mein se kisi ko accept karein.',
              style: AppType.caption.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 10),
            for (final request in offers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RequestCard(
                  request: request,
                  busy: _busyId == request.id,
                  onCall: () => _call(request.customerPhone),
                  onMessage: () =>
                      _message(request.customerPhone, request.customerName),
                  onAccept: () => _run(
                      request.id, () => _repository.accept(request)),
                  onDecline: () => _decline(request),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text('Nayi bookings — confirm ho chuki',
              style: AppType.section.copyWith(color: AppText.primary)),
          const SizedBox(height: 10),
          if (bookings.isEmpty)
            const UdEmptyState(
              icon: Icons.event_available_rounded,
              title: 'Abhi koi booking nahi',
              text: 'Customer seat, poori gaari ya rent book karega to yahan '
                  'aa jayegi — aap ko accept nahi karna.',
            )
          else
            for (final booking in bookings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BookingCard(
                  booking: booking,
                  busy: _busyId == booking.id,
                  onCall: () => _call(booking.customerPhone),
                  onMessage: () =>
                      _message(booking.customerPhone, booking.customerName),
                  onNoShow: () => _confirmNoShow(booking),
                  onOpenRentals: _openRentals,
                ),
              ),
          if (showDepartures) ...[
            const SizedBox(height: 16),
            Text('Aane wali tours — seats',
                style: AppType.section.copyWith(color: AppText.primary)),
            const SizedBox(height: 10),
            for (final departure in home.departures)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DepartureCard(departure: departure),
              ),
          ],
        ],
      ),
    );
  }

  static String _short(double value) => value >= 1000
      ? 'PKR ${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
      : Money.amount(value);
}

final _day = DateFormat('d MMM');
final _dayTime = DateFormat('d MMM, h:mm a');
final _time = DateFormat('h:mm a');

String _range(DateTime start, DateTime? end) {
  if (end == null || !end.isAfter(start)) return _day.format(start);
  if (start.month == end.month) return '${start.day}–${_day.format(end)}';
  return '${_day.format(start)} – ${_day.format(end)}';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.vehicles,
    required this.wallet,
  });

  final String name;
  final List<String> vehicles;
  final double wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadii.all(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name · Tour & Rent',
                  style: AppType.listTitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.onInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${vehicles.length} ${vehicles.length == 1 ? 'gaari' : 'gaariyan'}'
                  '${vehicles.isEmpty ? '' : ' · ${vehicles.join(', ')}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: AppColors.onInkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: AppRadii.all(10),
            ),
            child: Text(
              Money.amount(wallet),
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.h3.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onChanged});

  final _Tab selected;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(_Tab value, String label) {
      final on = value == selected;
      return Expanded(
        child: Material(
          color: on ? AppColors.background : Colors.transparent,
          borderRadius: AppRadii.all(11),
          child: InkWell(
            borderRadius: AppRadii.all(11),
            onTap: () => onChanged(value),
            child: SizedBox(
              height: 38,
              child: Center(
                child: Text(
                  label,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadii.all(14),
      ),
      child: Row(
        children: [
          tab(_Tab.all, 'Sab'),
          const SizedBox(width: 6),
          tab(_Tab.tour, 'Tour'),
          const SizedBox(width: 6),
          tab(_Tab.rent, 'Rent a car'),
        ],
      ),
    );
  }
}

/// TOUR (purple) or RENT (amber), as on the design.
class _KindChip extends StatelessWidget {
  const _KindChip({required this.tour, required this.label});

  final bool tour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: tour ? AppTint.personalWash : AppTint.warning,
        borderRadius: AppRadii.all(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppType.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: tour ? AppTint.personal : AppTint.warningText,
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(11),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(11)),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onCall,
    required this.onMessage,
    required this.onAccept,
    required this.onDecline,
  });

  final TourRentRequest request;
  final bool busy;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  String get _kind {
    final what = request.wholeVehicle
        ? 'POORI GAARI'
        : '${request.seats} ${request.seats == 1 ? 'SEAT' : 'SEATS'}';
    return '${request.isTour ? 'TOUR' : 'RENT'} · $what';
  }

  String get _line {
    final r = request;
    if (r.accepted) {
      final until = r.acceptExpiresAt;
      return 'Accept ho gaya — customer '
          '${until == null ? 'jaldi' : '${_time.format(until)} tak'} '
          'advance de kar booking pakki karega.';
    }
    if (r.free) return 'Jagah khali hai — accept kar sakte hain.';
    if (!r.isTour) {
      return 'Gaari in dinon booked hai. Booked customer na aaye to accept '
          'kar sakte hain.';
    }
    return r.wholeVehicle
        ? 'Gaari book hai. Booked customer cancel kare ya na aaye to accept '
            'karein.'
        : 'Seats full (${r.bookedSeats}/${r.totalSeats}). Seat khali ho to '
            'accept kar sakte hain.';
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    final free = r.free;
    final stateLabel = r.accepted
        ? 'ACCEPTED'
        : free
            ? 'JAGAH KHALI'
            : 'INTEZAR';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(
          color: free ? AppColors.limeLine : AppColors.border,
          width: free ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _KindChip(tour: r.isTour, label: _kind),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Money.amount(r.amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: free || r.accepted ? AppTint.success : AppColors.surfaceAlt,
                  borderRadius: AppRadii.all(8),
                ),
                child: Text(
                  stateLabel,
                  style: AppType.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: free || r.accepted
                        ? AppTint.successText
                        : AppText.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${r.customerName} · ${r.title} · ${_range(r.startsAt, r.endsAt)}',
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _line,
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 5, child: _SmallButton(label: 'Call', onTap: onCall)),
              const SizedBox(width: 8),
              Expanded(
                  flex: 5, child: _SmallButton(label: 'Message', onTap: onMessage)),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: r.accepted
                    ? const SizedBox(height: 40)
                    : Material(
                        color: free ? AppColors.brand : AppColors.surfaceAlt,
                        borderRadius: AppRadii.all(11),
                        child: InkWell(
                          borderRadius: AppRadii.all(11),
                          onTap: free && !busy ? onAccept : null,
                          child: SizedBox(
                            height: 40,
                            child: Center(
                              child: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(
                                      free ? 'Accept' : 'Accept (abhi nahi)',
                                      style: AppType.small.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: free
                                            ? AppColors.navy
                                            : AppText.disabled,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (!r.accepted)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onDecline,
                child: Text(
                  'Mana karein',
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.busy,
    required this.onCall,
    required this.onMessage,
    required this.onNoShow,
    required this.onOpenRentals,
  });

  final TourRentBooking booking;
  final bool busy;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onNoShow;
  final VoidCallback onOpenRentals;

  String get _line {
    final b = booking;
    if (b.isTour) {
      return b.wholeVehicle
          ? '${b.title} · poori gaari (${b.seats} seats)'
          : '${b.title} · ${b.seats} ${b.seats == 1 ? 'seat' : 'seats'}';
    }
    final mode = b.rentalMode == 'SelfDrive' ? 'self-drive' : 'driver ke saath';
    return '${b.vehicle} · $mode · ${b.seats} din';
  }

  String get _when => booking.isTour
      ? _dayTime.format(booking.startsAt)
      : _range(booking.startsAt, booking.endsAt);

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final initial =
        b.customerName.trim().isEmpty ? '?' : b.customerName.trim()[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: AppType.listTitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              _KindChip(
                tour: b.isTour,
                label: b.isTour
                    ? (b.wholeVehicle ? 'TOUR · POORI GAARI' : 'TOUR')
                    : 'RENT',
              ),
              SizedBox(
                width: 32,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: AppColors.caption),
                  enabled: !busy && !b.needsAccept,
                  onSelected: (_) => onNoShow(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'noShow',
                      child: Text('Customer nahi aaya'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _when,
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ),
                Text(
                  Money.amount(b.amount),
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
          ),
          if (b.needsAccept) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UdBanner(
                tone: UdTone.warn,
                icon: Icons.account_balance_wallet_rounded,
                onTap: onOpenRentals,
                child: const Text(
                  'Wallet mein commission jitne paise nahi the, is liye yeh '
                  'booking aap ke accept ka intezar kar rahi hai. Wallet '
                  'top-up karein, phir Rent requests mein accept karein.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(child: _SmallButton(label: 'Call', onTap: onCall)),
                const SizedBox(width: 8),
                Expanded(
                    child: _SmallButton(label: 'Message', onTap: onMessage)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DepartureCard extends StatelessWidget {
  const _DepartureCard({required this.departure});

  final TourRentDeparture departure;

  @override
  Widget build(BuildContext context) {
    final d = departure;
    final left = (d.totalSeats - d.bookedSeats).clamp(0, d.totalSeats);
    final share = d.totalSeats == 0 ? 0.0 : d.bookedSeats / d.totalSeats;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${d.title} · ${_day.format(d.departureAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ),
              Text(
                '${d.bookedSeats} / ${d.totalSeats}',
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppRadii.all(4),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(
                  d.full ? AppColors.warning : AppColors.limeLine),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d.full
                ? 'Full — nayi requests waiting list mein jayengi'
                : '${d.bookings} ${d.bookings == 1 ? 'booking' : 'bookings'} · '
                    '$left ${left == 1 ? 'seat' : 'seats'} baqi — seat ya poori '
                    'gaari direct book',
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ],
      ),
    );
  }
}
