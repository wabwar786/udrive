import 'package:flutter/material.dart';

import '../../core/auth/session_store.dart';
import '../../core/communication/communication_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/network/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/communication_models.dart';
import 'delete_account_screen.dart';
import 'legal_screen.dart';

/// G-10 — Notifications.
///
/// Rendered inside `main_shell`, which draws the bar, so there is no
/// `Scaffold` here.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final CommunicationRepository repo;
  bool loading = true;
  String? error;
  NotificationPage page = const NotificationPage([], 0);

  @override
  void initState() {
    super.initState();
    repo = CommunicationRepository(ApiClient(SessionStore()));
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo.notifications();
      if (mounted) setState(() => page = result);
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Notifications could not be loaded. Pull down to retry.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Unchanged: the type string decides the glyph.
  IconData icon(String type) {
    final t = type.toLowerCase();
    if (t.contains('message')) return Icons.chat_bubble_rounded;
    if (t.contains('offer')) return Icons.local_offer_rounded;
    if (t.contains('driver')) return Icons.directions_car_rounded;
    if (t.contains('complaint') || t.contains('dispute')) {
      return Icons.support_agent_rounded;
    }
    if (t.contains('payment') || t.contains('payout')) {
      return Icons.account_balance_wallet_rounded;
    }
    return Icons.notifications_rounded;
  }

  String time(DateTime x) {
    final d = DateTime.now().difference(x.toLocal());
    if (d.inMinutes < 1) return 'Now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} hr ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

  Future<void> _open(UserNotification item) async {
    if (item.isRead) return;
    await repo.markRead(item.id);
    await load();
  }

  @override
  Widget build(BuildContext context) {
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
                // The count row only exists while something is unread — with
                // nothing to mark, "Mark all read" is a button that does
                // nothing and a "0 unread" line that says nothing.
                if (page.unreadCount > 0) ...[
                  UdSectionHeader(
                    title: '${page.unreadCount} unread',
                    actionLabel: 'Mark all read',
                    onAction: () async {
                      await repo.markAllRead();
                      await load();
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                if (page.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: UdEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No notifications yet',
                      text: 'Trip, offer and account updates will appear here.',
                    ),
                  )
                else ...[
                  UdListGroup(
                    children: [
                      for (final item in page.items)
                        _NotificationRow(
                          item: item,
                          icon: icon(item.type),
                          time: time(item.createdAt),
                          onTap: () => _open(item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const UdBanner(
                    tone: UdTone.gray,
                    icon: Icons.refresh_rounded,
                    text: 'Pull down to check for new updates.',
                  ),
                ],
              ],
            ),
    );
  }
}

/// One notification. Unread sits on the grey inset with a red dot; read is
/// white with a soft tile, so the two are told apart by more than the dot.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.icon,
    required this.time,
    required this.onTap,
  });

  final UserNotification item;
  final IconData icon;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;

    return Material(
      color: unread ? AppColors.surface : AppColors.surfaceHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UdIconTile(
                icon: icon,
                tone: unread ? UdIconTone.navy : UdIconTone.neutral,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: AppType.listTitle.copyWith(
                              fontSize: 16,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      time,
                      style: AppType.caption.copyWith(color: AppText.caption),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// SupportScreen was here. It told the person on screen that "Dummy chat,
// ticket and emergency help options are active", and answered anything
// they typed with "a demo support ticket has been created". Support now
// opens FeedbackCenterScreen, which files a real case.

/// G-11 — Settings.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final language = controller.locale.languageCode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
      children: [
        UdSectionHeader(title: context.tr('language')),
        const SizedBox(height: 14),
        UdListGroup(
          children: [
            for (final option in <(String, String)>[
              ('en', context.tr('english')),
              ('ur', context.tr('urdu')),
            ])
              UdListRow(
                title: option.$2,
                trailing: UdRadio(
                  selected: language == option.$1,
                  onTap: () => controller.setLanguage(option.$1),
                ),
                onTap: () => controller.setLanguage(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 26),
        UdSectionHeader(title: context.tr('settings')),
        const SizedBox(height: 14),
        // Privacy and Terms open inside the app, from the copy bundled with it,
        // so they work with no connection — which is the state somebody is most
        // likely to be in when they suddenly want to know what we do with their
        // CNIC. The same documents are served by the API at /privacy and /terms,
        // which is the URL on the Play listing, and the reader has an "open
        // online" button for that.
        UdListGroup(
          children: [
            UdListRow(
              title: context.tr('privacy'),
              leading: const UdIconTile(icon: Icons.lock_rounded),
              showChevron: true,
              onTap: () => LegalScreen.open(context, 'privacy-policy'),
            ),
            UdListRow(
              title: context.tr('terms'),
              leading: const UdIconTile(icon: Icons.description_rounded),
              showChevron: true,
              onTap: () => LegalScreen.open(context, 'terms'),
            ),
            UdListRow(
              title: context.tr('about'),
              leading: const UdIconTile(icon: Icons.info_rounded),
              showChevron: true,
              onTap: () => showAboutDialog(
                context: context,
                applicationName: AppConfig.appName,
                applicationVersion: AppConfig.buildLabel,
                applicationLegalese: '© Tech Geni Ltd.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const UdSectionHeader(title: 'Account'),
        const SizedBox(height: 14),
        UdListGroup(
          children: [
            UdListRow(
              title: 'Delete account',
              subtitle: 'Permanently remove your account and personal data',
              titleColor: AppColors.danger,
              leading: const UdIconTile(
                icon: Icons.delete_forever_rounded,
                tone: UdIconTone.red,
              ),
              showChevron: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            '${AppConfig.appName} · ${AppConfig.buildLabel}',
            style: AppType.caption.copyWith(color: AppText.caption),
          ),
        ),
      ],
    );
  }
}
