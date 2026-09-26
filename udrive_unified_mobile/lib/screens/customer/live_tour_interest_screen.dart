import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_controls.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';

/// C-25 — Join a Tour.
///
/// A bottom-nav tab root: `main_shell` supplies the top bar, so there is no
/// `Scaffold` and no app bar here.
class LiveTourInterestScreen extends StatefulWidget {
  const LiveTourInterestScreen({super.key});

  @override
  State<LiveTourInterestScreen> createState() => _LiveTourInterestScreenState();
}

class _LiveTourInterestScreenState extends State<LiveTourInterestScreen> {
  static const destinations = <String, String>{
    '10000000-0000-0000-0000-000000000002': 'Neelum Valley',
    '10000000-0000-0000-0000-000000000003': 'Sharda',
    '10000000-0000-0000-0000-000000000004': 'Rawalakot',
    '10000000-0000-0000-0000-000000000005': 'Banjosa Lake',
    '10000000-0000-0000-0000-000000000006': 'Pir Chinasi',
  };

  /// The four values the API takes, with the label each one shows.
  static const preferences = <String, String>{
    'Family': 'Family',
    'WomenOnly': 'Women only',
    'Individual': 'Individual',
    'Group': 'Group',
  };

  String _destinationId = destinations.keys.first;
  String _preference = 'Family';
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  int _persons = 2;
  final _pickup = TextEditingController(text: 'Muzaffarabad');
  final _budget = TextEditingController(text: '5000');
  bool _busy = false;

  @override
  void dispose() {
    _pickup.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final advancePercent = (AppConfig.tourAdvancePercent * 100).round();

    return RefreshIndicator(
      onRefresh: controller.refreshPhase9Marketplace,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
        children: [
          UdCard(
            tone: UdCardTone.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Was a bare AppColors.accent icon — the deep lime ink, which
                // is picked for white pages and sits at about 2.1:1 on navy.
                // On navy the accent has to be the lime itself, on a tile.
                const UdIconTile(
                  icon: Icons.auto_awesome_rounded,
                  tone: UdIconTone.lime,
                ),
                const SizedBox(height: 14),
                Text(
                  _t(context, 'Tell Udrive where you want to go',
                      'یو ڈرائیو کو بتائیں آپ کہاں جانا چاہتے ہیں'),
                  style: AppType.h2.copyWith(color: AppText.onInk),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    context,
                    'We match your date, group, seats, budget and pickup city '
                        'with approved Driver packages.',
                    'ہم آپ کی تاریخ، گروپ، نشستوں، بجٹ اور شہر کو منظور شدہ ڈرائیور پیکجز سے میچ کرتے ہیں۔',
                  ),
                  // Was AppText.secondary: about 2.3:1 on navy. This is 10.8:1.
                  style: AppType.body2.copyWith(color: AppText.onInkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const UdSectionHeader(title: 'Trip details'),
          const SizedBox(height: 14),
          _PickerField(
            label: 'Destination',
            value: destinations[_destinationId] ?? '',
            icon: Icons.landscape_rounded,
            onTap: _pickDestination,
          ),
          const SizedBox(height: 14),
          UdTextField(
            controller: _pickup,
            label: 'Pickup city',
            icon: Icons.location_city_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          _PickerField(
            label: 'Preferred date',
            value: DateFormat('dd MMM yyyy').format(_date),
            icon: Icons.calendar_month_rounded,
            onTap: _pickDate,
          ),
          const SizedBox(height: 14),
          const UdLabel('Group preference'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in preferences.entries)
                UdChip(
                  label: entry.value,
                  selected: _preference == entry.key,
                  onTap: () => setState(() => _preference = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 18),
          UdStepper(
            label: 'Tour persons',
            value: _persons,
            min: 1,
            onChanged: (value) => setState(() => _persons = value),
          ),
          const SizedBox(height: 16),
          UdTextField(
            controller: _budget,
            label: 'Maximum budget per seat (PKR)',
            icon: Icons.payments_rounded,
            keyboardType: TextInputType.number,
            helper: 'Tour bookings need at least a $advancePercent% advance '
                'once matched.',
          ),
          const SizedBox(height: 20),
          UdButton.primary(
            label: _t(context, 'Register & find matching tours',
                'رجسٹر کریں اور میچنگ ٹور تلاش کریں'),
            icon: Icons.notifications_active_rounded,
            busy: _busy,
            onPressed: _register,
          ),
          const SizedBox(height: 26),
          const UdSectionHeader(title: 'Matching departures'),
          const SizedBox(height: 14),
          if (controller.liveTourMatches.isEmpty)
            UdBanner(
              tone: UdTone.gray,
              icon: Icons.info_outline_rounded,
              text: _t(
                context,
                'No active match yet. Your registration remains active and new '
                    'approved packages can match later.',
                'ابھی کوئی فعال میچ نہیں۔ آپ کی رجسٹریشن فعال رہے گی اور نئے منظور شدہ پیکجز بعد میں میچ ہو سکتے ہیں۔',
              ),
            )
          else
            for (final match in controller.liveTourMatches)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MatchCard(match: match),
              ),
        ],
      ),
    );
  }

  Future<void> _pickDestination() async {
    final picked = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Destination',
              style: AppType.h2.copyWith(color: AppText.primary),
            ),
            const SizedBox(height: 16),
            UdListGroup(
              children: [
                for (final entry in destinations.entries)
                  UdListRow(
                    title: entry.value,
                    leading: const UdIconTile(
                      icon: Icons.landscape_rounded,
                      size: UdIconTileSize.sm,
                    ),
                    trailing: entry.key == _destinationId
                        ? const Icon(Icons.check_circle_rounded,
                            size: 22, color: AppColors.brandInk)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, entry.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _destinationId = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      await AppControllerScope.of(context).createLiveTourInterest({
        'destinationId': _destinationId,
        'preferredStartDate': DateFormat('yyyy-MM-dd').format(_date),
        'preferredEndDate': DateFormat('yyyy-MM-dd')
            .format(_date.add(const Duration(days: 5))),
        'persons': _persons,
        'groupPreference': _preference,
        'budgetPerSeat': double.tryParse(_budget.text),
        'pickupCity': _pickup.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tour interest registered and matching completed.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

/// A field that opens a picker rather than the keyboard: the box looks like
/// every other field in the app, and the chevron says it is a button.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          UdLabel(label),
          const SizedBox(height: 8),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadii.all(AppRadii.field),
              child: Container(
                height: AppSizes.field,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: AppRadii.all(AppRadii.field),
                  border: Border.all(
                      color: AppColors.borderStrong, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: AppText.secondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body.copyWith(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.chevron_right_rounded,
                        size: 22, color: AppText.caption),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

/// One matched departure.
class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});

  final LiveTourMatch match;

  @override
  Widget build(BuildContext context) {
    final tight = match.availableSeats <= 2;

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UdBadge(label: '${match.matchPercent}% match', tone: UdTone.lime),
              const Spacer(),
              UdBadge(
                label: '${match.availableSeats} seats free',
                tone: tight ? UdTone.warn : UdTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.all(AppRadii.row),
            ),
            child: Row(
              children: [
                const Icon(Icons.route_rounded, size: 17, color: AppColors.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    match.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.listTitle.copyWith(
                      fontSize: 15,
                      color: AppText.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            match.packageTitle,
            style: AppType.h3.copyWith(fontSize: 16, color: AppText.primary),
          ),
          const SizedBox(height: 3),
          Text(
            'Departs ${DateFormat('dd MMM').format(match.departureAt)}',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${match.driverName} · Safety ${match.safetyScore}/100',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'PKR ${NumberFormat('#,###').format(match.pricePerSeat)}',
                style: AppType.priceMd.copyWith(
                  fontSize: 19,
                  color: AppColors.brandInk,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
