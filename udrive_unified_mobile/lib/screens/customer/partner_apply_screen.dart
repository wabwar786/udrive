import 'package:flutter/material.dart';

import '../../core/partner/partner_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// "Become a partner" — a customer asking to run UDrive in their own area.
///
/// The whole reason this is in the app rather than a form an admin fills in: the
/// people who can actually run UDrive in a town are people already using it
/// there. An admin typing names into a panel never meets them.
///
/// Two things this screen is careful about, both learned from how these go
/// wrong:
///
/// **It says which areas are taken, before anybody asks.** The territory list
/// shows the holder's name on an area that has one, and those areas cannot be
/// selected. Finding out six weeks later, in a refusal, that the job was never
/// open is the thing that makes somebody angry — not the refusal.
///
/// **It says what the work is, not only what the money is.** Each tier lists its
/// monthly commitments on the card, above the deposit. A partnership somebody
/// thought was an investment, and turns out to be a job, is an argument later —
/// and the deposit here earns nothing by itself. That is the agreement, so it is
/// on the first screen.
class PartnerApplyScreen extends StatefulWidget {
  const PartnerApplyScreen({super.key});

  @override
  State<PartnerApplyScreen> createState() => _PartnerApplyScreenState();
}

class _PartnerApplyScreenState extends State<PartnerApplyScreen> {
  final _note = TextEditingController();
  final _phone = TextEditingController();

  PartnerOpenings? _data;
  PartnerTier? _tier;
  TerritoryNode? _territory;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _sent;

  PartnerRepository get _repository =>
      PartnerRepository(AppControllerScope.of(context).apiClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _note.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.openings();
      if (!mounted) return;
      setState(() {
        _data = data;
        // Only clear a selection that is no longer offered. Reloading after a
        // failed submit should not quietly throw away what they picked.
        if (_tier != null &&
            !data.tiers.any((tier) => tier.tierKey == _tier!.tierKey)) {
          _tier = null;
          _territory = null;
        }
      });
    } on PartnerRefused catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'We could not load this. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final tier = _tier;
    final territory = _territory;
    if (tier == null || territory == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _repository.apply(
        tierKey: tier.tierKey,
        territoryId: territory.id,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      );
      if (!mounted) return;
      setState(() => _sent = territory.name);
      await _load();
    } on PartnerRefused catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The areas this tier can be appointed over, and only those.
  ///
  /// Filtered by kind because the server refuses a mismatch anyway — a City Head
  /// application against a tehsil is rejected — and a choice that is going to be
  /// refused should not be offered.
  List<TerritoryNode> _areasFor(PartnerTier tier) =>
      (_data?.territories ?? const <TerritoryNode>[])
          .where((node) => node.kind == tier.territoryKind)
          .toList();

  @override
  Widget build(BuildContext context) {
    final mine = _data?.mine ?? PartnerSelf.none;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: 'Become a partner',
        onBack: () => Navigator.maybePop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding,
                8,
                AppSizes.sidePadding,
                32,
              ),
              children: [
                if (_sent != null) ...[
                  _Banner(
                    tone: _BannerTone.good,
                    title: 'Your request has been sent',
                    body: 'We will look at it and come back to you about '
                        '$_sent. You can see where it stands on this screen.',
                  ),
                  const SizedBox(height: 16),
                ],

                if (mine.isPartner) ...[
                  _Banner(
                    tone: _BannerTone.good,
                    title: 'You are a UDrive partner',
                    body: '${mine.partnerTierName} of ${mine.partnerTerritory}. '
                        '${mine.contractAwaitingSignature ? 'Your contract is waiting for your signature in the partner portal.' : 'Your contract and your monthly record are in the partner portal.'}',
                  ),
                  const SizedBox(height: 16),
                ] else if (mine.isPending) ...[
                  _Banner(
                    tone: _BannerTone.wait,
                    title: 'You already have a request with us',
                    body: '${mine.applicationTerritory ?? 'Your area'} — we will '
                        'come back to you on that one first.',
                  ),
                  const SizedBox(height: 10),
                  UdButton.outline(
                    label: 'Withdraw that request',
                    size: UdButtonSize.small,
                    onPressed: _busy || mine.applicationId == null
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await _repository.withdraw(mine.applicationId!);
                              await _load();
                            } on PartnerRefused catch (error) {
                              if (mounted) {
                                setState(() => _error = error.message);
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                ] else if (mine.applicationStatus == 'Rejected') ...[
                  _Banner(
                    tone: _BannerTone.warn,
                    title: 'Your last request was not accepted',
                    // The admin wrote this sentence knowing the applicant would
                    // read it. Shown word for word rather than softened.
                    body: mine.decisionReason ??
                        'You can ask again for a different area.',
                  ),
                  const SizedBox(height: 16),
                ],

                Text(
                  'Run UDrive where you live',
                  style: AppType.h2.copyWith(color: AppText.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'A partner holds one area — nobody else gets it. In return they '
                  'bring drivers, keep them working, and are the local answer for '
                  'drivers and customers. The deposit is refundable and earns '
                  'nothing on its own; what a partner earns comes from the work.',
                  style: AppType.small
                      .copyWith(color: AppText.secondary, height: 1.55),
                ),
                const SizedBox(height: 20),

                if (_error != null) ...[
                  _Banner(
                    tone: _BannerTone.warn,
                    title: 'That did not go through',
                    body: _error!,
                  ),
                  const SizedBox(height: 16),
                ],

                const UdSectionHeader(title: 'Choose what you want to be'),
                const SizedBox(height: 10),

                for (final tier in _data?.tiers ?? const <PartnerTier>[]) ...[
                  _TierCard(
                    tier: tier,
                    selected: _tier?.tierKey == tier.tierKey,
                    openAreas: _areasFor(tier).where((a) => a.isOpen).length,
                    onTap: () => setState(() {
                      _tier = tier;
                      _territory = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],

                if (_tier != null) ...[
                  const SizedBox(height: 10),
                  const UdSectionHeader(title: 'Choose your area'),
                  const SizedBox(height: 10),
                  _AreaList(
                    areas: _areasFor(_tier!),
                    selected: _territory,
                    onSelect: (node) => setState(() => _territory = node),
                  ),
                  const SizedBox(height: 20),
                  UdTextField(
                    controller: _phone,
                    label: 'Phone to reach you on',
                    labelSuffix: '(optional)',
                    hint: 'If it is not the number you signed in with',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  UdTextField(
                    controller: _note,
                    label: 'Why you',
                    labelSuffix: '(optional)',
                    hint: 'What you do, who you know locally, how you would '
                        'bring drivers',
                    maxLines: 4,
                    minLines: 3,
                  ),
                  const SizedBox(height: 20),
                  UdButton.primary(
                    label: 'Send my request',
                    busy: _busy,
                    onPressed:
                        _territory == null || _busy || mine.isPending ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nothing is agreed by sending this. If we accept, we write a '
                    'contract and you read all of it before signing anything.',
                    textAlign: TextAlign.center,
                    style: AppType.caption
                        .copyWith(color: AppText.caption, height: 1.45),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.selected,
    required this.openAreas,
    required this.onTap,
  });

  final PartnerTier tier;
  final bool selected;
  final int openAreas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return UdCard(
      tone: UdCardTone.plain,
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tier.displayName,
                  style: AppType.h3.copyWith(color: AppText.primary),
                ),
              ),
              Text(
                openAreas == 0 ? 'none open' : '$openAreas open',
                style: AppType.caption.copyWith(
                  color: openAreas == 0 ? AppText.caption : AppColors.brandInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (tier.description != null) ...[
            const SizedBox(height: 6),
            Text(
              tier.description!,
              style: AppType.small
                  .copyWith(color: AppText.secondary, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),

          // The work first, the money second. A tier read in the other order
          // reads as an investment, which it is not.
          if (tier.commitments.isNotEmpty) ...[
            Text(
              'EVERY MONTH YOU COMMIT TO',
              style: AppType.overline.copyWith(color: AppText.caption),
            ),
            const SizedBox(height: 6),
            for (final line in tier.commitments)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· $line',
                  style: AppType.small.copyWith(color: AppText.primary),
                ),
              ),
            const SizedBox(height: 12),
          ],

          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.all(AppRadii.row),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Line(
                  label: 'Security deposit',
                  value: 'PKR ${_money(tier.securityDeposit)}',
                ),
                const SizedBox(height: 6),
                _Line(
                  label: "Your share of UDrive's commission",
                  value: '${_plain(tier.commissionSharePct)}%',
                ),
                const SizedBox(height: 6),
                _Line(label: 'Agreement runs for', value: '${tier.termMonths} months'),
                const SizedBox(height: 8),
                Text(
                  'The deposit is held, not spent, and comes back at the end. No '
                  'profit or interest is paid on it.',
                  style: AppType.caption
                      .copyWith(color: AppText.caption, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppType.caption.copyWith(color: AppText.secondary),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: AppType.small.copyWith(
            color: AppText.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _AreaList extends StatelessWidget {
  const _AreaList({
    required this.areas,
    required this.selected,
    required this.onSelect,
  });

  final List<TerritoryNode> areas;
  final TerritoryNode? selected;
  final ValueChanged<TerritoryNode> onSelect;

  @override
  Widget build(BuildContext context) {
    if (areas.isEmpty) {
      return UdCard(
        tone: UdCardTone.tint,
        padding: const EdgeInsets.all(16),
        child: Text(
          'There are no areas of this kind set up yet. Try another one, or ask '
          'us about your town.',
          style: AppType.small
              .copyWith(color: AppText.secondary, height: 1.5),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final area in areas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: UdCard(
              tone: UdCardTone.plain,
              selected: selected?.id == area.id,
              // A taken area cannot be chosen. It is still listed, with the name
              // of whoever holds it, because "who runs UDrive in Mirpur" is a
              // reasonable thing to want to know.
              onTap: area.isOpen ? () => onSelect(area) : null,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          area.name,
                          style: AppType.listTitle.copyWith(
                            color: area.isOpen
                                ? AppText.primary
                                : AppText.caption,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          area.isOpen
                              ? '${area.driverCount} drivers'
                                  '${area.waitingCount > 0 ? ' · ${area.waitingCount} waiting' : ''}'
                              : 'Taken — ${area.partnerName}',
                          style:
                              AppType.caption.copyWith(color: AppText.caption),
                        ),
                      ],
                    ),
                  ),
                  if (area.isOpen)
                    Icon(
                      selected?.id == area.id
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 22,
                      color: selected?.id == area.id
                          ? AppColors.limeLine
                          : AppColors.borderStrong,
                    )
                  else
                    Icon(Icons.lock_outline_rounded,
                        size: 19, color: AppText.caption),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _BannerTone { good, wait, warn }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.title,
    required this.body,
  });

  final _BannerTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final (background, border, ink) = switch (tone) {
      _BannerTone.good => (
          AppTint.success,
          AppTint.successBorder,
          AppTint.successText
        ),
      _BannerTone.wait => (AppTint.info, AppTint.infoBorder, AppTint.infoText),
      _BannerTone.warn => (
          AppTint.warning,
          AppTint.warningBorder,
          AppTint.warningText
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: AppRadii.all(AppRadii.card),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppType.listTitle.copyWith(color: ink),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: AppType.small.copyWith(color: ink, height: 1.5),
          ),
        ],
      ),
    );
  }
}

String _money(double value) {
  final whole = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return buffer.toString();
}

String _plain(double value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();
