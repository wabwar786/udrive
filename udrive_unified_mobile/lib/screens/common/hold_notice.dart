import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/holds/hold_repository.dart';
import '../../core/media/image_compressor.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../feedback/feedback_center_screen.dart';

/// The banner on a dashboard while one of the owner's vehicles, hotels or
/// businesses is back in review or suspended from the Admin's Approved page.
///
/// It says plainly that no ride or booking will come until the review is
/// done, gives the Admin's reason, and holds the two things the owner can
/// do: upload the documents the Admin asked for again, or send a re-claim
/// against a suspension. Shows nothing when there is no open hold.
class HoldNotice extends StatefulWidget {
  const HoldNotice({
    super.key,
    required this.kinds,
    this.entityId,
    this.padding = const EdgeInsets.fromLTRB(
        AppSizes.sidePadding, 10, AppSizes.sidePadding, 0),
    this.maxHeightFactor,
  });

  /// Which kinds of work this dashboard is for: city, tour, rent, hotels, businesses.
  final Set<String> kinds;

  /// Only this vehicle / hotel; null = every one of [kinds].
  final String? entityId;
  final EdgeInsets padding;

  /// When set, the notice scrolls inside this share of the screen height, so
  /// the dashboard under it stays in view.
  final double? maxHeightFactor;

  @override
  State<HoldNotice> createState() => _HoldNoticeState();
}

class _HoldNoticeState extends State<HoldNotice> {
  List<Hold> _holds = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant HoldNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId) _load();
  }

  HoldRepository get _repo =>
      HoldRepository(AppControllerScope.of(context).apiClient);

  Future<void> _load() async {
    try {
      final holds = await _repo.mine();
      if (!mounted) return;
      setState(() {
        _holds = holds;
        _loaded = true;
      });
    } catch (_) {
      // The dashboard still works; the banner simply does not show.
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final mine = _holds
        .where((h) => widget.kinds.contains(h.kind))
        .where((h) => widget.entityId == null || h.entityId == widget.entityId)
        .toList();
    if (mine.isEmpty) return const SizedBox.shrink();

    final column = Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final hold in mine) ...[
            _HoldCard(hold: hold, repo: _repo, onChanged: _load),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );

    final factor = widget.maxHeightFactor;
    if (factor == null) return column;
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * factor),
      child: SingleChildScrollView(child: column),
    );
  }
}

class _HoldCard extends StatelessWidget {
  const _HoldCard({required this.hold, required this.repo, required this.onChanged});

  final Hold hold;
  final HoldRepository repo;
  final Future<void> Function() onChanged;

  String get _thing => switch (hold.kind) {
        'hotels' => 'hotel',
        'businesses' => 'business',
        _ => 'gaari',
      };

  String get _work => switch (hold.kind) {
        'hotels' => 'koi booking nahi milegi',
        'businesses' => 'yeh customers ko nazar nahi aayega',
        'city' => 'koi ride nahi milegi',
        _ => 'koi booking nahi milegi',
      };

  @override
  Widget build(BuildContext context) {
    final review = hold.isReview;
    final ink = review ? AppTint.warningText : AppTint.dangerDeep;
    final date = DateFormat('d MMM yyyy').format(hold.createdAt);
    final aap = hold.kind == 'city' || hold.kind == 'tour' || hold.kind == 'rent'
        ? 'Aap ki'
        : 'Aap ka';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: review ? AppTint.warning : AppTint.danger,
            borderRadius: AppRadii.all(16),
            border: Border.all(
                color: review ? AppTint.warningBorder : AppTint.dangerBorder,
                width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: review ? AppTint.warningText : AppTint.dangerText,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      review ? Icons.priority_high_rounded : Icons.block_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review
                              ? '$aap $_thing dobara review mein hai'
                              : '$aap $_thing suspend hai',
                          style: AppType.h3.copyWith(
                              color: ink, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(hold.title,
                            style: AppType.small.copyWith(color: ink)),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: review
                                    ? 'Jab tak review nahi hoti, '
                                    : 'Jab tak admin dobara chalu nahi karta, '),
                            TextSpan(
                                text: _work,
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            const TextSpan(text: '.'),
                          ]),
                          style: AppType.small.copyWith(color: ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: AppRadii.all(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(
                            text: 'Wajah: ',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: hold.reason),
                      ]),
                      style: AppType.small.copyWith(color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(review ? 'Review: $date' : 'Suspend: $date',
                        style: AppType.caption.copyWith(color: ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (review)
          _ReviewPart(hold: hold, repo: repo, onChanged: onChanged)
        else
          _ClaimPart(hold: hold, repo: repo, onChanged: onChanged),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Support')),
              body: const FeedbackCenterScreen(),
            ),
          )),
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
          label: const Text('Support se baat'),
        ),
      ],
    );
  }
}

/// "Admin ne yeh maange hain": one upload button per document.
class _ReviewPart extends StatefulWidget {
  const _ReviewPart({required this.hold, required this.repo, required this.onChanged});

  final Hold hold;
  final HoldRepository repo;
  final Future<void> Function() onChanged;

  @override
  State<_ReviewPart> createState() => _ReviewPartState();
}

class _ReviewPartState extends State<_ReviewPart> {
  String? _busy;

  Future<void> _upload(HoldDocument doc) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = doc.key);
    try {
      final file = await ImageCompressor.shrink(files.first);
      final message = await widget.repo.upload(widget.hold, doc.key, file);
      _say(message);
      await widget.onChanged();
    } catch (error) {
      _say(_problem(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = 'submit');
    try {
      _say(await widget.repo.submit(widget.hold));
      await widget.onChanged();
    } catch (error) {
      _say(_problem(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final hold = widget.hold;
    if (hold.submittedAt != null) {
      return _InfoCard(
        title: 'Documents bhej diye',
        body: 'Admin dekh raha hai. Approve hote hi rides / bookings khud chalu ho jayengi.',
        chip: 'ADMIN DEKH RAHA HAI',
      );
    }
    if (hold.documents.isEmpty) {
      return const _InfoCard(
        title: 'Admin dobara check kar raha hai',
        body: 'Aap ko kuch bhejna nahi. Approve hote hi rides / bookings khud chalu ho jayengi.',
        chip: 'REVIEW',
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Admin ne yeh maange hain',
              style: AppType.listTitle.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final doc in hold.documents) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: AppRadii.all(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: doc.uploaded ? AppTint.success : Colors.white,
                      borderRadius: AppRadii.all(9),
                      border: Border.all(
                          color: doc.uploaded
                              ? AppTint.successBorder
                              : AppTint.warningBorder),
                    ),
                    child: Icon(
                      doc.uploaded ? Icons.check_rounded : Icons.priority_high_rounded,
                      size: 18,
                      color: doc.uploaded ? AppTint.successText : AppTint.warningText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(doc.label,
                        style: AppType.small.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  _busy == doc.key
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4))
                      : doc.uploaded
                          ? OutlinedButton(
                              onPressed: _busy == null ? () => _upload(doc) : null,
                              child: const Text('Badlein'))
                          : FilledButton(
                              onPressed: _busy == null ? () => _upload(doc) : null,
                              child: const Text('Upload')),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: hold.allUploaded && _busy == null ? _submit : null,
            child: _busy == 'submit'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(hold.allUploaded
                    ? 'Review ke liye bhejein'
                    : 'Pehle sab upload karein'),
          ),
          const SizedBox(height: 6),
          Text(
            'Bhejne ke baad Verification mein jaata hai; approve hote hi rides / bookings khud chalu.',
            style: AppType.caption,
          ),
        ],
      ),
    );
  }
}

/// The re-claim against a suspension, or its status once sent.
class _ClaimPart extends StatefulWidget {
  const _ClaimPart({required this.hold, required this.repo, required this.onChanged});

  final Hold hold;
  final HoldRepository repo;
  final Future<void> Function() onChanged;

  @override
  State<_ClaimPart> createState() => _ClaimPartState();
}

class _ClaimPartState extends State<_ClaimPart> {
  String _type = 'WrongReason';
  final _message = TextEditingController();
  final List<PlatformFile> _photos = [];
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final file = await ImageCompressor.shrink(files.first);
    if (mounted) setState(() => _photos.add(file));
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 5) {
      _say('Apni baat likhein.');
      return;
    }
    setState(() => _sending = true);
    try {
      _say(await widget.repo.claim(widget.hold,
          type: _type, message: text, photos: List.of(_photos)));
      _message.clear();
      _photos.clear();
      await widget.onChanged();
    } catch (error) {
      _say(_problem(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.hold.claim;
    if (claim != null && claim.pending) {
      return _InfoCard(
        title: 'Aap ki request',
        body: '"${claim.type == 'Fixed' ? 'Masla hal kar diya' : 'Wajah galat hai'}" — ${claim.message}'
            '${claim.photos > 0 ? ' · ${claim.photos} photo' : ''}\n'
            'Bheji: ${DateFormat('d MMM, h:mm a').format(claim.createdAt)}. Jawab app aur WhatsApp par aayega.',
        chip: 'ADMIN DEKH RAHA HAI',
      );
    }

    Widget option(String value, String label) {
      final on = _type == value;
      return Expanded(
        child: on
            ? FilledButton(onPressed: () {}, child: Text(label, textAlign: TextAlign.center))
            : OutlinedButton(
                onPressed: () => setState(() => _type = value),
                child: Text(label, textAlign: TextAlign.center)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Suspension par re-claim',
              style: AppType.listTitle.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Admin ko batayein — yeh wajah galat hai, ya masla hal ho gaya.',
              style: AppType.caption),
          if (claim != null && claim.rejected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTint.danger,
                borderRadius: AppRadii.all(10),
              ),
              child: Text(
                'Pichli request manzoor nahi hui'
                '${claim.adminNote == null ? '' : ' — Admin: ${claim.adminNote}'}',
                style: AppType.small.copyWith(color: AppTint.dangerDeep),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            option('WrongReason', 'Wajah galat hai'),
            const SizedBox(width: 6),
            option('Fixed', 'Masla hal kar diya'),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: 'Apni baat likhein (zaroori)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _photos.length; i++)
                InputChip(
                  label: Text('Photo ${i + 1}'),
                  onDeleted: () => setState(() => _photos.removeAt(i)),
                ),
              if (_photos.length < 3)
                OutlinedButton.icon(
                  onPressed: _sending ? null : _addPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Saboot (photo)'),
                ),
              Text('3 tak, optional', style: AppType.caption),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Request bhejein'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body, required this.chip});

  final String title;
  final String body;
  final String chip;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: AppType.listTitle.copyWith(fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTint.warning,
                    borderRadius: AppRadii.all(8),
                  ),
                  child: Text(chip,
                      style: AppType.caption.copyWith(
                          color: AppTint.warningText, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: AppType.small),
          ],
        ),
      );
}

String _problem(Object error) {
  final text = '$error'.replaceFirst(RegExp(r'^(ApiException|Exception):\s*'), '');
  return text.isEmpty ? 'Kuch ghalat ho gaya. Dobara koshish karein.' : text;
}
