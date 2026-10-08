import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/money.dart';
import '../../core/holds/hold_repository.dart';
import '../../core/listings/listing_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/tour_rent/tour_rent_repository.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../common/hold_notice.dart';
import '../listing/listing_handover_screen.dart';
import '../listing/listing_rent_calendar_screen.dart';
import '../listing/listing_rent_settings_screen.dart';
import '../listing/my_vehicles_screen.dart';
import 'driver_home_screen.dart';

/// The driver's dashboard. One vehicle does one kind of work, so a driver
/// sees the dashboard of that work: City rides (the existing dashboard), Tour
/// or Rent a car. Only a driver with vehicles in two or more kinds of work
/// gets the switch on top.
///
/// The kinds are worked out once per app session, so the screen does not
/// flicker between dashboards on every rebuild.
class DriverStartScreen extends StatefulWidget {
  const DriverStartScreen({super.key});

  @override
  State<DriverStartScreen> createState() => _DriverStartScreenState();
}

class _DriverStartScreenState extends State<DriverStartScreen> {
  static List<String>? _kinds;
  static String? _selected;

  @override
  void initState() {
    super.initState();
    if (_kinds == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
    }
  }

  Future<void> _decide() async {
    final api = AppControllerScope.of(context).apiClient;
    var kinds = <String>['city'];
    try {
      final home = await TourRentRepository(api).home();
      var tour = false;
      var rent = false;
      try {
        final listing = await ListingRepository(api).home();
        tour = listing.vehicles.any(_isTour);
        rent = listing.vehicles.any(_isRent);
      } catch (_) {
        // No listing profile: tour/rent come only from the server's count.
        tour = home.vehicles.isNotEmpty;
      }
      // A vehicle on review or suspended is not live, but its dashboard must
      // still open so the driver sees why.
      var held = <String>{};
      try {
        held = {for (final h in await HoldRepository(api).mine()) h.kind};
      } catch (_) {}
      kinds = [
        if (home.ridesVehicles > 0 || held.contains('city')) 'city',
        if (tour || held.contains('tour')) 'tour',
        if (rent || held.contains('rent')) 'rent',
      ];
      if (kinds.isEmpty) kinds = ['city'];
    } catch (_) {
      // Fall back to the ordinary dashboard.
    }
    if (!mounted) return;
    setState(() {
      _kinds = kinds;
      _selected = kinds.contains(_selected) ? _selected : kinds.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _kinds;
    if (kinds == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final selected = _selected ?? kinds.first;
    final body = selected == 'city'
        ? const DriverHomeScreen()
        : TourRentHomeScreen(kind: selected, key: ValueKey(selected));

    return Column(
      children: [
        if (kinds.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 6, AppSizes.sidePadding, 0),
            child: _Switch(
              kinds: kinds,
              selected: selected,
              onChanged: (kind) => setState(() => _selected = kind),
            ),
          ),
        // Review / suspend from the Admin: why no ride or booking comes.
        HoldNotice(
          key: ValueKey('hold-$selected'),
          kinds: {selected},
          maxHeightFactor: 0.55,
        ),
        Expanded(child: body),
      ],
    );
  }
}

bool _isTour(ListingVehicle v) =>
    v.isLive &&
    v.wantsTour &&
    (v.tourReview.status == 'Approved' || v.tourReview.status == 'None');

bool _isRent(ListingVehicle v) =>
    v.isLive &&
    v.wantsRent &&
    (v.rentReview.status == 'Approved' || v.rentReview.status == 'None');

/// Tour or Rent a car dashboard (Driver mode).
///
/// Tour: the driver's vehicles first, each with "+ Departure lagayein" and
/// both fares, then the departures and their seats, then bookings and the
/// waiting list. Rent a car: each car's next seven days, today's handovers
/// and returns, then bookings and the waiting list. Bookings come in
/// directly — nothing to accept except a waiting-list request once a place
/// is free.
///
/// Sits inside the driver shell, which already has the bar and the drawer, so
/// there is no `Scaffold` here.
class TourRentHomeScreen extends StatefulWidget {
  const TourRentHomeScreen({this.kind = 'tour', super.key});

  /// `tour` or `rent`.
  final String kind;

  @override
  State<TourRentHomeScreen> createState() => _TourRentHomeScreenState();
}

class _TourRentHomeScreenState extends State<TourRentHomeScreen> {
  late final TourRentRepository _repository =
      TourRentRepository(AppControllerScope.of(context).apiClient);
  late final ListingRepository _listing =
      ListingRepository(AppControllerScope.of(context).apiClient);
  late final RentalRepository _rentals =
      RentalRepository(AppControllerScope.of(context).apiClient);

  TourRentHome? _home;
  List<ListingVehicle> _vehicles = const [];
  List<FleetDriver> _drivers = const [];
  Map<String, List<RentCalendarDay>> _calendars = const {};
  List<RentalBooking> _ownerRentals = const [];
  String? _error;
  String? _busyId;

  /// The vehicle whose departure form is open, if any.
  String? _formFor;

  bool get _tour => widget.kind != 'rent';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final home = await _repository.home();
      var vehicles = <ListingVehicle>[];
      var drivers = <FleetDriver>[];
      try {
        final listing = await _listing.home();
        vehicles = listing.vehicles.where(_tour ? _isTour : _isRent).toList();
        drivers = listing.drivers;
      } catch (_) {
        // The cards below still show bookings and requests.
      }

      final calendars = <String, List<RentCalendarDay>>{};
      var rentals = <RentalBooking>[];
      if (!_tour) {
        final today = DateTime.now();
        final from = DateTime(today.year, today.month, today.day);
        await Future.wait([
          for (final v in vehicles)
            _listing
                .calendar(v.id, from, days: 7)
                .then((days) => calendars[v.id] = days)
                .catchError((_) => const <RentCalendarDay>[]),
        ]);
        try {
          rentals = await _rentals.ownerRentals();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _home = home;
        _vehicles = vehicles;
        _drivers = drivers;
        _calendars = calendars;
        _ownerRentals = rentals;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

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

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  void _openRentals() => _open(const MyVehiclesScreen());

  /// The departure form sent: the server checks the date, the fares and who
  /// drives, and says what is wrong in words.
  Future<bool> _postDeparture(ListingVehicle vehicle, _DepartureInput input) async {
    try {
      await _listing.saveDeparture(
        vehicle.id,
        input.date,
        from: input.from,
        to: input.to,
        time: input.time,
        durationDays: 1,
        pricePerSeat: input.perSeat,
        wholeVehiclePrice: input.whole,
        pickupPoint: input.from,
        fleetDriverId: input.driverId,
      );
      _snack('Departure lag gayi — customers ab book kar sakte hain.');
      if (mounted) setState(() => _formFor = null);
      await _load();
      return true;
    } on ListingRefused catch (error) {
      _snack(error.message);
      return false;
    } catch (error) {
      _snack('$error');
      return false;
    }
  }

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

    final kind = _tour ? 'tour' : 'rent';
    final name = AppControllerScope.of(context).currentUserName.split(' ').first;
    final offers = home.waitlist.where((w) => w.kind == kind).toList();
    final bookings = home.bookings.where((b) => b.kind == kind).toList();
    final since = DateTime.now().subtract(const Duration(days: 7));
    final newBookings =
        bookings.where((b) => b.createdAt.isAfter(since)).length;
    final week = _tour ? home.weekTour : home.weekRent;

    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final upcomingDepartures = home.departures.length;
    final outToday = _vehicles
        .where((v) => (_calendars[v.id] ?? const []).any((d) =>
            _sameDay(d.date, day0) && (d.state == 'booked' || d.state == 'pending')))
        .length;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 10, AppSizes.sidePadding, 34),
        children: [
          _Header(
            title: '$name · ${_tour ? 'Tour' : 'Rent a car'}',
            subtitle: _tour
                ? '${_vehicles.length} ${_vehicles.length == 1 ? 'gaari' : 'gaariyan'}'
                    ' · $upcomingDepartures departures lagi hain'
                : '${_vehicles.length} ${_vehicles.length == 1 ? 'gaari' : 'gaariyan'}'
                    ' · $outToday aaj bahir',
            wallet: home.walletBalance,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _Stat(value: '$newBookings', label: 'Nayi bookings')),
              const SizedBox(width: 8),
              Expanded(
                  child: _Stat(value: '${offers.length}', label: 'Waiting list')),
              const SizedBox(width: 8),
              Expanded(child: _Stat(value: _short(week), label: 'Is hafte')),
            ],
          ),
          const SizedBox(height: 16),
          Text(_tour ? 'Meri gaariyan' : 'Meri gaariyan — agle 7 din',
              style: AppType.section.copyWith(color: AppText.primary)),
          const SizedBox(height: 10),
          if (_vehicles.isEmpty)
            UdEmptyState(
              icon: Icons.directions_car_outlined,
              title: 'Abhi koi live gaari nahi',
              text: 'Gaari approve ho jaye to yahan aayegi.',
              action: UdButton.outline(
                label: 'Meri gaariyan kholein',
                expand: false,
                onPressed: _openRentals,
              ),
            )
          else if (_tour)
            for (final vehicle in _vehicles) ...[
              _TourVehicleCard(
                vehicle: vehicle,
                next: _nextDeparture(home, vehicle),
                onAdd: () => setState(() =>
                    _formFor = _formFor == vehicle.id ? null : vehicle.id),
              ),
              if (_formFor == vehicle.id) ...[
                const SizedBox(height: 10),
                _DepartureForm(
                  vehicle: vehicle,
                  drivers: _drivers
                      .where((d) => d.status == 'Approved' && d.licenceValid)
                      .toList(),
                  onCancel: () => setState(() => _formFor = null),
                  onSubmit: (input) => _postDeparture(vehicle, input),
                ),
              ],
              const SizedBox(height: 10),
            ]
          else ...[
            for (final vehicle in _vehicles) ...[
              _RentVehicleCard(
                vehicle: vehicle,
                days: _calendars[vehicle.id] ?? const [],
                today: day0,
                onBlock: () => _open(ListingRentCalendarScreen(vehicle: vehicle)),
                onRates: () => _open(ListingRentSettingsScreen(vehicle: vehicle)),
              ),
              const SizedBox(height: 10),
            ],
            const _Legend(),
          ],
          if (_tour && home.departures.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Aane wali departures — seats',
                style: AppType.section.copyWith(color: AppText.primary)),
            const SizedBox(height: 10),
            for (final departure in home.departures)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DepartureCard(departure: departure),
              ),
          ],
          if (!_tour) ..._todayWork(day0),
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
            UdEmptyState(
              icon: Icons.event_available_rounded,
              title: 'Abhi koi booking nahi',
              text: _tour
                  ? 'Customer seat ya poori gaari book karega to yahan aa '
                      'jayegi — aap ko accept nahi karna.'
                  : 'Customer gaari book karega to yahan aa jayegi — aap ko '
                      'accept nahi karna.',
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
        ],
      ),
    );
  }

  /// Rent: cars to hand over today or tomorrow, and cars due back today.
  List<Widget> _todayWork(DateTime day0) {
    final tomorrow = day0.add(const Duration(days: 1));
    final work = <(RentalBooking, String)>[
      for (final b in _ownerRentals)
        if (b.status == 'Confirmed' &&
            !b.startDate.isBefore(day0) &&
            !b.startDate.isAfter(tomorrow))
          (b, 'handover')
        else if (b.status == 'HandedOver' && !b.endDate.isAfter(day0))
          (b, 'return'),
    ];
    if (work.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text('Aaj ka kaam',
          style: AppType.section.copyWith(color: AppText.primary)),
      const SizedBox(height: 10),
      for (final (booking, phase) in work)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TodayCard(
            booking: booking,
            phase: phase,
            onCall: () => _call(booking.counterpartPhone),
            onMessage: () =>
                _message(booking.counterpartPhone, booking.counterpartName),
            onAction: () =>
                _open(ListingHandoverScreen(booking: booking, phase: phase)),
          ),
        ),
    ];
  }

  String _nextDeparture(TourRentHome home, ListingVehicle vehicle) {
    for (final d in home.departures) {
      if (d.vehicleId == vehicle.id) {
        return 'Agli: ${d.title} · ${_day.format(d.departureAt)} '
            '(${d.bookedSeats}/${d.totalSeats}${d.full ? ' full' : ''})';
      }
    }
    return 'Koi departure nahi lagi';
  }

  static String _short(double value) => value >= 1000
      ? 'PKR ${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
      : Money.amount(value);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
    required this.title,
    required this.subtitle,
    required this.wallet,
  });

  final String title;
  final String subtitle;
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
                  title,
                  style: AppType.listTitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.onInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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

/// City rides / Tour / Rent a car — only for a driver with vehicles in two or
/// more kinds of work.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.kinds,
    required this.selected,
    required this.onChanged,
  });

  final List<String> kinds;
  final String selected;
  final ValueChanged<String> onChanged;

  static String _label(String kind) => switch (kind) {
        'city' => 'City rides',
        'tour' => 'Tour',
        _ => 'Rent a car',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadii.all(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < kinds.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Material(
                color: kinds[i] == selected
                    ? AppColors.background
                    : Colors.transparent,
                borderRadius: AppRadii.all(11),
                child: InkWell(
                  borderRadius: AppRadii.all(11),
                  onTap: () => onChanged(kinds[i]),
                  child: SizedBox(
                    height: 38,
                    child: Center(
                      child: Text(
                        _label(kinds[i]),
                        style: AppType.small.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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

/// The vehicle's own photo, or a plain tile when there is none.
class _VehiclePhoto extends StatelessWidget {
  const _VehiclePhoto({required this.url, this.width = 96, this.height = 72});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final link = ApiConfig.absoluteUrl(url?.trim());
    final Widget fallback = Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_rounded,
          size: 32, color: AppColors.navy),
    );
    return ClipRRect(
      borderRadius: AppRadii.all(12),
      child: SizedBox(
        width: width,
        height: height,
        child: link.isEmpty
            ? fallback
            : Image.network(
                link,
                fit: BoxFit.cover,
                cacheWidth: 288,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

String _vehicleTitle(ListingVehicle v) {
  final name = v.name.trim().isEmpty ? '${v.make} ${v.model}'.trim() : v.name.trim();
  return v.registrationNumber.trim().isEmpty
      ? name
      : '$name · ${v.registrationNumber.trim()}';
}

/// Tour: one vehicle and the button that opens its departure form.
class _TourVehicleCard extends StatelessWidget {
  const _TourVehicleCard({
    required this.vehicle,
    required this.next,
    required this.onAdd,
  });

  final ListingVehicle vehicle;
  final String next;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final features = [
      '${vehicle.seats} seats',
      if (vehicle.isFourByFour) '4x4',
      if (vehicle.kit.airConditioning) 'AC',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(10),
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
              _VehiclePhoto(url: vehicle.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vehicleTitle(vehicle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(features,
                        style: AppType.caption.copyWith(color: AppText.secondary)),
                    const SizedBox(height: 3),
                    Text(
                      next,
                      maxLines: 2,
                      style: AppType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          UdButton.primary(
            label: '+ Departure lagayein',
            size: UdButtonSize.small,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// What the departure form sends.
class _DepartureInput {
  const _DepartureInput({
    required this.from,
    required this.to,
    required this.date,
    required this.time,
    required this.perSeat,
    required this.whole,
    required this.driverId,
  });

  final String from;
  final String to;
  final DateTime date;

  /// `HH:mm`.
  final String time;
  final double perSeat;
  final double whole;
  final String? driverId;
}

/// "+ Departure lagayein": where, when, and both fares — per seat and the
/// whole vehicle. Every vehicle can sell single seats; on a car of five
/// seats or fewer the seat fare is optional (blank = whole vehicle only).
class _DepartureForm extends StatefulWidget {
  const _DepartureForm({
    required this.vehicle,
    required this.drivers,
    required this.onCancel,
    required this.onSubmit,
  });

  final ListingVehicle vehicle;
  final List<FleetDriver> drivers;
  final VoidCallback onCancel;
  final Future<bool> Function(_DepartureInput input) onSubmit;

  @override
  State<_DepartureForm> createState() => _DepartureFormState();
}

class _DepartureFormState extends State<_DepartureForm> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _perSeat = TextEditingController();
  final _whole = TextEditingController();
  late DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  String? _driverId;
  bool _saving = false;

  /// A big vehicle must give a seat fare; a small car may leave it blank.
  bool get _seatRequired => widget.vehicle.seats > 5;

  @override
  void initState() {
    super.initState();
    _from.text = widget.vehicle.pickupPoint ?? '';
    if (widget.drivers.length == 1) _driverId = widget.drivers.first.id;
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _perSeat.dispose();
    _whole.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
      initialDate: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  static double _amount(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  Future<void> _submit() async {
    final whole = _amount(_whole);
    final perSeat = _amount(_perSeat);
    String? problem;
    if (_from.text.trim().length < 2) {
      problem = 'Kahan se — likhein.';
    } else if (_to.text.trim().length < 2) {
      problem = 'Kahan tak — likhein.';
    } else if (whole <= 0) {
      problem = 'Poori gaari ka kiraya likhein.';
    } else if (_seatRequired && perSeat <= 0) {
      problem = 'Per seat kiraya likhein.';
    } else if (perSeat > whole) {
      problem = 'Seat ka kiraya poori gaari se zyada nahi ho sakta.';
    }
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    setState(() => _saving = true);
    await widget.onSubmit(_DepartureInput(
      from: _from.text.trim(),
      to: _to.text.trim(),
      date: _date,
      time: '${_time.hour.toString().padLeft(2, '0')}:'
          '${_time.minute.toString().padLeft(2, '0')}',
      perSeat: perSeat,
      whole: whole,
      driverId: _driverId,
    ));
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.caption.copyWith(color: AppText.secondary)),
          const SizedBox(height: 4),
          child,
        ],
      );

  InputDecoration get _box => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(10),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(10),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
      );

  Widget _picker(String text, VoidCallback onTap) => Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(10),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(10)),
          child: Container(
            height: 44,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(text,
                style: AppType.body.copyWith(color: AppText.primary)),
          ),
        ),
      );

  Widget _fare(String label, TextEditingController c, Color wash, Color ink) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: AppRadii.all(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppType.caption
                    .copyWith(fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 4),
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: _box,
              style: AppType.body.copyWith(
                  fontWeight: FontWeight.w800, color: AppText.primary),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('h:mm a')
        .format(DateTime(2000, 1, 1, _time.hour, _time.minute));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.navy, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Departure — ${_vehicleTitle(widget.vehicle)}',
              style: AppType.listTitle.copyWith(
                  fontWeight: FontWeight.w800, color: AppText.primary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _field('Kahan se',
                      TextField(controller: _from, decoration: _box))),
              const SizedBox(width: 8),
              Expanded(
                  child: _field('Kahan tak',
                      TextField(controller: _to, decoration: _box))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _field('Tareekh',
                      _picker(DateFormat('d MMM, EEE').format(_date), _pickDate))),
              const SizedBox(width: 8),
              Expanded(child: _field('Waqt', _picker(timeText, _pickTime))),
            ],
          ),
          if (widget.drivers.length > 1) ...[
            const SizedBox(height: 8),
            _field(
              'Kaun chalayega',
              DropdownButtonFormField<String>(
                value: _driverId,
                isExpanded: true,
                decoration: _box,
                hint: const Text('Driver chunein'),
                items: [
                  for (final d in widget.drivers)
                    DropdownMenuItem(
                      value: d.id,
                      child: Text(d.isOwner ? '${d.name} (main khud)' : d.name),
                    ),
                ],
                onChanged: (value) => setState(() => _driverId = value),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(_seatRequired ? 'Kiraya — dono dein' : 'Kiraya',
              style: AppType.small.copyWith(
                  fontWeight: FontWeight.w800, color: AppText.primary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _fare(
                    _seatRequired ? 'Per seat (PKR)' : 'Per seat (PKR) · optional',
                    _perSeat,
                    AppTint.success,
                    AppTint.successText),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _fare('Poori gaari (PKR)', _whole, AppTint.personalWash,
                    AppTint.personal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _seatRequired
                ? 'Customer seat ya poori gaari direct book karega. Seats full '
                    'hon to nayi requests waiting list mein jayengi.'
                : 'Per seat likhein to customer ${widget.vehicle.seats} mein se '
                    'single seat bhi book kar sakega. Khali chhorein to sirf '
                    'poori gaari.',
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: UdButton.outline(
                  label: 'Wapas',
                  size: UdButtonSize.small,
                  onPressed: _saving ? null : widget.onCancel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: UdButton.dark(
                  label: 'Departure post karein',
                  size: UdButtonSize.small,
                  busy: _saving,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rent: one car, its rates, today's state and the next seven days.
class _RentVehicleCard extends StatelessWidget {
  const _RentVehicleCard({
    required this.vehicle,
    required this.days,
    required this.today,
    required this.onBlock,
    required this.onRates,
  });

  final ListingVehicle vehicle;
  final List<RentCalendarDay> days;
  final DateTime today;
  final VoidCallback onBlock;
  final VoidCallback onRates;

  static bool _booked(String state) => state == 'booked' || state == 'pending';
  static bool _closed(String state) => state == 'blocked' || state == 'tour';

  @override
  Widget build(BuildContext context) {
    final rates = [
      if ((vehicle.withDriverDaily ?? 0) > 0)
        'Driver ke saath ${Money.plain(vehicle.withDriverDaily!)}',
      if ((vehicle.selfDriveDaily ?? 0) > 0)
        'Self ${Money.plain(vehicle.selfDriveDaily!)}',
    ].join(' · ');
    String? todayState;
    for (final d in days) {
      if (_sameDay(d.date, today)) todayState = d.state;
    }
    final out = todayState != null && _booked(todayState);
    final week = days.take(7).toList();

    return Container(
      padding: const EdgeInsets.all(10),
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
              _VehiclePhoto(url: vehicle.photoUrl, width: 84, height: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vehicleTitle(vehicle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.listTitle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rates.isEmpty ? 'Kiraya set nahi' : '$rates / din',
                      style: AppType.caption.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: out ? AppTint.warning : AppTint.success,
                  borderRadius: AppRadii.all(8),
                ),
                child: Text(
                  out ? 'AAJ BAHIR' : 'KHALI',
                  style: AppType.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: out ? AppTint.warningText : AppTint.successText,
                  ),
                ),
              ),
            ],
          ),
          if (week.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < week.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _DayCell(day: week[i])),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SmallButton(label: 'Din band karein', onTap: onBlock)),
              const SizedBox(width: 8),
              Expanded(child: _SmallButton(label: 'Kiraya badlein', onTap: onRates)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day});

  final RentCalendarDay day;

  @override
  Widget build(BuildContext context) {
    final booked = _RentVehicleCard._booked(day.state);
    final closed = _RentVehicleCard._closed(day.state);
    final (Color wash, Color line, Color ink) = booked
        ? (AppTint.warning, AppTint.warningBorder, AppTint.warningText)
        : closed
            ? (AppColors.surfaceAlt, AppColors.borderStrong, AppText.secondary)
            : (AppTint.success, AppColors.limeLine, AppTint.successText);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: AppRadii.all(8),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Text(DateFormat('E').format(day.date).substring(0, 2),
              style: AppType.caption.copyWith(
                  fontSize: 10, fontWeight: FontWeight.w700, color: ink)),
          Text('${day.date.day}',
              style: AppType.small
                  .copyWith(fontWeight: FontWeight.w800, color: ink)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color wash, Color line, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: wash,
                borderRadius: AppRadii.all(3),
                border: Border.all(color: line),
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: AppType.caption.copyWith(color: AppText.secondary)),
          ],
        );
    return Wrap(
      spacing: 14,
      children: [
        item(AppTint.success, AppColors.limeLine, 'Khali'),
        item(AppTint.warning, AppTint.warningBorder, 'Booked'),
        item(AppColors.surfaceAlt, AppColors.borderStrong, 'Band'),
      ],
    );
  }
}

/// Rent: a car to hand over, or one due back.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.booking,
    required this.phase,
    required this.onCall,
    required this.onMessage,
    required this.onAction,
  });

  final RentalBooking booking;

  /// `handover` or `return`.
  final String phase;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final name = b.counterpartName.trim().isEmpty ? 'Customer' : b.counterpartName.trim();
    final line = phase == 'handover'
        ? '${b.vehicleName} · ${_day.format(b.startDate)} handover'
        : '${b.vehicleName} · wapsi ${_day.format(b.endDate)}';

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
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  name[0].toUpperCase(),
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
                    Text(name,
                        style: AppType.listTitle.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppText.primary)),
                    const SizedBox(height: 2),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption
                            .copyWith(color: AppText.secondary)),
                  ],
                ),
              ),
              Text(Money.amount(b.subtotal),
                  style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800, color: AppText.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 5, child: _SmallButton(label: 'Call', onTap: onCall)),
              const SizedBox(width: 8),
              Expanded(
                  flex: 5,
                  child: _SmallButton(label: 'Message', onTap: onMessage)),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: UdButton.dark(
                  label: phase == 'handover' ? 'Handover' : 'Gaari wapas li',
                  size: UdButtonSize.small,
                  onPressed: onAction,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
