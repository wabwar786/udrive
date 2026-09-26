import 'package:flutter/material.dart';

import '../../core/feedback/feedback_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// Rating the driver, once the trip is over.
///
/// Replaces the map rather than sitting on top of it. The moment a trip
/// completes the map has nothing left to say — the car is here, the journey is
/// done — and leaving it there makes the rating look optional, which is how a
/// platform ends up with no ratings at all.
///
/// The stars and words collected here are exactly what the next customer sees
/// on the tracking screen before this driver arrives. That is worth saying out
/// loud on the screen, because a review that visibly goes somewhere gets
/// written more often than one that disappears into a form.
class TripRatingScreen extends StatefulWidget {
  const TripRatingScreen({
    required this.bookingId,
    required this.driverName,
    required this.vehicle,
    required this.fare,
    super.key,
  });

  final String bookingId;
  final String driverName;
  final String vehicle;
  final double fare;

  @override
  State<TripRatingScreen> createState() => _TripRatingScreenState();
}

class _TripRatingScreenState extends State<TripRatingScreen> {
  final _review = TextEditingController();

  int _overall = 0;
  bool _sending = false;
  bool _done = false;
  String? _error;

  /// Quick reasons, offered only once the rating makes them relevant.
  ///
  /// Different lists for good and bad, because "clean vehicle" is not a useful
  /// prompt for someone who just gave two stars, and asking a happy customer
  /// what went wrong invites a complaint that was not there.
  static const _praise = [
    'Drove safely',
    'On time',
    'Clean vehicle',
    'Polite',
    'Knew the route',
  ];

  static const _concerns = [
    'Drove too fast',
    'Arrived late',
    'Vehicle not clean',
    'Rude',
    'Took a longer route',
  ];

  final Set<String> _tags = <String>{};

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  List<String> get _tagOptions => _overall >= 4 ? _praise : _concerns;

  Future<void> _submit() async {
    if (_overall == 0 || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    // Tags are folded into the review text rather than sent as a separate
    // field. The ratings table has no tag column, and inventing one for five
    // fixed phrases would be a migration for something a sentence already says.
    final parts = <String>[
      if (_tags.isNotEmpty) _tags.join(', '),
      if (_review.text.trim().isNotEmpty) _review.text.trim(),
    ];

    try {
      final controller = AppControllerScope.of(context);
      await FeedbackRepository(controller.apiClient).rate(
        bookingId: widget.bookingId,
        overall: _overall,
        review: parts.isEmpty ? null : parts.join(' · '),
      );
      if (!mounted) return;
      setState(() {
        _done = true;
        _sending = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _done ? _thanks() : _form()),
    );
  }

  Widget _thanks() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: UdIconTile(
                  icon: Icons.check_circle_rounded,
                  tone: UdIconTone.lime,
                  size: UdIconTileSize.lg,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Thank you',
                textAlign: TextAlign.center,
                style: AppType.h1.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 10),
              Text(
                'Your rating goes on ${widget.driverName}’s profile, where '
                'the next customer will see it.',
                textAlign: TextAlign.center,
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 28),
              UdButton.primary(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 28, AppSizes.sidePadding, 20),
            children: [
              Text(
                'TRIP COMPLETED',
                style: AppType.overline.copyWith(color: AppColors.brandInk),
              ),
              const SizedBox(height: 12),
              Text(
                'How was your ride with ${widget.driverName}?',
                style: AppType.h1.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 14),
              // Who and what, under the headline. The driver was text-only
              // before; the name, vehicle and fare all already arrive here.
              Row(
                children: [
                  UdAvatar(initials: _initials(widget.driverName), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.vehicle} · '
                      'PKR ${widget.fare.toStringAsFixed(0)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppText.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var star = 1; star <= 5; star++)
                    IconButton(
                      onPressed: () => setState(() {
                        _overall = star;
                        // The tag list changes with the rating, so keeping
                        // selections from the other list would attach "polite"
                        // to a one-star review.
                        _tags.clear();
                      }),
                      iconSize: 44,
                      tooltip: '$star star${star == 1 ? '' : 's'}',
                      icon: Icon(
                        star <= _overall
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        // Gold when it counts, and the strong hairline grey
                        // when it does not — the disabled ink is for text.
                        color: star <= _overall
                            ? AppTint.star
                            : AppColors.borderStrong,
                      ),
                    ),
                ],
              ),
              // The whole lower half appears only once a star is picked.
              if (_overall > 0) ...[
                const SizedBox(height: 8),
                Text(
                  switch (_overall) {
                    1 => 'Bad',
                    2 => 'Poor',
                    3 => 'Fine',
                    4 => 'Good',
                    _ => 'Excellent',
                  },
                  textAlign: TextAlign.center,
                  style: AppType.h3.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  _overall >= 4 ? 'What went well?' : 'What went wrong?',
                  style: AppType.section.copyWith(
                    fontSize: 17,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tag in _tagOptions)
                      UdChip(
                        label: tag,
                        selected: _tags.contains(tag),
                        onTap: () => setState(() {
                          if (!_tags.remove(tag)) _tags.add(tag);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                UdTextField(
                  controller: _review,
                  hint: 'Anything you want the next customer to know? '
                      '(optional)',
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                UdBanner(
                  tone: UdTone.err,
                  icon: Icons.error_outline_rounded,
                  text: _error!,
                ),
              ],
            ],
          ),
        ),
        UdBottomBar(
          children: [
            UdButton.primary(
              label: 'Submit rating',
              busy: _sending,
              // Disabled until a star is picked — unchanged.
              onPressed: _overall == 0 ? null : _submit,
            ),
            // Skipping is allowed and says so plainly. A rating screen with no
            // way out is one people learn to close by killing the app, and
            // that loses the trip summary too.
            UdButton.ghost(
              label: 'Skip for now',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ],
    );
  }

  /// The same two-letter rule the shell's avatar uses.
  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'U';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}
