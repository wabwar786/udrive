import 'package:flutter/material.dart';

import '../../core/growth/driver_growth_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';

/// D-63 — everything the platform has told drivers in this city.
///
/// The API has returned fifty of these all along, and the home screen has only
/// ever shown `updates.first`. Every other update written — a road reopening, a
/// commission change, next Sunday's rush — was fetched and thrown away. This is
/// the screen that reads the other forty-nine.
class DriverUpdatesScreen extends StatefulWidget {
  const DriverUpdatesScreen({super.key});

  @override
  State<DriverUpdatesScreen> createState() => _DriverUpdatesScreenState();
}

class _DriverUpdatesScreenState extends State<DriverUpdatesScreen> {
  late final DriverGrowthRepository _repository =
      DriverGrowthRepository(AppControllerScope.of(context).apiClient);

  List<DriverUpdate> _updates = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  Future<void> _load() async {
    setState(() => _loading = true);
    final updates = await _repository.updates();
    if (!mounted) return;
    setState(() {
      _updates = updates;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('Updates', 'اطلاعات'),
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.sidePadding, 14, AppSizes.sidePadding, 40),
                children: [
                  if (_updates.isEmpty)
                    UdEmptyState(
                      icon: Icons.campaign_outlined,
                      title: _t('Nothing yet', 'ابھی کچھ نہیں'),
                      text: _t(
                        'Road conditions, busy days and policy changes for your '
                        'city will appear here.',
                        'آپ کے شہر کے راستوں کے حالات، مصروف دن اور پالیسی کی '
                            'تبدیلیاں یہاں آئیں گی۔',
                      ),
                    )
                  else
                    UdListGroup(
                      children: _updates
                          .map((update) => UdListRow(
                                title: update.title,
                                subtitle:
                                    '${update.body}\n${_ago(update.publishAt)}',
                                leading: UdIconTile(
                                  icon: _icon(update.category),
                                  tone: _tone(update.category),
                                ),
                              ))
                          .toList(growable: false),
                    ),
                ],
              ),
            ),
    );
  }

  static IconData _icon(String category) => switch (category) {
        'Demand' => Icons.trending_up_rounded,
        'Rewards' => Icons.star_outline_rounded,
        'Policy' => Icons.gavel_rounded,
        'Service' => Icons.build_outlined,
        _ => Icons.campaign_outlined,
      };

  static UdIconTone _tone(String category) =>
      category == 'Demand' || category == 'Rewards'
          ? UdIconTone.soft
          : UdIconTone.neutral;

  /// Relative, because "2 hours ago" is what decides whether a road report
  /// still applies and an exact timestamp is not.
  String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);
    if (gap.inMinutes < 60) {
      return _t('${gap.inMinutes} minute(s) ago', '${gap.inMinutes} منٹ پہلے');
    }
    if (gap.inHours < 24) {
      return _t('${gap.inHours} hour(s) ago', '${gap.inHours} گھنٹے پہلے');
    }
    if (gap.inDays == 1) return _t('Yesterday', 'کل');
    return _t('${gap.inDays} day(s) ago', '${gap.inDays} دن پہلے');
  }
}
