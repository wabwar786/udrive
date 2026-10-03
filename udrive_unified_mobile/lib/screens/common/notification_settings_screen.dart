import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// D-64 — which notifications this person wants.
///
/// `notification_preferences` has had all seven switches since the first
/// schema, with an endpoint to read them and an endpoint to save them. There
/// has never been a screen, so every one of them has sat at its default and
/// nobody could turn anything off — the only lever available was switching the
/// phone's notifications off entirely, which also loses the booking alerts
/// people actually want.
///
/// Shown to both Drivers and Customers: the switches are about this account,
/// not about which half of the app it uses.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const _keys = <String>[
    'bookingAlerts',
    'packageAlerts',
    'payoutAlerts',
    'complaintAlerts',
    'promotionalAlerts',
    'pushEnabled',
    'smsEnabled',
  ];

  final Map<String, bool> _values = {for (final key in _keys) key: true};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  ApiClient get _api => AppControllerScope.of(context).apiClient;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getJson('/api/v1/notification-preferences');
      final data = response['data'];
      if (!mounted) return;
      setState(() {
        if (data is Map) {
          for (final key in _keys) {
            _values[key] = data[key] != false;
          }
        }
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

  /// Saved on every switch rather than behind a Save button.
  ///
  /// There is nothing to review here: each switch is its own decision and takes
  /// effect on its own. A Save button would only add a way to turn something
  /// off and have it come back.
  Future<void> _set(String key, bool value) async {
    final previous = _values[key] ?? true;
    setState(() {
      _values[key] = value;
      _saving = true;
      _error = null;
    });

    try {
      await _api.putJson('/api/v1/notification-preferences', {
        for (final entry in _values.entries) entry.key: entry.value,
      });
      if (mounted) setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      // Put the switch back. Leaving it where the finger left it would tell
      // somebody they had turned payout alerts off when they had not.
      setState(() {
        _values[key] = previous;
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('Notifications', 'اطلاعات'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 14, AppSizes.sidePadding, 40),
              children: [
                if (_error != null) ...[
                  UdBanner(tone: UdTone.err, text: _error),
                  const SizedBox(height: 14),
                ],
                UdSectionHeader(title: _t('What to tell me', 'کیا بتایا جائے')),
                const SizedBox(height: 10),
                UdListGroup(
                  children: [
                    _row('bookingAlerts',
                        _t('Bookings', 'بکنگ'),
                        _t('New rides, accepted offers, cancellations',
                            'نئی رائیڈ، آفر منظور، کینسل')),
                    _row('packageAlerts',
                        _t('Packages', 'پیکج'),
                        _t('Seats sold, departures coming up',
                            'سیٹ بکی، روانگی قریب')),
                    _row('payoutAlerts',
                        _t('Money', 'پیسہ'),
                        _t('Rewards credited, wallet, payouts',
                            'انعام، والیٹ، ادائیگی')),
                    _row('complaintAlerts',
                        _t('Complaints', 'شکایت'),
                        _t('When somebody raises one about a trip',
                            'جب کوئی سفر پر شکایت کرے')),
                    _row('promotionalAlerts',
                        _t('Offers', 'آفرز'),
                        _t('New campaigns and weekly targets',
                            'نئی کیمپین اور ہفتہ وار ٹارگٹ')),
                  ],
                ),
                const SizedBox(height: 22),
                UdSectionHeader(title: _t('How to tell me', 'کیسے بتایا جائے')),
                const SizedBox(height: 10),
                UdListGroup(
                  children: [
                    _row('pushEnabled',
                        _t('Push notifications', 'پش نوٹیفکیشن'),
                        _t('On this phone', 'اس فون پر')),
                    _row('smsEnabled',
                        _t('SMS', 'ایس ایم ایس'),
                        _t('Only for the important ones',
                            'صرف ضروری باتوں کے لیے')),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _t(
                    'Turning everything off does not stop a trip in progress '
                    'from reaching you — safety messages are always sent.',
                    'سب بند کرنے سے چلتے سفر کی اطلاع نہیں رکتی — حفاظت کے '
                        'پیغام ہمیشہ جاتے ہیں۔',
                  ),
                  style: AppType.caption.copyWith(color: AppText.caption),
                ),
              ],
            ),
    );
  }

  Widget _row(String key, String title, String subtitle) => UdListRow(
        title: title,
        subtitle: subtitle,
        trailing: UdSwitch(
          value: _values[key] ?? true,
          onChanged: _saving ? null : (value) => _set(key, value),
          semanticLabel: title,
        ),
      );
}
