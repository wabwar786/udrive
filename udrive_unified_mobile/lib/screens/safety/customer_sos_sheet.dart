import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/communication/whatsapp_repository.dart';
import '../../core/safety/safety_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

class CustomerSosSheet extends StatefulWidget {
  const CustomerSosSheet({super.key});

  /// Presented with `showModalBottomSheet` rather than `showUdSheet`, because
  /// this sheet paints its own container: it needs a height cap, its own
  /// scroll region and a footer note under it. What it does take from the kit
  /// is the scrim — navy at 45%, the same dimming every other sheet uses.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppTint.scrim,
        elevation: 0,
        builder: (_) => const CustomerSosSheet(),
      );

  @override
  State<CustomerSosSheet> createState() => _CustomerSosSheetState();

  static Future<Position> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please switch on location services.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required for an emergency alert.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}

class _EmergencyNumber {
  const _EmergencyNumber({
    required this.name,
    required this.phone,
    required this.subtitle,
    required this.isOfficial,
    this.isPrimary = false,
  });

  final String name;
  final String phone;
  final String subtitle;
  final bool isOfficial;
  final bool isPrimary;
}

class _CustomerSosSheetState extends State<CustomerSosSheet> {
  late SafetyRepository _safety;
  late WhatsAppRepository _whatsApp;

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<_EmergencyNumber> _numbers = const [];

  static const _official = <_EmergencyNumber>[
    _EmergencyNumber(name: 'Rescue 1122', phone: '1122', subtitle: 'Ambulance, fire, road accidents and rescue', isOfficial: true),
    _EmergencyNumber(name: 'Police Emergency', phone: '15', subtitle: 'Police emergency helpline', isOfficial: true),
    _EmergencyNumber(name: 'AJK Tourist Helpline', phone: '05822924300', subtitle: 'Tourist assistance and coordination', isOfficial: true),
    _EmergencyNumber(name: 'AJK Tourist Helpline 2', phone: '05822921649', subtitle: 'Tourist assistance and coordination', isOfficial: true),
    _EmergencyNumber(name: 'Muzaffarabad Police Control', phone: '05822930418', subtitle: 'District police control room', isOfficial: true),
    _EmergencyNumber(name: 'Neelum Police Control', phone: '05821930000', subtitle: 'Neelum district police control room', isOfficial: true),
    _EmergencyNumber(name: 'SDMA Operations', phone: '05822921591', subtitle: 'Disaster management operations', isOfficial: true),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = AppControllerScope.of(context).apiClient;
    _safety = SafetyRepository(client);
    _whatsApp = WhatsAppRepository(client);
    if (_loading && _numbers.isEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await _safety.contacts();
      if (!mounted) return;
      setState(() {
        _numbers = [
          ..._official,
          ...contacts.map((contact) => _EmergencyNumber(
                name: contact.name,
                phone: contact.phone,
                subtitle: contact.relationship.isEmpty ? 'Personal emergency contact' : contact.relationship,
                isOfficial: false,
                isPrimary: contact.isPrimary,
              )),
        ];
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _numbers = _official;
        _loading = false;
        _error = 'Personal contacts could not be loaded. Official helplines are still available.';
      });
    }
  }

  Future<void> _call(_EmergencyNumber item) async {
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: item.phone),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call to ${item.phone}.')),
      );
    }
  }

  /// Raises the alert: a case for the safety desk, and a WhatsApp message with
  /// the customer's name and position to every personal contact they have
  /// added.
  ///
  /// This used to be a press-and-hold that recorded thirty seconds of audio and
  /// posted it to `/whatsapp/emergency-voice-broadcast`. **That endpoint does
  /// not exist in the API.** Every alert therefore 404'd on the upload and told
  /// the customer their recording "was not marked as sent" — in an emergency,
  /// after they had held the button for half a minute. The microphone, and the
  /// permission that went with it, bought nothing and cost a working SOS.
  ///
  /// One tap now, and the part that always worked is the part that runs.
  Future<void> _sendAlert() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final controller = AppControllerScope.of(context);
      final location = await CustomerSosSheet.currentLocation();
      final personalNumbers = _numbers
          .where((item) => !item.isOfficial)
          .map((item) => item.phone)
          .where((phone) => phone.trim().isNotEmpty)
          .toSet()
          .toList();

      // The case first. If the WhatsApp fan-out fails — no signal, WA Engine
      // down — the safety desk has still been told, which is the half that
      // matters most.
      await _safety.raiseSos(
        type: 'EmergencyAlert',
        description: 'Customer raised an emergency alert from the SOS sheet.',
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
      );

      final sent = await _whatsApp.emergencyBroadcast(
        numbers: personalNumbers,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracy,
        customerName: controller.currentUserName,
      );

      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            personalNumbers.isEmpty
                ? 'Udrive safety operations were notified with your location.'
                : 'Emergency alert sent to $sent personal contact(s). Udrive safety operations were notified.',
          ),
          backgroundColor: AppColors.primaryDark,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '${error.toString().replaceFirst('Exception: ', '')} '
            'If this keeps failing, call a helpline above.';
      });
    }
  }

  Future<void> _addContact() async {
    // A sheet, not a dialog. Three fields and a toggle inside an AlertDialog
    // shrank to a strip the moment the keyboard came up.
    final result = await showUdSheet<_NewContact>(
      context: context,
      builder: (_) => const _AddContactForm(),
    );
    if (result == null || !mounted) return;
    try {
      setState(() => _loading = true);
      await _safety.addContact(
        name: result.name,
        phone: result.phone,
        relationship: result.relationship,
        primary: result.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final personalCount = _numbers.where((item) => !item.isOfficial).length;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      padding: EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 12, AppSizes.sidePadding, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.sheetTop(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UdSheetHandle(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const UdIconTile(
                icon: Icons.shield_rounded,
                tone: UdIconTone.red,
                size: UdIconTileSize.lg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Emergency & safety contacts',
                      style: AppType.h2.copyWith(
                        fontSize: 20,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Call an official helpline, or send your name and live '
                      'location to your personal contacts.',
                      style:
                          AppType.body2.copyWith(color: AppText.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              UdIconButton(
                icon: Icons.close_rounded,
                variant: UdIconButtonVariant.soft,
                tooltip: 'Close',
                onPressed: _sending ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.warn,
              icon: Icons.warning_amber_rounded,
              text: _error!,
            ),
          ],
          const SizedBox(height: 16),
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child:
                          CircularProgressIndicator(color: AppColors.navy),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      // Official helplines first, then this person's own
                      // contacts — unchanged.
                      for (final item in _numbers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ContactCard(
                            item: item,
                            onCall: () => _call(item),
                          ),
                        ),
                      const SizedBox(height: 4),
                      UdButton.outline(
                        label: personalCount == 0
                            ? 'Add emergency contact'
                            : 'Add another emergency contact',
                        icon: Icons.person_add_alt_1_rounded,
                        size: UdButtonSize.small,
                        onPressed: _addContact,
                      ),
                      const SizedBox(height: 18),
                      _AlertCard(
                        sending: _sending,
                        personalCount: personalCount,
                        onSend: _sendAlert,
                      ),
                      const SizedBox(height: 14),
                      // This line replaced a press-and-hold that recorded
                      // audio to an endpoint that never existed. Saying so
                      // plainly is the point of it.
                      Text(
                        'Official helplines receive calls only. Your alert '
                        'goes to your personal emergency contacts and Udrive '
                        'safety operations. No audio is recorded.',
                        textAlign: TextAlign.center,
                        style: AppType.caption.copyWith(
                          color: AppText.caption,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One number to call. Official helplines are lime; a person's own contacts
/// are purple, which is the one hue in the app that belongs to no product —
/// on this sheet, in an emergency, "Rescue 1122" and "my brother" have to be
/// told apart at a glance, and both of them being *the app's* colours would
/// not do that.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.item, required this.onCall});

  final _EmergencyNumber item;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final accent = item.isOfficial ? AppColors.brandInk : AppTint.personal;
    final pale = item.isOfficial ? AppTint.success : AppTint.personalWash;
    final edge = item.isOfficial ? AppTint.successBorder : AppTint.personalBorder;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        border: Border.all(color: edge),
        borderRadius: AppRadii.all(AppRadii.card),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconTile,
            height: AppSizes.iconTile,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pale, shape: BoxShape.circle),
            child: Icon(
              item.isOfficial
                  ? Icons.phone_in_talk_rounded
                  : Icons.person_rounded,
              size: 22,
              color: accent,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 15.5,
                          color: AppText.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: pale,
                        borderRadius: AppRadii.all(AppRadii.chip),
                      ),
                      child: Text(
                        item.isOfficial
                            ? 'Official'
                            : item.isPrimary
                                ? 'Primary'
                                : 'My contact',
                        style: AppType.caption.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.phone} · ${item.subtitle}',
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: pale,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onCall,
              customBorder: const CircleBorder(),
              child: Tooltip(
                message: 'Call ${item.phone}',
                child: SizedBox(
                  width: AppSizes.iconTile,
                  height: AppSizes.iconTile,
                  child: Icon(Icons.call_rounded, size: 21, color: accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-tap alert: a case for the safety desk, then a WhatsApp broadcast.
class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.sending,
    required this.personalCount,
    required this.onSend,
  });

  final bool sending;
  final int personalCount;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.panel),
          border: Border.all(color: AppTint.dangerBorder, width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              'Send emergency alert',
              style: AppType.h3.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              sending
                  ? 'Sending your location…'
                  : personalCount == 0
                      ? 'Tap to alert Udrive safety operations with your '
                          'location.'
                      : 'Tap to send your name and live location to your '
                          '$personalCount emergency contact(s) and Udrive '
                          'safety operations.',
              textAlign: TextAlign.center,
              style: AppType.small.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 18),
            Semantics(
              button: true,
              enabled: !sending,
              label: 'Send emergency alert',
              child: GestureDetector(
                onTap: sending ? null : onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: sending ? AppText.disabled : AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTint.danger, width: 6),
                  ),
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.background,
                          ),
                        )
                      : const Icon(
                          Icons.sos_rounded,
                          color: AppColors.background,
                          size: 34,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _NewContact {
  const _NewContact(this.name, this.phone, this.relationship, this.primary);

  final String name;
  final String phone;
  final String relationship;
  final bool primary;
}

/// G-23 — Add emergency contact.
class _AddContactForm extends StatefulWidget {
  const _AddContactForm();

  @override
  State<_AddContactForm> createState() => _AddContactFormState();
}

class _AddContactFormState extends State<_AddContactForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _relationship = TextEditingController();
  bool _primary = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  void _save() {
    // Unchanged: a name is required, and a number of at least 7 digits.
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _NewContact(
        _name.text.trim(),
        _phone.text.trim(),
        _relationship.text.trim(),
        _primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add emergency contact',
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 8),
              Text(
                'They get your name and live location when you send an alert.',
                style: AppType.body2.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 20),
              UdTextField(
                controller: _name,
                label: 'Contact name',
                icon: Icons.person_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter contact name'
                    : null,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: _phone,
                label: 'Phone / WhatsApp number',
                icon: Icons.call_rounded,
                keyboardType: TextInputType.phone,
                validator: (value) => (value ?? '').trim().length < 7
                    ? 'Enter a valid phone number'
                    : null,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: _relationship,
                label: 'Relationship',
                labelSuffix: '(optional)',
                icon: Icons.diversity_3_rounded,
                hint: 'Brother, friend, neighbour',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 18),
              UdCheckboxRow(
                value: _primary,
                semanticLabel: 'Set as primary contact',
                onChanged: (value) => setState(() => _primary = value),
                child: Text(
                  'Set as primary contact',
                  style: AppType.body2.copyWith(color: AppText.primary),
                ),
              ),
              const SizedBox(height: 20),
              UdButtonRow(
                children: [
                  UdButton.outline(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                  UdButton.dark(label: 'Save contact', onPressed: _save),
                ],
              ),
            ],
          ),
        ),
      );
}
