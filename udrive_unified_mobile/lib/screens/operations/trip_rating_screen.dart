import 'package:flutter/material.dart';

import '../../core/feedback/feedback_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

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
      body: SafeArea(
        child: _done ? _thanks() : _form(),
      ),
    );
  }

  Widget _thanks() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 64, color: AppColors.success),
              const SizedBox(height: 18),
              const Text(
                'Thank you',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your rating goes on ${widget.driverName}\u2019s profile, where '
                'the next customer will see it.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.55,
                  color: AppText.secondary,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _form() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            children: [
              const Text(
                'Trip completed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'How was your ride with ${widget.driverName}?',
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                  color: AppText.primary,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '${widget.vehicle}  ·  PKR ${widget.fare.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppText.secondary,
                ),
              ),

              const SizedBox(height: 30),
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
                      icon: Icon(
                        star <= _overall
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: star <= _overall
                            ? AppColors.secondary
                            : AppText.disabled,
                      ),
                    ),
                ],
              ),

              if (_overall > 0) ...[
                const SizedBox(height: 6),
                Text(
                  switch (_overall) {
                    1 => 'Bad',
                    2 => 'Poor',
                    3 => 'Fine',
                    4 => 'Good',
                    _ => 'Excellent',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in _tagOptions)
                      _Tag(
                        label: tag,
                        selected: _tags.contains(tag),
                        onTap: () => setState(() {
                          if (!_tags.remove(tag)) _tags.add(tag);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _review,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  style: const TextStyle(color: AppText.primary),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'Anything you want the next customer to know? '
                        '(optional)',
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
            ],
          ),
        ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _overall == 0 || _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit rating'),
                  ),
                ),
                TextButton(
                  // Skipping is allowed and says so plainly. A rating screen
                  // with no way out is one people learn to close by killing the
                  // app, and that loses the trip summary too.
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip for now'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
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
      color: selected ? AppTint.brand : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? AppColors.secondary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.secondary : AppText.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
