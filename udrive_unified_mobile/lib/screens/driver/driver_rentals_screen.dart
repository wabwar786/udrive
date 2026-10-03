import 'package:flutter/material.dart';

import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// The owner's side of renting: who has which car, and when it comes back.
///
/// This screen is also the only place the Driver can see their own vehicle
/// committed into the future. Before rental there was nothing to see — a trip
/// is hours long and a package carries its own date — and with rental there is
/// a car in somebody else's driveway for a week, which is exactly the thing a
/// Driver must not forget when the next job is offered.
class DriverRentalsScreen extends StatefulWidget {
  const DriverRentalsScreen({super.key});

  @override
  State<DriverRentalsScreen> createState() => _DriverRentalsScreenState();
}

class _DriverRentalsScreenState extends State<DriverRentalsScreen> {
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
      final bookings = await _repository.driverBookings();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(RentalBooking booking, String status) async {
    try {
      await _repository.setStatus(booking.id, status);
      await _load();
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusal.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _bookings.where((b) => b.isLive).toList(growable: false);
    final past = _bookings.where((b) => !b.isLive).toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('Rentals', 'کرائے'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 12, AppSizes.sidePadding, 40),
                children: [
                  if (_error != null) ...[
                    UdBanner(tone: UdTone.err, text: _error),
                    const SizedBox(height: 14),
                  ],
                  if (_bookings.isEmpty)
                    UdEmptyState(
                      icon: Icons.vpn_key_outlined,
                      title: _t('No rentals yet', 'ابھی کوئی کرایہ نہیں'),
                      text: _t(
                        'Set a daily rate on a vehicle and switch Rent a car '
                        'on, and bookings will appear here.',
                        'کسی گاڑی پر روزانہ کرایہ رکھیں اور "کرائے پر گاڑی" '
                            'چالو کریں، بکنگ یہاں آنے لگے گی۔',
                      ),
                    ),
                  if (live.isNotEmpty) ...[
                    UdSectionHeader(
                      title: _t('Now and next', 'ابھی اور آگے'),
                      caption: '${live.length}',
                    ),
                    const SizedBox(height: 10),
                    ...live.map((booking) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RentalCard(
                            booking: booking,
                            t: _t,
                            onHandOver: booking.status == 'Confirmed'
                                ? () => _setStatus(booking, 'HandedOver')
                                : null,
                            onReturned: booking.status == 'HandedOver'
                                ? () => _setStatus(booking, 'Returned')
                                : null,
                            onNoShow: booking.status == 'Confirmed'
                                ? () => _setStatus(booking, 'NoShow')
                                : null,
                          ),
                        )),
                  ],
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    UdSectionHeader(title: _t('Finished', 'مکمل')),
                    const SizedBox(height: 10),
                    ...past.map((booking) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RentalCard(booking: booking, t: _t),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({
    required this.booking,
    required this.t,
    this.onHandOver,
    this.onReturned,
    this.onNoShow,
  });

  final RentalBooking booking;
  final String Function(String, String) t;
  final VoidCallback? onHandOver;
  final VoidCallback? onReturned;
  final VoidCallback? onNoShow;

  @override
  Widget build(BuildContext context) {
    return UdCard(
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
                      '${_d(booking.startDate)} — ${_d(booking.endDate)}',
                      style: AppType.h3.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.vehicleName} · ${booking.registrationNumber}',
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              UdBadge(
                label: booking.isSelfDrive
                    ? t('SELF-DRIVE', 'خود')
                    : t('WITH DRIVER', 'ڈرائیور'),
                tone: booking.isSelfDrive ? UdTone.warn : UdTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 12),
          UdListGroup(
            children: [
              UdListRow(
                title: booking.counterpartName,
                subtitle: booking.counterpartPhone ??
                    t('Customer', 'کسٹمر'),
                leading: const UdIconTile(
                  icon: Icons.person_outline_rounded,
                  tone: UdIconTone.neutral,
                ),
              ),
              UdListRow(
                title: 'PKR ${booking.balanceDue.round()} '
                    '${t('to collect', 'وصول کرنی ہے')}',
                subtitle: t(
                  'Plus PKR ${booking.securityDeposit.round()} deposit, which '
                  'you return. Advance of PKR ${booking.advanceAmount.round()} '
                  'already paid through the app.',
                  'اور PKR ${booking.securityDeposit.round()} ڈیپازٹ، جو آپ '
                      'واپس کریں گے۔ PKR ${booking.advanceAmount.round()} '
                      'ایڈوانس ایپ سے ادا ہو چکا ہے۔',
                ),
                leading: const UdIconTile(
                  icon: Icons.payments_outlined,
                  tone: UdIconTone.soft,
                ),
              ),
            ],
          ),

          // Self-drive is the only path where documents exist, and they are
          // meant to be looked at with the person in front of you — not a
          // week earlier by somebody in an office.
          if (booking.isSelfDrive && booking.isLive) ...[
            const SizedBox(height: 10),
            UdBanner(
              tone: UdTone.info,
              icon: Icons.badge_outlined,
              text: t(
                'Check their CNIC and licence against the person collecting '
                'the car. Nobody at UDrive has checked them.',
                'ان کا شناختی کارڈ اور لائسنس اسی شخص سے ملائیں جو گاڑی لینے '
                    'آیا ہے۔ UDrive نے یہ نہیں جانچے۔',
              ),
            ),
          ],

          if (onHandOver != null || onReturned != null) ...[
            const SizedBox(height: 12),
            if (onHandOver != null)
              UdButton.primary(
                label: t('Car handed over', 'گاڑی دے دی'),
                onPressed: onHandOver,
              ),
            if (onReturned != null)
              UdButton.primary(
                label: t('Car returned', 'گاڑی واپس آ گئی'),
                onPressed: onReturned,
              ),
            if (onNoShow != null) ...[
              const SizedBox(height: 8),
              UdButton.ghost(
                label: t('They did not come', 'وہ نہیں آئے'),
                onPressed: onNoShow,
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _d(DateTime value) => '${value.day} ${_months[value.month - 1]}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
