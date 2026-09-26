import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/booking/trip_chat_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// Messages between the two people on one trip.
///
/// One screen for both sides. The only thing that differs is which role counts
/// as "mine", and that arrives as a parameter — two near-identical screens
/// would drift apart the first time either was touched.
///
/// Scoped to a booking, and there is no inbox anywhere. A driver cannot reach a
/// customer after the ride, which is the point rather than a limitation.
class TripChatScreen extends StatefulWidget {
  const TripChatScreen({
    required this.bookingId,
    required this.myRole,
    required this.otherPartyName,
    super.key,
  });

  final String bookingId;

  /// 'Customer' or 'Driver' — whichever the person on this device is.
  final String myRole;

  final String otherPartyName;

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<TripMessage> _messages = const [];
  Timer? _poller;
  bool _sending = false;
  bool _loading = true;
  String? _error;

  TripChatRepository get _repository =>
      TripChatRepository(AppControllerScope.of(context).apiClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial: true));
    // Three seconds. A message that arrives while someone is standing on a
    // roadside looking for a car is worth a poll; a websocket for a
    // conversation that lasts one trip is not worth the infrastructure.
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      // Only what is newer than the last message held, so a poll on a quiet
      // conversation transfers nothing.
      final after = initial || _messages.isEmpty ? null : _messages.last.createdAt;
      final fresh = await _repository.messages(widget.bookingId, after: after);

      if (!mounted) return;
      if (fresh.isEmpty && !initial) {
        if (_loading) setState(() => _loading = false);
        return;
      }

      setState(() {
        _messages = after == null ? fresh : [..._messages, ...fresh];
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);
    // Cleared immediately. Leaving the text in place while the request is in
    // flight invites a second tap and a duplicate message.
    _input.clear();

    try {
      final message = await _repository.send(widget.bookingId, body);
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      // Put the text back. Losing what someone typed because the network
      // hiccuped is the worst thing a chat box can do.
      _input.text = body;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.otherPartyName.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      // A pushed page, so it keeps its own Scaffold and draws its own bar.
      appBar: UdTopBar(
        title: name.isEmpty ? 'Trip chat' : name,
        onBack: () => Navigator.maybePop(context),
        divider: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The bar's own subtitle. `UdTopBar` carries one line, and this is
          // the thing worth saying about this screen: the thread ends with
          // the trip, and nobody can reach anybody afterwards.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 10, AppSizes.sidePadding, 0),
            child: Text(
              'Messages stay with this trip',
              style: AppType.caption.copyWith(color: AppText.caption),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 12, AppSizes.sidePadding, 0),
              child: UdBanner(
                tone: UdTone.err,
                icon: Icons.cloud_off_rounded,
                text: _error!,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.navy),
                  )
                : _messages.isEmpty
                    ? _empty()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                            AppSizes.sidePadding, 16, AppSizes.sidePadding, 10),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return _Bubble(
                            message: message,
                            mine: message.senderRole == widget.myRole,
                          );
                        },
                      ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: UdEmptyState(
            icon: Icons.forum_outlined,
            title: 'No messages yet',
            text: widget.myRole == 'Driver'
                ? 'Tell the passenger where you are, or ask for a landmark.'
                : 'Send the driver a landmark, or say where exactly you are '
                    'standing.',
          ),
        ),
      );

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 12, AppSizes.sidePadding, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: AppSizes.buttonSmall),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.all(AppRadii.chip),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _send(),
                    cursorColor: AppColors.navy,
                    style: AppType.body2.copyWith(
                      fontSize: 15.5,
                      color: AppText.primary,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Write a message',
                      hintStyle: AppType.body2.copyWith(
                        fontSize: 15.5,
                        color: AppText.caption,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // A plain sized box with an InkWell, not a FilledButton.
              //
              // The app's FilledButton theme sets `minimumSize:
              // Size.fromHeight(54)`, which is `Size(infinity, 54)`. In a Row
              // that button demands infinite width, so the Expanded field
              // beside it collapsed to a few pixels and the button itself was
              // pushed off the right edge — which is why this composer looked
              // like an empty strip with a stray line in the corner.
              Material(
                // Navy with a lime glyph. This was AppColors.secondary — the
                // deep lime — carrying AppText.onBrand, which is navy: navy
                // on dark olive, about 2:1. The pair is checked this way
                // round, not that one.
                color: AppColors.navy,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _sending ? null : _send,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: AppSizes.buttonSmall,
                    height: AppSizes.buttonSmall,
                    child: Center(
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brand,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: AppColors.brand,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One message. Mine is navy with white on it; theirs is the grey inset with
/// navy on it.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final TripMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .76,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 9),
        decoration: BoxDecoration(
          // Was AppColors.secondary — the deep lime — with navy text on it,
          // which is about 2:1 and unreadable in sunlight. Navy and white is
          // 15.9:1, and it is what the design draws.
          color: mine ? AppColors.navy : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: AppRadii.all(AppRadii.field).topLeft,
            topRight: AppRadii.all(AppRadii.field).topRight,
            bottomLeft: Radius.circular(mine ? 16 : 5),
            bottomRight: Radius.circular(mine ? 5 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: AppType.body2.copyWith(
                fontSize: 15,
                color: mine ? AppText.onInk : AppText.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('h:mm a').format(message.createdAt),
              style: AppType.caption.copyWith(
                fontSize: 12.5,
                color: mine ? AppText.onInkMuted : AppText.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
