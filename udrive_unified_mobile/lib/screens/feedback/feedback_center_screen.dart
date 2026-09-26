import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session_store.dart';
import '../../core/feedback/feedback_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/feedback_models.dart';

/// G-17 — Ratings & support.
///
/// Rendered inside `main_shell`, which draws the bar. It used to carry its own
/// `Scaffold` and `AppBar('Ratings & support')` as well, so the screen showed
/// two stacked bars — the same thing Explore was doing. The floating action
/// button went with it: in this design a screen's primary action lives in the
/// page, not over it.
class FeedbackCenterScreen extends StatefulWidget {
  const FeedbackCenterScreen({super.key});

  @override
  State<FeedbackCenterScreen> createState() => _FeedbackCenterScreenState();
}

class _FeedbackCenterScreenState extends State<FeedbackCenterScreen> {
  late final FeedbackRepository repo;
  bool loading = true;
  String? error;
  List<EligibleRatingBooking> eligible = [];
  List<DisputeCaseItem> cases = [];

  /// The nine categories and four priorities the API accepts. Unchanged.
  static const _categories = [
    'Service', 'Fare', 'Payment', 'Cancellation', 'Behaviour',
    'Vehicle', 'Route', 'Safety', 'Other',
  ];
  static const _priorities = ['Low', 'Normal', 'Urgent', 'Emergency'];

  @override
  void initState() {
    super.initState();
    repo = FeedbackRepository(ApiClient(SessionStore()));
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([repo.eligible(), repo.cases()]);
      if (!mounted) return;
      setState(() {
        eligible = result[0] as List<EligibleRatingBooking>;
        cases = result[1] as List<DisputeCaseItem>;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Unchanged: a trip already rated drops off the list.
    final awaiting = eligible.where((x) => !x.alreadyRated).toList();

    return RefreshIndicator(
      onRefresh: load,
      color: AppColors.navy,
      child: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
              children: [
                if (error != null) ...[
                  UdBanner(
                    tone: UdTone.err,
                    icon: Icons.cloud_off_rounded,
                    text: error!,
                  ),
                  const SizedBox(height: 16),
                ],
                UdButton.dark(
                  label: 'New complaint',
                  icon: Icons.report_problem_outlined,
                  onPressed: openCase,
                ),
                const SizedBox(height: 26),
                UdSectionHeader(
                  title: 'Trips awaiting rating',
                  caption: awaiting.isEmpty ? null : '${awaiting.length}',
                ),
                const SizedBox(height: 14),
                if (awaiting.isEmpty)
                  const UdEmptyState(
                    icon: Icons.star_outline_rounded,
                    title: 'Nothing to rate',
                    text: 'No completed trip is waiting for a rating.',
                  )
                else
                  for (final booking in awaiting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RatingCard(
                        booking: booking,
                        onRate: () => rate(booking),
                      ),
                    ),
                const SizedBox(height: 26),
                UdSectionHeader(
                  title: 'My complaints & disputes',
                  caption: cases.isEmpty ? null : '${cases.length}',
                ),
                const SizedBox(height: 14),
                if (cases.isEmpty)
                  const UdEmptyState(
                    icon: Icons.support_agent_rounded,
                    title: 'No cases open',
                    text: 'No complaint cases created.',
                  )
                else
                  for (final item in cases)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CaseCard(item: item),
                    ),
              ],
            ),
    );
  }

  Future<void> rate(EligibleRatingBooking booking) async {
    var stars = 5;
    final text = TextEditingController();

    final submitted = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rate ${booking.otherPartyName}',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                booking.bookingReference,
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => setSheetState(() => stars = i),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          i <= stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 44,
                          color: i <= stars ? AppTint.star : AppColors.borderStrong,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _starLabel(stars),
                textAlign: TextAlign.center,
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 22),
              UdTextField(
                controller: text,
                label: 'Review',
                labelSuffix: '(optional)',
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: 'Submit rating',
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (submitted == true) {
      await repo.rate(
        bookingId: booking.bookingId,
        overall: stars,
        review: text.text,
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted.')),
        );
      }
    }
  }

  static String _starLabel(int stars) => switch (stars) {
        1 => 'Very poor',
        2 => 'Poor',
        3 => 'Alright',
        4 => 'Good',
        _ => 'Excellent',
      };

  Future<void> openCase() async {
    final subject = TextEditingController();
    final description = TextEditingController();
    var category = 'Service';
    var priority = 'Normal';

    final submitted = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create complaint',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'Udrive support reads every case. Give the detail you would '
                'give a person.',
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 20),
              // The two dropdowns are chip rows now. Nine categories behind a
              // closed menu is nine things nobody knows are there, and a
              // menu inside a sheet inside a keyboard was three layers deep.
              const UdLabel('Category'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _categories)
                    UdChip(
                      label: value,
                      selected: category == value,
                      onTap: () => setSheetState(() => category = value),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const UdLabel('Priority'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _priorities)
                    UdChip(
                      label: value,
                      selected: priority == value,
                      onTap: () => setSheetState(() => priority = value),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              UdTextField(
                controller: subject,
                label: 'Subject',
                icon: Icons.title_rounded,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: description,
                label: 'What happened?',
                minLines: 4,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: 'Submit complaint',
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      ),
    );

    // Unchanged: a case with no subject or no description is not filed.
    if (submitted == true &&
        subject.text.trim().isNotEmpty &&
        description.text.trim().isNotEmpty) {
      await repo.createCase(
        category: category,
        priority: priority,
        subject: subject.text,
        description: description.text,
      );
      await load();
    }
  }
}

/// A completed trip that has not been rated yet.
class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.booking, required this.onRate});

  final EligibleRatingBooking booking;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Row(
          children: [
            const UdIconTile(icon: Icons.star_rounded, tone: UdIconTone.soft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    booking.otherPartyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.listTitle.copyWith(
                      fontSize: 16,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${booking.bookingReference} · '
                    '${DateFormat('dd MMM').format(booking.pickupAt)} · '
                    'PKR ${NumberFormat('#,###').format(booking.totalAmount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            UdButton.primary(
              label: 'Rate',
              size: UdButtonSize.xs,
              expand: false,
              onPressed: onRate,
            ),
          ],
        ),
      );
}

/// A complaint or dispute this person has opened.
class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.item});

  final DisputeCaseItem item;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.caseReference,
                    style: AppType.small.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppText.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                UdBadge(label: item.priority, tone: _priorityTone(item.priority)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.subject,
              style: AppType.h3.copyWith(fontSize: 16, color: AppText.primary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Meta(Icons.category_rounded, item.category),
                const SizedBox(width: 8),
                _Meta(Icons.flag_rounded, item.status),
              ],
            ),
            if ((item.resolutionSummary ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              UdBanner(
                tone: UdTone.ok,
                icon: Icons.check_circle_outline_rounded,
                text: item.resolutionSummary!,
              ),
            ],
          ],
        ),
      );

  static UdTone _priorityTone(String priority) => switch (priority) {
        'Emergency' => UdTone.err,
        'Urgent' => UdTone.warn,
        'Low' => UdTone.gray,
        _ => UdTone.info,
      };
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(AppRadii.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppText.secondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppType.caption.copyWith(color: AppText.primary),
            ),
          ],
        ),
      );
}
