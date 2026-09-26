import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/session_store.dart';
import '../../core/network/api_client.dart';
import '../../core/safety/safety_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/permissions/location_access.dart';

/// C-53 — Safety centre.
///
/// The emergency card stays red. Everything else in v2 is white, navy and
/// lime, but a status colour keeps its own palette, and this is the one
/// control on the screen that must not be mistaken for anything else.
class SafetyHubScreen extends StatefulWidget {
  const SafetyHubScreen({super.key});

  @override
  State<SafetyHubScreen> createState() => _SafetyHubScreenState();
}

class _SafetyHubScreenState extends State<SafetyHubScreen> {
  late final SafetyRepository repo;
  bool loading = true;
  bool sending = false;
  String? error;
  List<TrustedContact> contacts = [];

  @override
  void initState() {
    super.initState();
    repo = SafetyRepository(ApiClient(SessionStore()));
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo.contacts();
      if (mounted) setState(() => contacts = result);
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Safety details could not be loaded. Pull down to retry.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<Position?> location() async {
    try {
      // Disclosure before the prompt — see LocationAccess.
      final permission =
          await LocationAccess.ensure(context, LocationPurpose.customer);
      if (!LocationAccess.granted(permission)) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> sos() async {
    final confirmed = await showUdDialog<bool>(
      context: context,
      title: 'Activate emergency SOS?',
      message: 'Your latest location and account details will be shared with '
          'Udrive safety operations.',
      content: const Center(
        child: UdIconTile(
          icon: Icons.sos_rounded,
          tone: UdIconTone.red,
          size: UdIconTileSize.lg,
        ),
      ),
      actions: [
        UdButton(
          label: 'Send SOS',
          variant: UdButtonVariant.dangerSolid,
          onPressed: () => Navigator.pop(context, true),
        ),
        UdButton.ghost(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );
    if (confirmed != true) return;

    setState(() => sending = true);
    try {
      final position = await location();
      await repo.raiseSos(
        type: 'SOS',
        description: 'Immediate assistance requested from the mobile '
            'application.',
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracy: position?.accuracy,
      );
      if (mounted) {
        await showUdDialog<void>(
          context: context,
          title: 'SOS sent',
          message: 'Udrive safety operations have received your emergency '
              'alert.',
          barrierDismissible: false,
          content: const Center(
            child: UdIconTile(
              icon: Icons.verified_user_rounded,
              tone: UdIconTone.lime,
              size: UdIconTileSize.lg,
            ),
          ),
          actions: [
            UdButton.primary(
              label: 'Understood',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS could not be sent. Call local emergency '
                'services if you are in immediate danger.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> addContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relationship = TextEditingController();
    // The first contact somebody adds is their primary one by default.
    var primary = contacts.isEmpty;

    final saved = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add trusted contact',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 8),
              Text(
                'They are who Udrive safety operations reach if you raise an '
                'SOS.',
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 18),
              UdTextField(
                controller: name,
                label: 'Name',
                icon: Icons.person_rounded,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: phone,
                label: 'Phone number',
                icon: Icons.call_rounded,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: relationship,
                label: 'Relationship',
                labelSuffix: '(optional)',
                icon: Icons.diversity_3_rounded,
                hint: 'Family',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              UdCheckboxRow(
                value: primary,
                semanticLabel: 'Primary emergency contact',
                onChanged: (value) => setSheetState(() => primary = value),
                child: Text(
                  'Primary emergency contact',
                  style: AppType.body2.copyWith(color: AppText.primary),
                ),
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: 'Save contact',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      ),
    );

    // Unchanged: a contact with no name or no number is not saved.
    if (saved == true &&
        name.text.trim().isNotEmpty &&
        phone.text.trim().isNotEmpty) {
      await repo.addContact(
        name: name.text.trim(),
        phone: phone.text.trim(),
        relationship: relationship.text.trim().isEmpty
            ? 'Family'
            : relationship.text.trim(),
        primary: primary,
      );
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: load,
        color: AppColors.navy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
          children: [
            _EmergencyCard(sending: sending, onPressed: sending ? null : sos),
            if (error != null) ...[
              const SizedBox(height: 16),
              UdBanner(
                tone: UdTone.err,
                icon: Icons.cloud_off_rounded,
                text: error!,
              ),
            ],
            const SizedBox(height: 26),
            Row(
              children: [
                const Expanded(
                  child: UdSectionHeader(title: 'Trusted contacts'),
                ),
                const SizedBox(width: 12),
                UdButton.dark(
                  label: 'Add',
                  icon: Icons.person_add_alt_1_rounded,
                  size: UdButtonSize.xs,
                  expand: false,
                  onPressed: addContact,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.navy),
                ),
              )
            else if (contacts.isEmpty)
              const UdEmptyState(
                icon: Icons.group_add_rounded,
                title: 'No trusted contacts yet',
                text: 'Add a family member or emergency contact.',
              )
            else
              UdListGroup(
                children: [
                  for (final contact in contacts)
                    UdListRow(
                      title: contact.name,
                      subtitle: '${contact.relationship} · ${contact.phone}',
                      leading: UdAvatar(initials: _initials(contact.name)),
                      // Only the primary contact is marked — unchanged.
                      trailing: contact.isPrimary
                          ? const UdBadge(label: 'Primary', tone: UdTone.dark)
                          : null,
                    ),
                ],
              ),
            const SizedBox(height: 26),
            const UdSectionHeader(title: 'Trip safety controls'),
            const SizedBox(height: 14),
            const UdCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ControlRow(
                    icon: Icons.pin_rounded,
                    title: 'Boarding PIN',
                    text: 'Driver verifies the 4-digit customer PIN before '
                        'starting the trip.',
                  ),
                  _ControlRow(
                    icon: Icons.location_searching_rounded,
                    title: 'GPS health',
                    text: 'Customer and Admin see delayed/stale location '
                        'indicators.',
                  ),
                  _ControlRow(
                    icon: Icons.route_rounded,
                    title: 'Route monitoring',
                    text: 'Deviation and long-stop events are stored for '
                        'safety review.',
                  ),
                  _ControlRow(
                    icon: Icons.badge_outlined,
                    title: 'Driver compliance',
                    text: 'Expired licence, CNIC, registration and insurance '
                        'can restrict new rides.',
                    last: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

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

/// The one red thing on the screen.
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.sending, required this.onPressed});

  final bool sending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: AppRadii.all(AppRadii.card),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTint.dangerDeep, AppColors.danger],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: AppSizes.iconTileLg,
              height: AppSizes.iconTileLg,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // White on the red, so the tile reads as a warning sign
                // rather than a second shade of the card.
                color: AppColors.background,
                borderRadius: AppRadii.all(18),
              ),
              child: const Icon(Icons.sos_rounded,
                  size: 28, color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            Text(
              'Emergency assistance',
              style: AppType.h2.copyWith(color: AppText.onInk),
            ),
            const SizedBox(height: 8),
            Text(
              'Share your latest location and trip context with Udrive safety '
              'operations.',
              style: AppType.body2.copyWith(
                // Full white, not a muted grey: this card is red, and the
                // navy card's muted ink is not a checked pairing on it.
                color: AppText.onInk,
              ),
            ),
            const SizedBox(height: 20),
            UdButton(
              label: sending ? 'Sending…' : 'Activate SOS',
              icon: Icons.warning_amber_rounded,
              // Near-white fill, red label. A lime button here would read as
              // an ordinary confirm, and a solid red one would disappear into
              // the card it sits on.
              variant: UdButtonVariant.danger,
              busy: sending,
              onPressed: onPressed,
            ),
          ],
        ),
      );
}

/// One of the four things Udrive does on every trip, whether or not the
/// customer touches this screen. Not toggles — statements.
class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.icon,
    required this.title,
    required this.text,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UdIconTile(icon: icon, size: UdIconTileSize.sm),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppType.listTitle.copyWith(
                      fontSize: 16,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
