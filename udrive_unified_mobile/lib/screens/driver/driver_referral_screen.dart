import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/growth/driver_growth_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/driver_growth_models.dart';

/// D-60 — the Driver's referral code, and everyone who has used it.
///
/// The code itself has been generated for every driver since the growth system
/// shipped, and there has never been a screen that showed it or a route that
/// accepted one. `driver_referrals` was read on every growth evaluation and
/// written by nothing in the codebase, so the whole programme reported zero
/// invites to everybody, for ever.
///
/// Each milestone is listed separately, with what it pays and whether it has
/// landed. The temptation is one "Pending: PKR 1,700" figure, and that is the
/// number a driver argues about three weeks later — it says nothing about which
/// of their invitees is stuck, or on what.
class DriverReferralScreen extends StatefulWidget {
  const DriverReferralScreen({super.key});

  @override
  State<DriverReferralScreen> createState() => _DriverReferralScreenState();
}

class _DriverReferralScreenState extends State<DriverReferralScreen> {
  late final DriverGrowthRepository _repository =
      DriverGrowthRepository(AppControllerScope.of(context).apiClient);

  ReferralSummary? _summary;
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
    final summary = await _repository.referrals();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: _t('Refer a driver', 'ڈرائیور بلائیں'),
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
                children: summary == null
                    ? [
                        UdEmptyState(
                          icon: Icons.group_add_outlined,
                          title: _t('Not available', 'دستیاب نہیں'),
                          text: _t(
                            'Your referral code could not be loaded. Pull down '
                            'to try again.',
                            'آپ کا کوڈ نہیں آ سکا۔ نیچے کھینچ کر دوبارہ کوشش '
                                'کریں۔',
                          ),
                        ),
                      ]
                    : _content(summary),
              ),
            ),
    );
  }

  List<Widget> _content(ReferralSummary summary) => [
        _CodeCard(code: summary.code, onCopy: () => _copy(summary.code)),
        const SizedBox(height: 12),
        UdButton.primary(
          label: _t('Send on WhatsApp', 'واٹس ایپ پر بھیجیں'),
          icon: Icons.ios_share_rounded,
          onPressed: () => _copy(summary.code, share: true),
        ),

        const SizedBox(height: 14),
        // Offered here because there is nowhere else a Driver would look for
        // it. The server refuses a code once the account is verified, and says
        // so in words — which is the honest place for that rule, since a code
        // accepted after verification would let two established drivers enter
        // each other's and collect twice for nobody new.
        UdListGroup(
          children: [
            UdListRow(
              title: _t('Somebody invited me', 'مجھے کسی نے بلایا تھا'),
              subtitle: _t(
                'Enter their code — they earn, nothing is taken from you.',
                'ان کا کوڈ ڈالیں — انہیں انعام ملے گا، آپ کا کچھ نہیں کٹتا۔',
              ),
              leading: const UdIconTile(
                icon: Icons.redeem_outlined,
                tone: UdIconTone.neutral,
              ),
              onTap: _enterCode,
              showChevron: true,
            ),
          ],
        ),

        const SizedBox(height: 22),
        UdSectionHeader(title: _t('What you get', 'آپ کو کیا ملتا ہے')),
        const SizedBox(height: 10),
        UdBanner(
          tone: UdTone.info,
          icon: Icons.info_outline_rounded,
          text: _t(
            'Paid as the driver you brought gets going — most of it when they '
            'are actually working, not when they sign up.',
            'جو ڈرائیور آپ لائے، جوں جوں وہ کام شروع کرے آپ کو ملتا ہے — سب سے '
                'بڑا حصہ تب، جب وہ واقعی چل پڑے۔',
          ),
        ),

        const SizedBox(height: 22),
        UdSectionHeader(
          title: _t('Your invites', 'آپ کے انوائٹ'),
          caption: summary.totalInvited == 0 ? null : '${summary.totalInvited}',
        ),
        const SizedBox(height: 10),

        if (summary.totalInvited == 0)
          UdEmptyState(
            icon: Icons.group_add_outlined,
            title: _t('Nobody yet', 'ابھی کوئی نہیں'),
            text: _t(
              'Share your code with a driver you know. You will see them here '
              'the moment they sign up with it.',
              'کسی جاننے والے ڈرائیور کو اپنا کوڈ دیں۔ وہ کوڈ کے ساتھ سائن اپ '
                  'کرتے ہی یہاں نظر آ جائے گا۔',
            ),
          )
        else ...[
          _Totals(
            earned: summary.earnedAmount,
            pending: summary.pendingAmount,
            t: _t,
          ),
          const SizedBox(height: 12),
          UdListGroup(
            children: summary.entries
                .map((entry) => UdListRow(
                      title: entry.name,
                      subtitle: _progressLine(entry),
                      leading: UdIconTile(
                        icon: entry.isActive
                            ? Icons.verified_rounded
                            : Icons.person_outline_rounded,
                        tone: entry.isActive
                            ? UdIconTone.soft
                            : UdIconTone.neutral,
                      ),
                      trailing: Text(
                        entry.rewardEarned > 0
                            ? 'PKR ${entry.rewardEarned.round()}'
                            : '—',
                        style: AppType.body2.copyWith(
                          color: entry.rewardEarned > 0
                              ? AppColors.brandInk
                              : AppText.caption,
                        ),
                      ),
                    ))
                .toList(growable: false),
          ),
        ],
      ];

  /// What this invitee has reached, in the order the money arrives.
  String _progressLine(ReferralEntry entry) {
    final steps = <String>[
      if (entry.isVerified) _t('verified', 'تصدیق شدہ'),
      if (entry.hasRidden) _t('first ride', 'پہلی رائیڈ'),
      if (entry.isActive) _t('active', 'ایکٹو'),
    ];
    if (steps.isEmpty) {
      return _t('Documents with the admin', 'کاغذات ایڈمن کے پاس');
    }
    return steps.join(' · ');
  }

  /// Where a Driver says who brought them.
  ///
  /// The first route in the codebase that writes `driver_referrals` at all.
  Future<void> _enterCode() async {
    final controller = TextEditingController();
    var busy = false;
    String? error;

    final applied = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                _t('Who invited you?', 'آپ کو کس نے بلایا؟'),
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 10),
              Text(
                _t(
                  'The driver who told you about UDrive earns as you get going. '
                  'Nothing is taken from your side.',
                  'جس ڈرائیور نے آپ کو UDrive بتایا، جوں جوں آپ چلیں گے اسے '
                      'انعام ملے گا۔ آپ کا کچھ نہیں کٹتا۔',
                ),
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                UdBanner(tone: UdTone.err, text: error),
                const SizedBox(height: 12),
              ],
              UdTextField(
                controller: controller,
                label: _t('Referral code', 'ریفرل کوڈ'),
                hint: 'UDRIVE-ABCDE',
                icon: Icons.redeem_outlined,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 18),
              UdButton.primary(
                label: busy
                    ? _t('Adding…', 'شامل ہو رہا ہے…')
                    : _t('Add', 'شامل کریں'),
                onPressed: busy
                    ? null
                    : () async {
                        setSheetState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await _repository
                              .applyReferralCode(controller.text.trim());
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (failure) {
                          setSheetState(() {
                            busy = false;
                            error = '$failure';
                          });
                        }
                      },
              ),
              const SizedBox(height: 10),
              UdButton.ghost(
                label: _t('Not now', 'ابھی نہیں'),
                onPressed: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      ),
    );

    controller.dispose();
    if (applied == true && mounted) await _load();
  }

  Future<void> _copy(String code, {bool share = false}) async {
    final text = share
        ? _t(
            'Drive with UDrive. Use my code $code when you sign up.',
            'UDrive پر گاڑی چلائیں۔ سائن اپ کرتے وقت میرا کوڈ $code ڈالیں۔',
          )
        : code;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(share
            ? _t('Message copied — paste it in WhatsApp',
                'پیغام کاپی ہو گیا — واٹس ایپ میں پیسٹ کریں')
            : _t('Code copied', 'کوڈ کاپی ہو گیا')),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => UdCard(
        tone: UdCardTone.navy,
        onTap: onCopy,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                code.isEmpty ? '—' : code,
                style: AppType.h1.copyWith(
                  color: AppText.onInk,
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.copy_rounded, size: 20, color: AppColors.brand),
          ],
        ),
      );
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.earned,
    required this.pending,
    required this.t,
  });

  final double earned;
  final double pending;
  final String Function(String, String) t;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _Figure(
              label: t('Earned', 'مل چکا'),
              value: 'PKR ${earned.round()}',
              strong: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Figure(
              label: t('Still to come', 'آنا باقی'),
              value: 'PKR ${pending.round()}',
              strong: false,
            ),
          ),
        ],
      );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.strong,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => UdCard(
        selected: strong,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: AppType.caption.copyWith(
                color: AppText.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppType.h2.copyWith(
                color: strong ? AppColors.brandInk : AppText.primary,
                height: 1,
              ),
            ),
          ],
        ),
      );
}
