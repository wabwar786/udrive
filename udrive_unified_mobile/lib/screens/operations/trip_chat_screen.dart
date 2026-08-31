import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/booking/trip_chat_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherPartyName.trim().isEmpty
                  ? 'Trip chat'
                  : widget.otherPartyName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Messages stay with this trip',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _empty()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined,
                  size: 44, color: AppText.disabled),
              const SizedBox(height: 12),
              Text(
                widget.myRole == 'Driver'
                    ? 'Tell the passenger where you are, or ask for a landmark.'
                    : 'Send the driver a landmark, or say where exactly you are '
                        'standing.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppText.secondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Write a message',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
        decoration: BoxDecoration(
          color: mine ? AppColors.secondary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: mine ? AppText.onBrand : AppText.primary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat('h:mm a').format(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: mine
                    ? AppText.onBrand.withValues(alpha: .7)
                    : AppText.disabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
