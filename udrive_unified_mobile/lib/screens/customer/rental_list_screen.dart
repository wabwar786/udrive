import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/network/api_config.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/demo_tag.dart';
import '../../core/widgets/ud_kit.dart';
import 'rental_booking_screen.dart';
import 'rental_waiting_screen.dart';

/// Car rental — every car on offer, as a list.
///
/// The same shape as Tours: the list takes the screen, With driver / Self drive
/// sits on top because it changes the price on every card, and the dates are
/// asked in the footer. Picking dates reloads the list from the server, so a
/// car already out that week is not on screen at all.
class RentalListScreen extends StatefulWidget {
  const RentalListScreen({this.fourByFour = false, super.key});

  /// Opened from Explore for a place that needs a 4x4: the list starts on
  /// the 4x4 filter.
  final bool fourByFour;

  @override
  State<RentalListScreen> createState() => _RentalListScreenState();
}

enum _RentCategory { all, car, fourByFour, van }

class _RentalListScreenState extends State<RentalListScreen> {
  late final RentalRepository _repository =
      RentalRepository(AppControllerScope.of(context).apiClient);

  List<RentalVehicle> _vehicles = const [];
  DateTimeRange? _dates;
  bool _loading = true;
  String? _error;

  /// 'WithDriver' or 'SelfDrive' — the same strings the booking uses.
  String _mode = 'WithDriver';
  late _RentCategory _category =
      widget.fourByFour ? _RentCategory.fourByFour : _RentCategory.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = await _repository.search(
        from: _dates?.start,
        to: _dates?.end,
      );
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
      initialDateRange: _dates,
      helpText: _t('When do you need the car?', 'گاڑی کب چاہیے؟'),
    );
    if (picked == null || !mounted) return;
    setState(() => _dates = picked);
    await _load();
  }

  bool _offersMode(RentalVehicle v) =>
      _mode == 'WithDriver' ? v.offersWithDriver : v.offersSelfDrive;

  bool _inCategory(RentalVehicle v) {
    final category = v.category.trim().toLowerCase();
    return switch (_category) {
      _RentCategory.all => true,
      _RentCategory.car => category == 'car' && !v.isFourByFour,
      _RentCategory.fourByFour => v.isFourByFour,
      _RentCategory.van =>
        category == 'hiace' || category == 'coster' || category == 'coaster',
    };
  }

  List<RentalVehicle> get _shown => _vehicles
      .where(_offersMode)
      .where(_inCategory)
      .toList(growable: false);

  String _categoryLabel(_RentCategory value) => switch (value) {
        _RentCategory.all => _t('All', 'سب'),
        _RentCategory.car => _t('Car', 'کار'),
        _RentCategory.fourByFour => _t('4x4 / Jeep', '4x4 / جیپ'),
        _RentCategory.van => _t('Hiace / Coaster', 'ہائی ایس / کوسٹر'),
      };

  Future<void> _open(RentalVehicle vehicle) async {
    final dates = _dates;
    if (vehicle.bookedOnDates && dates != null) {
      await _askWaitlist(vehicle, dates);
      return;
    }
    final booked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RentalBookingScreen(
          vehicle: vehicle,
          dates: _dates,
          mode: _mode,
        ),
      ),
    );
    if (!mounted) return;
    if (booked == true) {
      await _openMine();
      if (mounted) await _load();
    }
  }

  /// The car is taken on these dates: say so plainly, and offer a
  /// waiting-list request instead of a booking.
  Future<void> _askWaitlist(RentalVehicle vehicle, DateTimeRange dates) async {
    final rate = (_mode == 'WithDriver'
            ? vehicle.withDriverDaily
            : vehicle.selfDriveDaily) ??
        vehicle.fromDaily;
    final send = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => _BookedSheet(
        vehicle: vehicle,
        dates: '${_day(dates.start)} — ${_day(dates.end)}',
        total: Money.amount(rate * _days(dates)),
        onSend: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (send != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.joinWaitlist(
        vehicleId: vehicle.vehicleId,
        from: dates.start,
        to: dates.end,
        mode: _mode,
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Request bhej di. Driver accept kare to aap ko '
            'notification aayegi.'),
      ));
    } on RentalRefused catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openMine() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const _MyRentalsScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final dates = _dates;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Column(
            children: [
              _header(),
              Expanded(child: _body(shown)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _RentFooter(
              title: dates == null
                  ? _t('When do you need it?', 'گاڑی کب چاہیے؟')
                  : '${_day(dates.start)} — ${_day(dates.end)}',
              subtitle: dates == null
                  ? (_mode == 'WithDriver'
                      ? _t('With driver · any dates',
                          'ڈرائیور کے ساتھ · کوئی بھی تاریخ')
                      : _t('Self drive · any dates',
                          'خود چلائیں · کوئی بھی تاریخ'))
                  : _t('${_days(dates)} day(s)', '${_days(dates)} دن'),
              action: dates == null
                  ? _t('Pick dates', 'تاریخ چنیں')
                  : _t('Change', 'بدلیں'),
              onTap: _pickDates,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _OutlineSquare(
                    icon: Icons.chevron_left_rounded,
                    label: _t('Back', 'واپس'),
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('Car rental', 'کرائے پر گاڑی'),
                      style: AppType.h2.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  Material(
                    color: AppColors.surfaceAlt,
                    borderRadius: AppRadii.all(12),
                    child: InkWell(
                      onTap: _openMine,
                      borderRadius: AppRadii.all(12),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_rounded,
                                size: 16, color: AppColors.navy),
                            const SizedBox(width: 6),
                            Text(
                              _t('My rentals', 'میری بکنگ'),
                              style: AppType.small.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppText.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ModeToggle(
                value: _mode,
                withDriver: _t('With driver', 'ڈرائیور کے ساتھ'),
                selfDrive: _t('Self drive', 'خود چلائیں'),
                onChanged: (value) => setState(() => _mode = value),
              ),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: _RentCategory.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final value = _RentCategory.values[index];
                    return _FilterChip(
                      label: _categoryLabel(value),
                      selected: value == _category,
                      onTap: () => setState(() => _category = value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<RentalVehicle> shown) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 160),
        children: [
          UdEmptyState(
            icon: Icons.cloud_off_rounded,
            tone: UdTone.err,
            title: _t('Could not load cars', 'گاڑیاں نہیں آ سکیں'),
            text: _error,
            action: UdButton.outline(
              label: _t('Try again', 'دوبارہ کوشش'),
              icon: Icons.refresh_rounded,
              expand: false,
              onPressed: _load,
            ),
          ),
        ],
      );
    }

    final count = shown.length;
    final label = _mode == 'WithDriver'
        ? _t('$count vehicles · driver included',
            '$count گاڑیاں · ڈرائیور شامل')
        : _t('$count vehicles · you drive · licence needed',
            '$count گاڑیاں · آپ چلائیں · لائسنس ضروری');

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 150),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              label,
              style: AppType.small.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppText.secondary,
              ),
            ),
          ),
          if (shown.isEmpty)
            UdEmptyState(
              icon: Icons.no_transfer_rounded,
              title: _dates == null
                  ? _t('No cars here yet', 'یہاں ابھی کوئی گاڑی نہیں')
                  : _t('Nothing free for those dates',
                      'ان تاریخوں میں کچھ خالی نہیں'),
              text: _t(
                'Try the other option above, another filter, or different '
                'dates.',
                'اوپر دوسرا آپشن، کوئی اور فلٹر یا دوسری تاریخیں آزمائیں۔',
              ),
              action: _dates == null
                  ? null
                  : UdButton.outline(
                      label: _t('Clear dates', 'تاریخ ہٹائیں'),
                      expand: false,
                      onPressed: () {
                        setState(() => _dates = null);
                        _load();
                      },
                    ),
            )
          else
            for (final vehicle in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RentCard(
                  vehicle: vehicle,
                  mode: _mode,
                  t: _t,
                  onTap: () => _open(vehicle),
                ),
              ),
        ],
      ),
    );
  }

  static int _days(DateTimeRange range) =>
      range.end.difference(range.start).inDays + 1;

  static String _day(DateTime value) =>
      '${value.day} ${_rentMonths[value.month - 1]}';
}

const _rentMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _rentDay(DateTime value) =>
    '${value.day} ${_rentMonths[value.month - 1]}';

/// With driver | Self drive.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.value,
    required this.withDriver,
    required this.selfDrive,
    required this.onChanged,
  });

  final String value;
  final String withDriver;
  final String selfDrive;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String id, String label) {
      final on = value == id;
      return Expanded(
        child: Material(
          color: on ? AppColors.background : Colors.transparent,
          borderRadius: AppRadii.all(11),
          elevation: 0,
          child: InkWell(
            onTap: () => onChanged(id),
            borderRadius: AppRadii.all(11),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: on
                  ? BoxDecoration(
                      borderRadius: AppRadii.all(11),
                      boxShadow: AppShadows.card,
                    )
                  : null,
              child: Text(
                label,
                style: AppType.small.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
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
          option('WithDriver', withDriver),
          const SizedBox(width: 4),
          option('SelfDrive', selfDrive),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(12),
        side: BorderSide(
          color: selected ? AppColors.navy : AppColors.border,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: AppType.small.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppText.onInk : AppText.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineSquare extends StatelessWidget {
  const _OutlineSquare({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(14),
          side: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder:
              RoundedRectangleBorder(borderRadius: AppRadii.all(14)),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 26, color: AppColors.navy),
          ),
        ),
      ),
    );
  }
}

/// One car, compact enough for four on a screen.
class _RentCard extends StatelessWidget {
  const _RentCard({
    required this.vehicle,
    required this.mode,
    required this.t,
    required this.onTap,
  });

  final RentalVehicle vehicle;
  final String mode;
  final String Function(String, String) t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final rate = (mode == 'WithDriver' ? v.withDriverDaily : v.selfDriveDaily) ??
        v.fromDaily;
    final minDays = v.minimumDays > 1;
    // Short, so they sit side by side on one line instead of each taking the
    // card's full width.
    final features = <(IconData?, String)>[
      (Icons.person_rounded, '${v.passengerCapacity}'),
      if (v.luggageCapacity > 0) (Icons.luggage_rounded, '${v.luggageCapacity}'),
      if (v.hasAirConditioning) (Icons.ac_unit_rounded, 'AC'),
      if (v.isFourByFour) (null, '4x4'),
      if (v.kmPerDay != null) (null, t('${v.kmPerDay} km/din', '${v.kmPerDay} کلومیٹر/دن')),
    ];
    final sub = [
      v.colour,
      if ((v.pickupPoint ?? '').trim().isNotEmpty) v.pickupPoint!.trim(),
      v.ownerName,
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The photo, with the "from 1 day" badge on it rather than in a
              // separate block under it.
              SizedBox(
                width: 112,
                height: 92,
                child: Stack(
                  children: [
                    _RentPhoto(url: v.photoUrl, width: 112, height: 92),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: v.bookedOnDates
                              ? AppTint.warning
                              : minDays
                                  ? AppColors.surfaceAlt
                                  : AppColors.brandWash,
                          borderRadius: AppRadii.all(7),
                        ),
                        child: Text(
                          v.bookedOnDates
                              ? 'Book ho chuki'
                              : minDays
                                  ? t('Min ${v.minimumDays} din',
                                      'کم از کم ${v.minimumDays} دن')
                                  : t('1 din se', 'ایک دن سے'),
                          maxLines: 1,
                          style: AppType.caption.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: v.bookedOnDates
                                ? AppTint.warningText
                                : minDays
                                    ? AppText.primary
                                    : AppColors.brandInk,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            v.year > 0 ? '${v.name} ${v.year}' : v.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        if (v.isDemo) ...[
                          const SizedBox(width: 6),
                          const DemoTag(),
                        ],
                        const SizedBox(width: 6),
                        if (v.ownerRating > 0) ...[
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.brandInk),
                          const SizedBox(width: 2),
                          Text(
                            v.ownerRating.toStringAsFixed(1),
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ] else
                          const NewRatingTag(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppText.secondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final (icon, text) in features)
                          // No alignment on this Container: with one it grows
                          // to the full width the Wrap allows, which is what
                          // put every chip on a line of its own.
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: AppRadii.all(7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (icon != null) ...[
                                  Icon(icon, size: 12, color: AppText.secondary),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  text,
                                  style: AppType.caption.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppText.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: Money.amount(rate),
                                  style: AppType.listTitle.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: t(' / din', ' / دن'),
                                  style: AppType.caption.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppText.secondary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: AppColors.navy,
                          borderRadius: AppRadii.all(11),
                          child: InkWell(
                            onTap: onTap,
                            borderRadius: AppRadii.all(11),
                            child: Container(
                              height: 34,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              child: Text(
                                v.bookedOnDates ? 'Request' : t('Rent', 'کرایہ'),
                                style: AppType.small.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.onInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The owner's photograph of the car, or a plain tile when it will not load.
class _RentPhoto extends StatelessWidget {
  const _RentPhoto({
    required this.url,
    required this.width,
    required this.height,
  });

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final link = ApiConfig.absoluteUrl(url);
    final Widget fallback = Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_rounded,
          size: 40, color: AppColors.navy),
    );
    return ClipRRect(
      borderRadius: AppRadii.all(13),
      child: SizedBox(
        width: width,
        height: height,
        child: link.isEmpty
            ? fallback
            : Image.network(
                link,
                fit: BoxFit.cover,
                cacheWidth: 320,
                errorBuilder: (_, __, ___) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}

/// "When do you need it?", pinned to the bottom.
class _RentFooter extends StatelessWidget {
  const _RentFooter({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppShadows.floating,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: AppRadii.all(3),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: AppColors.navy,
              borderRadius: AppRadii.all(18),
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadii.all(18),
                child: SizedBox(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded,
                            size: 22, color: AppColors.brand),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.listTitle.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.onInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onInkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            borderRadius: AppRadii.all(13),
                          ),
                          child: Text(
                            action,
                            style: AppType.small.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The customer's own rentals — moved here from the old second tab.
class _MyRentalsScreen extends StatefulWidget {
  const _MyRentalsScreen();

  @override
  State<_MyRentalsScreen> createState() => _MyRentalsScreenState();
}

class _MyRentalsScreenState extends State<_MyRentalsScreen> {
  late final RentalRepository _repository =
      RentalRepository(AppControllerScope.of(context).apiClient);

  List<RentalBooking> _bookings = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await _repository.myBookings();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _cancel(RentalBooking booking) async {
    final go = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            _t('Cancel this rental?', 'یہ بکنگ منسوخ کریں؟'),
            style: AppType.h2.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 10),
          Text(
            booking.advanceRefundableNow
                ? _t(
                    'Your advance will be returned.',
                    'آپ کا ایڈوانس واپس ہو جائے گا۔',
                  )
                : _t(
                    'The rental starts soon, so the advance stays with the '
                    'owner — they turned other bookings away for these days.',
                    'بکنگ قریب ہے، اس لیے ایڈوانس مالک کے پاس رہے گا — انہوں '
                        'نے ان دنوں کی دوسری بکنگ منع کی تھی۔',
                  ),
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 20),
          UdButton.primary(
            label: _t('Yes, cancel', 'ہاں، منسوخ کریں'),
            onPressed: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: 10),
          UdButton.ghost(
            label: _t('Keep it', 'رہنے دیں'),
            onPressed: () => Navigator.pop(sheetContext, false),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;
    try {
      await _repository.cancel(booking.id);
      await _load();
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusal.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'That could not be cancelled right now. Your booking is '
              'unchanged — please try again.',
              'یہ ابھی منسوخ نہیں ہو سکی۔ آپ کی بکنگ ویسی ہی ہے — دوبارہ کوشش '
                  'کریں۔',
            ),
          ),
        ),
      );
    }
  }

  /// A booking still waiting for the owner opens the waiting screen, which
  /// runs the clock and can cancel it.
  Future<void> _openWaiting(RentalBooking booking) async {
    final findOther = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RentalWaitingScreen(booking: booking),
      ),
    );
    if (!mounted) return;
    if (findOther == true) {
      Navigator.pop(context);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('My rentals', 'میری بکنگ'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.navy),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 12, AppSizes.sidePadding, 40),
                children: [
                  if (_error != null) ...[
                    UdBanner(tone: UdTone.err, text: _error),
                    const SizedBox(height: 12),
                  ],
                  if (_bookings.isEmpty && _error == null)
                    UdEmptyState(
                      icon: Icons.vpn_key_outlined,
                      title: _t('No rentals yet', 'ابھی کوئی بکنگ نہیں'),
                      text: _t(
                        'Cars you rent will appear here with the owner\'s '
                        'number and where to collect them.',
                        'آپ کی کرائے کی گاڑیاں یہاں آئیں گی — مالک کا نمبر اور '
                            'گاڑی کہاں سے ملے گی، دونوں کے ساتھ۔',
                      ),
                    )
                  else
                    for (final booking in _bookings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BookingCard(
                          booking: booking,
                          onCancel: booking.isLive && !booking.isPendingOwner
                              ? () => _cancel(booking)
                              : null,
                          onOpen: booking.isPendingOwner
                              ? () => _openWaiting(booking)
                              : null,
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

/// One of the Customer's own rentals.
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onCancel,
    this.onOpen,
  });

  final RentalBooking booking;
  final VoidCallback? onCancel;

  /// Set while the owner has not answered: opens the waiting screen.
  final VoidCallback? onOpen;

  /// Short enough for the chip; the refund is said in full below it.
  static String _chip(String status) => switch (status) {
        'PendingOwner' => 'Waiting for owner',
        'Declined' => 'Owner declined',
        'Expired' => 'Expired',
        _ => rentalStatusLabel(status),
      };

  @override
  Widget build(BuildContext context) {
    final pending = booking.isPendingOwner;
    final refused = booking.isRefusedByOwner;
    return UdCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      booking.vehicleName,
                      style: AppType.h3.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.registrationNumber} · ${booking.reference}',
                      style:
                          AppType.caption.copyWith(color: AppText.caption),
                    ),
                  ],
                ),
              ),
              UdBadge(
                label: _chip(booking.status),
                tone: switch (booking.status) {
                  'PendingOwner' => UdTone.warn,
                  'Declined' || 'Expired' => UdTone.info,
                  'Cancelled' || 'NoShow' => UdTone.err,
                  'Returned' => UdTone.gray,
                  _ => UdTone.ok,
                },
              ),
            ],
          ),
          if (pending || refused) ...[
            const SizedBox(height: 10),
            UdBanner(
              tone: pending ? UdTone.warn : UdTone.info,
              icon: pending
                  ? Icons.hourglass_top_rounded
                  : Icons.check_circle_outline_rounded,
              text: pending
                  ? 'Waiting for the owner to confirm. Tap to see the time '
                      'left or cancel.'
                  : booking.statusLabel,
            ),
          ],
          const SizedBox(height: 12),
          UdListGroup(
            children: [
              UdListRow(
                title:
                    '${_rentDay(booking.startDate)} — ${_rentDay(booking.endDate)}',
                subtitle: '${booking.days} day(s) · '
                    '${booking.isSelfDrive ? 'Self-drive' : 'With a driver'}',
              ),
              UdListRow(
                title: '${Money.amount(booking.balanceDue)} on collection',
                subtitle: 'Plus ${Money.amount(booking.securityDeposit)} '
                    'refundable deposit. Advance of '
                    '${Money.amount(booking.advanceAmount)} already paid.',
              ),
              if (booking.pickupPoint != null)
                UdListRow(
                  title: booking.pickupPoint!,
                  subtitle: 'Collect from',
                  leading: const UdIconTile(
                    icon: Icons.place_outlined,
                    tone: UdIconTone.neutral,
                  ),
                ),
              UdListRow(
                title: booking.counterpartName,
                subtitle: booking.counterpartPhone ??
                    (pending ? 'Number shown once the owner confirms' : 'Owner'),
                leading: const UdIconTile(
                  icon: Icons.person_outline_rounded,
                  tone: UdIconTone.neutral,
                ),
              ),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            UdButton.outline(
              label: booking.advanceRefundableNow
                  ? 'Cancel — advance returned'
                  : 'Cancel — advance not returned',
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}


/// The car is booked on the chosen dates. Matches the tour version: a clear
/// "already booked" line, how the waiting list works, and one button.
class _BookedSheet extends StatelessWidget {
  const _BookedSheet({
    required this.vehicle,
    required this.dates,
    required this.total,
    required this.onSend,
  });

  final RentalVehicle vehicle;
  final String dates;
  final String total;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vehicle.name,
          style: AppType.h2.copyWith(fontSize: 20, color: AppText.primary),
        ),
        const SizedBox(height: 12),
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.event_busy_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yeh gaari $dates book ho chuki hai',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Aap phir bhi request bhej sakte hain. Agar booked customer '
                'cancel kare ya na aaye, to driver aap ki request accept kar '
                'sakta hai — phir aap ko notification aayegi.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Poori gaari · $dates',
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
            ),
            Text(
              total,
              style: AppType.listTitle.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Request bhejne par koi paisa nahi katega. Accept hone par advance '
          'dena hoga.',
          style: AppType.caption.copyWith(color: AppText.secondary),
        ),
        const SizedBox(height: 16),
        UdButton.dark(
          label: 'Waiting list mein request bhejein',
          onPressed: onSend,
        ),
      ],
    );
  }
}
