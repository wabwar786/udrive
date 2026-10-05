import 'package:flutter/material.dart';

import '../../core/listings/listing_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'listing_owner_parts.dart';

/// An invited driver, on his own phone: the owner added him, he sends his
/// own CNIC, licence and selfie, and UDrive checks them.
class DriverInviteScreen extends StatefulWidget {
  const DriverInviteScreen({super.key});

  @override
  State<DriverInviteScreen> createState() => _DriverInviteScreenState();
}

const _driverAgreementFallback =
    'I hold a valid driving licence and will drive UDrive customers safely. '
    'The documents I send are my own and true. I can only be given bookings '
    'once UDrive has checked them.';

class _DriverInviteScreenState extends State<DriverInviteScreen> {
  ListingRepository? _repo;

  List<DriverInvite> _invites = const [];
  int _index = 0;
  bool _loading = true;
  String? _loadError;

  final _licenceNumber = TextEditingController();
  DateTime? _licenceExpiry;
  bool _agree = false;
  String _agreementText = _driverAgreementFallback;

  /// Shows the form again for a Rejected invite.
  bool _editing = false;
  bool _busy = false;
  String? _uploading;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = ListingRepository(AppControllerScope.of(context).apiClient);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
        _loadAgreement();
      });
    }
  }

  @override
  void dispose() {
    _licenceNumber.dispose();
    super.dispose();
  }

  static String _message(Object error) =>
      '$error'.replaceFirst('Exception: ', '');

  DriverInvite? get _invite =>
      _invites.isEmpty ? null : _invites[_index.clamp(0, _invites.length - 1)];

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final invites = await repo.invites();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _index = 0;
        _loading = false;
      });
      _prefill();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadAgreement() async {
    final repo = _repo;
    if (repo == null) return;
    final text =
        await loadOwnerPublicText(repo.api, 'listing.driver_agreement_en');
    if (!mounted || text == null) return;
    setState(() => _agreementText = text);
  }

  void _prefill() {
    final invite = _invite;
    setState(() {
      _licenceNumber.text = invite?.licenceNumber ?? '';
      _licenceExpiry = invite?.licenceExpiry;
      _agree = false;
      _editing = false;
      _error = null;
    });
  }

  void _replace(DriverInvite updated) {
    _invites = [
      for (final invite in _invites) invite.id == updated.id ? updated : invite,
    ];
  }

  Future<void> _upload(String kind) async {
    final repo = _repo;
    final invite = _invite;
    if (repo == null || invite == null) return;
    final file = await pickOwnerImage();
    if (file == null || !mounted) return;
    setState(() {
      _uploading = kind;
      _error = null;
    });
    try {
      final updated = await repo.uploadInviteDocument(invite.id, kind, file);
      if (!mounted) return;
      setState(() {
        _replace(updated);
        _uploading = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = null;
        _error = 'The photo did not upload: ${_message(error)} '
            'Tap the slot to try again.';
      });
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _licenceExpiry != null && _licenceExpiry!.isAfter(today)
        ? _licenceExpiry!
        : today.add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 20)),
    );
    if (picked == null || !mounted) return;
    setState(() => _licenceExpiry = picked);
  }

  Future<void> _submit() async {
    final repo = _repo;
    final invite = _invite;
    if (repo == null || invite == null || _busy) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = _licenceExpiry;
    String? problem;
    if (!invite.photosDone) {
      problem = 'Add your CNIC, licence (both sides) and a selfie.';
    } else if (_licenceNumber.text.trim().isEmpty) {
      problem = 'Enter your licence number.';
    } else if (expiry == null || expiry.isBefore(today)) {
      problem = 'Pick a licence expiry date that is still ahead.';
    } else if (!_agree) {
      problem = 'Accept the driver agreement to submit.';
    }
    if (problem != null || expiry == null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await repo.submitInvite(
        invite.id,
        licenceNumber: _licenceNumber.text,
        licenceExpiry: expiry,
        acceptAgreement: true,
        agreementVersion: invite.agreementVersion,
      );
      if (!mounted) return;
      setState(() {
        _replace(updated);
        _busy = false;
        _editing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _decline() async {
    final repo = _repo;
    final invite = _invite;
    if (repo == null || invite == null || _busy) return;
    final confirmed = await showUdDialog<bool>(
      context: context,
      title: 'Decline this invite?',
      message: '${invite.ownerName} will see that you declined. Your '
          'documents are not sent.',
      actions: [
        Builder(
          builder: (dialogContext) => UdButton.dark(
            label: 'Decline invite',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ),
        Builder(
          builder: (dialogContext) => UdButton.outline(
            label: 'Keep it',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.declineInvite(invite.id);
      if (!mounted) return;
      final rest = _invites.where((i) => i.id != invite.id).toList();
      if (rest.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _invites = rest;
        _index = 0;
        _busy = false;
      });
      _prefill();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    }
  }

  // ─────────────────────────────────────────────────────────── build

  bool get _showForm {
    final invite = _invite;
    if (invite == null) return false;
    if (invite.status == 'Submitted') return false;
    if (invite.status == 'Rejected') return _editing;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerNavyHeader(
            overline: 'DRIVER INVITE',
            title: invite == null
                ? 'Driver invites'
                : '${invite.ownerName} added you as a driver',
            subtitle:
                invite == null || invite.vehicles.isEmpty ? null : invite.vehicles,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: _body(invite)),
          if (invite != null && _showForm)
            UdBottomBar(
              children: [
                if (_error != null)
                  UdBanner(
                    tone: UdTone.err,
                    icon: Icons.error_outline_rounded,
                    text: _error,
                  ),
                UdButtonRow(
                  children: [
                    UdButton.outline(
                      label: 'Decline',
                      onPressed: _busy || _uploading != null ? null : _decline,
                    ),
                    UdButton.primary(
                      label: 'Submit',
                      busy: _busy,
                      onPressed: _busy || _uploading != null ? null : _submit,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _body(DriverInvite? invite) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.sidePadding),
        children: [
          UdBanner(
            tone: UdTone.err,
            icon: Icons.error_outline_rounded,
            text: _loadError,
          ),
          const SizedBox(height: 14),
          UdButton.outline(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: _load,
          ),
        ],
      );
    }
    if (invite == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            UdEmptyState(
              icon: Icons.mail_outline_rounded,
              title: 'No open invites',
              text: 'When a vehicle owner adds you as a driver, the invite '
                  'shows up here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_invites.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _invites.length; i++)
                  UdChip(
                    label: _invites[i].ownerName,
                    selected: i == _index,
                    onTap: () {
                      setState(() => _index = i);
                      _prefill();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          ..._content(invite),
        ],
      ),
    );
  }

  List<Widget> _content(DriverInvite invite) {
    if (invite.status == 'Submitted') {
      return [
        const UdBanner(
          tone: UdTone.ok,
          icon: Icons.check_circle_outline_rounded,
          text: 'Sent — UDrive will check your documents. You can be given '
              'bookings once they are approved.',
        ),
        const SizedBox(height: 16),
        UdButton.outline(
          label: 'Done',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ];
    }

    final note = invite.reviewNote;
    if (invite.status == 'Rejected' && !_editing) {
      return [
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.info_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your documents were not approved',
                style: AppType.body2.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTint.warningText,
                ),
              ),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(note),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        UdButton.primary(
          label: 'Fix and send again',
          onPressed: () => setState(() => _editing = true),
        ),
      ];
    }

    return [
      if (invite.status == 'Rejected' && note != null && note.isNotEmpty) ...[
        UdBanner(tone: UdTone.warn, icon: Icons.info_outline_rounded, text: note),
        const SizedBox(height: 14),
      ],
      _note('You can only be given bookings once UDrive has checked these. '
          'Trips start from your phone, with live location.'),
      const SizedBox(height: 14),
      const OwnerCaps('CNIC'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _slot(
                'cnic-front', 'Front', invite.cnicFront, Icons.badge_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _slot(
                'cnic-back', 'Back', invite.cnicBack, Icons.badge_outlined),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const OwnerCaps('Driving licence'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _slot(
                'licence-front', 'Front', invite.licenceFront, Icons.credit_card_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _slot(
                'licence-back', 'Back', invite.licenceBack, Icons.credit_card_rounded),
          ),
        ],
      ),
      const SizedBox(height: 12),
      UdTextField(
        controller: _licenceNumber,
        label: 'Licence no.',
        hint: 'As printed on the card',
        textCapitalization: TextCapitalization.characters,
      ),
      const SizedBox(height: 12),
      OwnerDateField(
        label: 'Expires on',
        value: _licenceExpiry,
        onTap: _pickExpiry,
      ),
      const SizedBox(height: 14),
      const OwnerCaps('A selfie'),
      const SizedBox(height: 8),
      OwnerPhotoSlot(
        label: invite.selfie ? 'Selfie' : 'Take a selfie',
        icon: Icons.face_rounded,
        height: 72,
        done: invite.selfie,
        busy: _uploading == 'selfie',
        onTap: () => _upload('selfie'),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          UdCheckbox(
            value: _agree,
            onChanged: (v) => setState(() => _agree = v),
            semanticLabel: 'I accept the driver agreement',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _agree = !_agree),
                  child: Text(
                    'I accept the ',
                    style: AppType.body2.copyWith(color: AppText.primary),
                  ),
                ),
                InkWell(
                  onTap: () => showOwnerAgreementSheet(
                    context,
                    title: 'Driver agreement',
                    text: _agreementText,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Driver agreement',
                      style: AppType.body2.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _slot(
    String kind,
    String label,
    bool done,
    IconData icon,
  ) =>
      OwnerPhotoSlot(
        label: label,
        icon: icon,
        height: 88,
        done: done,
        busy: _uploading == kind,
        onTap: () => _upload(kind),
      );

  Widget _note(String text) => Text(
        text,
        style: AppType.small.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppText.secondary,
          height: 1.45,
        ),
      );
}
