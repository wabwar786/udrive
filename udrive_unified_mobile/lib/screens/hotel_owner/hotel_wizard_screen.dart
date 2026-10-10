import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/areas/area_picker.dart';
import '../../core/areas/area_repository.dart';
import '../../core/format/money.dart';
import '../../core/hotels/hotel_owner_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';
import '../listing/listing_owner_parts.dart' show pickOwnerImage;
import 'hotel_owner_profile_screen.dart';
import 'hotel_owner_shell.dart' show leaveHotelMode;
import 'hotel_pin_screen.dart';

/// Opens the hotel wizard: a new hotel when [hotelId] is null, otherwise that
/// hotel for editing.
///
/// A new hotel needs the owner profile first (the admin checks the owner and
/// the hotel together), so an incomplete profile opens that screen and the
/// wizard follows once it is done.
Future<void> openHotelWizard(BuildContext context, {String? hotelId}) async {
  final navigator = Navigator.of(context);
  if (hotelId == null) {
    final repo = HotelOwnerRepository(AppControllerScope.of(context).apiClient);
    try {
      final profile = await repo.profile();
      if (!profile.complete) {
        final done = await navigator.push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const HotelOwnerProfileScreen()),
        );
        if (done != true) return;
      }
    } catch (_) {
      // Offline or a server hiccup: let the owner start the hotel anyway. The
      // profile is checked again on Submit.
    }
  }
  await navigator.push<void>(
    MaterialPageRoute<void>(builder: (_) => HotelWizardScreen(hotelId: hotelId)),
  );
}

/// H-02 — a hotel in five steps and a review.
///
///   1 Basic      name, type, description
///   2 Location   map pin, address, district / tehsil
///   3 Photos     gallery upload, 3 to 9, the first is the main one
///   4 Rooms      room types with capacity, count and Rs / night
///   5 Rules      amenities, check-in / check-out, booking WhatsApp number
///   Review       every part with "Badlein", then "Admin ko bhejein"
///
/// Each step saves to the server when the owner presses Aage, so nothing is
/// lost if they stop half way.
class HotelWizardScreen extends StatefulWidget {
  const HotelWizardScreen({this.hotelId, super.key});

  final String? hotelId;

  @override
  State<HotelWizardScreen> createState() => _HotelWizardScreenState();
}

class _HotelWizardScreenState extends State<HotelWizardScreen> {
  static const _review = 5;
  static const _stepNames = ['Basic', 'Location', 'Photos', 'Rooms & kiraya', 'Sahuliyat & rules'];
  static const _types = ['Hotel', 'Guest house', 'Resort', 'Hut'];
  static const _amenityChoices = [
    'WiFi',
    'Parking',
    'Garam pani',
    'Heater',
    'Restaurant',
    'Room service',
    'Family friendly',
  ];

  late final HotelOwnerRepository _repo =
      HotelOwnerRepository(AppControllerScope.of(context).apiClient);

  OwnerHotelDraft? _draft;
  int _step = 0;
  bool _fromReview = false;
  bool _loading = false;
  bool _busy = false;
  String? _uploading;
  String? _error;

  // Step 1
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _type = 'Hotel';

  // Step 2
  final _address = TextEditingController();
  LatLng? _pin;
  AreaSelection? _area;

  // Step 4 — the "new room type" form
  final _roomType = TextEditingController();
  final _roomPeople = TextEditingController(text: '2');
  final _roomCount = TextEditingController(text: '1');
  final _roomRate = TextEditingController();

  // Step 5
  final Set<String> _amenities = {};
  bool _pickup = true;
  String? _checkIn = '14:00';
  String? _checkOut = '12:00';
  final _bookingPhone = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.hotelId != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bookingPhone.text = _local(AppControllerScope.of(context).currentUserPhone);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _roomType, _roomPeople, _roomCount, _roomRate, _bookingPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final draft = await _repo.hotel(widget.hotelId!);
      if (!mounted) return;
      setState(() {
        _fill(draft);
        _loading = false;
        _step = draft.status == 'Draft' ? _firstIncompleteStep(draft) : _review;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// Copies a server answer into the form.
  void _fill(OwnerHotelDraft draft) {
    _draft = draft;
    _name.text = draft.name;
    _description.text = draft.description;
    _type = _types.contains(draft.propertyType) ? draft.propertyType : 'Hotel';
    _address.text = draft.address;
    _pin = draft.latitude == null ? null : LatLng(draft.latitude!, draft.longitude!);
    _amenities
      ..clear()
      ..addAll(draft.amenities);
    _pickup = draft.transportAvailable;
    _checkIn = draft.checkInTime ?? _checkIn;
    _checkOut = draft.checkOutTime ?? _checkOut;
    if (draft.contactPhone.isNotEmpty) _bookingPhone.text = _local(draft.contactPhone);
  }

  int _firstIncompleteStep(OwnerHotelDraft d) {
    bool has(String word) => d.missing.any((m) => m.contains(word));
    if (has('naam') || has('description')) return 0;
    if (has('pin') || has('address') || has('city')) return 1;
    if (has('photos')) return 2;
    if (has('room')) return 3;
    if (has('WhatsApp')) return 4;
    return _review;
  }

  // ─────────────────────────────────────────────── navigation

  void _back() {
    if (_busy) return;
    if (_fromReview && _step != _review) {
      setState(() {
        _step = _review;
        _fromReview = false;
        _error = null;
      });
      return;
    }
    if (_step == 0 || (_step == _review && _draft != null && _draft!.status != 'Draft' && widget.hotelId != null)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step = _step == _review ? 4 : _step - 1;
      _error = null;
    });
  }

  void _goTo(int step) => setState(() {
        _step = step;
        _fromReview = true;
        _error = null;
      });

  void _advance() => setState(() {
        _step = _fromReview ? _review : _step + 1;
        _fromReview = false;
        _error = null;
      });

  Future<void> _run(Future<OwnerHotelDraft> Function() call, {bool advance = false, String? busyKey}) async {
    setState(() {
      _busy = busyKey == null;
      _uploading = busyKey;
      _error = null;
    });
    try {
      final draft = await call();
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _busy = false;
        _uploading = null;
      });
      if (advance) _advance();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _uploading = null;
        _error = '$error';
      });
    }
  }

  // ─────────────────────────────────────────────── steps → server

  Future<void> _saveBasic() async {
    final name = _name.text.trim();
    final description = _description.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Hotel ka naam likhein.');
      return;
    }
    if (description.length < 10) {
      setState(() => _error = 'Description thori aur likhein (kam az kam 10 harf).');
      return;
    }
    final values = {'name': name, 'propertyType': _type, 'description': description};
    final id = _draft?.id;
    await _run(() => id == null ? _repo.create(values) : _repo.update(id, values), advance: true);
  }

  Future<void> _pickPin() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(builder: (_) => HotelPinScreen(initial: _pin)),
    );
    if (point != null && mounted) setState(() => _pin = point);
  }

  Future<void> _saveLocation() async {
    final draft = _draft!;
    if (_pin == null) {
      setState(() => _error = 'Map par pin lagayein.');
      return;
    }
    if (_address.text.trim().length < 3) {
      setState(() => _error = 'Address likhein.');
      return;
    }
    final area = _area;
    if (area == null && (draft.city.isEmpty || draft.district.isEmpty)) {
      setState(() => _error = 'District aur tehsil chunein.');
      return;
    }
    await _run(
      () => _repo.update(draft.id, {
        'address': _address.text.trim(),
        'latitude': _pin!.latitude,
        'longitude': _pin!.longitude,
        if (area != null) 'district': area.districtName,
        if (area != null) 'city': area.tehsilName,
      }),
      advance: true,
    );
  }

  Future<void> _addPhoto() async {
    final file = await pickOwnerImage();
    if (file == null || !mounted) return;
    await _run(() => _repo.addPhoto(_draft!.id, file), busyKey: 'photo');
  }

  Future<void> _photoActions(OwnerHotelPhoto photo) async {
    final choice = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!photo.isMain) ...[
            UdButton.primary(
              label: 'Main photo banayein',
              icon: Icons.star_rounded,
              onPressed: () => Navigator.pop(sheetContext, 'main'),
            ),
            const SizedBox(height: 10),
          ],
          UdButton(
            label: 'Photo hatayein',
            icon: Icons.delete_outline_rounded,
            variant: UdButtonVariant.danger,
            onPressed: () => Navigator.pop(sheetContext, 'remove'),
          ),
          const SizedBox(height: 10),
          UdButton.soft(label: 'Rehne dein', onPressed: () => Navigator.pop(sheetContext)),
        ],
      ),
    );
    if (choice == 'main') await _run(() => _repo.mainPhoto(_draft!.id, photo.id), busyKey: 'photo');
    if (choice == 'remove') await _run(() => _repo.removePhoto(_draft!.id, photo.id), busyKey: 'photo');
  }

  void _photosNext() {
    if (_draft!.photos.length < 3) {
      setState(() => _error = 'Kam az kam 3 photos lagayein — bahar, kamra, washroom.');
      return;
    }
    _advance();
  }

  Future<void> _addRoom() async {
    final type = _roomType.text.trim();
    final people = int.tryParse(_roomPeople.text.trim()) ?? 0;
    final count = int.tryParse(_roomCount.text.trim()) ?? 0;
    final rate = double.tryParse(_roomRate.text.replaceAll(',', '').trim()) ?? 0;
    if (type.length < 2) {
      setState(() => _error = 'Room type likhein, jaise Double room.');
      return;
    }
    if (people < 1 || people > 20) {
      setState(() => _error = 'Ek kamre mein 1 se 20 log.');
      return;
    }
    if (count < 1 || count > 500) {
      setState(() => _error = 'Kamre 1 se 500 tak.');
      return;
    }
    if (rate < 1) {
      setState(() => _error = 'Rs / raat likhein.');
      return;
    }
    await _run(() => _repo.saveRoom(_draft!.id, roomType: type, capacity: people, totalRooms: count, baseRate: rate));
    if (_error == null && mounted) {
      _roomType.clear();
      _roomPeople.text = '2';
      _roomCount.text = '1';
      _roomRate.clear();
    }
  }

  Future<void> _editRoom(OwnerHotelRoomType room) async {
    final type = TextEditingController(text: room.roomType);
    final people = TextEditingController(text: '${room.capacity}');
    final count = TextEditingController(text: '${room.totalRooms}');
    final rate = TextEditingController(text: room.baseRate.toStringAsFixed(0));
    final choice = await showUdSheet<String>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Room type badlein', style: AppType.h3.copyWith(color: AppText.primary)),
            const SizedBox(height: 12),
            UdTextField(controller: type, label: 'Type'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: UdTextField(controller: people, label: 'Log', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: UdTextField(controller: count, label: 'Kamre', keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            UdTextField(controller: rate, label: 'Rs / raat', keyboardType: TextInputType.number),
            const SizedBox(height: 14),
            UdButton.primary(label: 'Save', onPressed: () => Navigator.pop(sheetContext, 'save')),
            const SizedBox(height: 8),
            UdButton.outline(
              label: 'Is room ki photo',
              icon: Icons.photo_camera_outlined,
              onPressed: () => Navigator.pop(sheetContext, 'photo'),
            ),
            const SizedBox(height: 8),
            UdButton(
              label: 'Room type hatayein',
              variant: UdButtonVariant.danger,
              onPressed: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );
    final id = _draft!.id;
    if (choice == 'save') {
      await _run(() => _repo.saveRoom(
            id,
            roomId: room.id,
            roomType: type.text.trim(),
            capacity: int.tryParse(people.text.trim()) ?? room.capacity,
            totalRooms: int.tryParse(count.text.trim()) ?? room.totalRooms,
            baseRate: double.tryParse(rate.text.replaceAll(',', '').trim()) ?? room.baseRate,
          ));
    } else if (choice == 'photo') {
      final file = await pickOwnerImage();
      if (file != null && mounted) await _run(() => _repo.roomPhoto(id, room.id, file), busyKey: 'room-${room.id}');
    } else if (choice == 'remove') {
      await _run(() => _repo.removeRoom(id, room.id));
    }
    // After the sheet's closing animation, which still draws these fields.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      for (final c in [type, people, count, rate]) {
        c.dispose();
      }
    });
  }

  void _roomsNext() {
    if (_draft!.rooms.isEmpty) {
      setState(() => _error = 'Kam az kam ek room type add karein.');
      return;
    }
    _advance();
  }

  Future<void> _pickTime(bool checkIn) async {
    final current = (checkIn ? _checkIn : _checkOut) ?? (checkIn ? '14:00' : '12:00');
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 12, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
    );
    if (picked == null || !mounted) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (checkIn) {
        _checkIn = value;
      } else {
        _checkOut = value;
      }
    });
  }

  Future<void> _saveRules() async {
    final digits = _bookingPhone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^(03\d{9}|923\d{9}|3\d{9})$').hasMatch(digits)) {
      setState(() => _error = 'Booking WhatsApp number sahi likhein, jaise 03001234567.');
      return;
    }
    await _run(
      () => _repo.update(_draft!.id, {
        'amenities': _amenities.toList(),
        'transportAvailable': _pickup,
        'checkInTime': _checkIn ?? '',
        'checkOutTime': _checkOut ?? '',
        'contactPhone': _bookingPhone.text.trim(),
      }),
      advance: true,
    );
  }

  Future<void> _submit() async {
    final draft = _draft!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await _repo.submit(draft.id);
      if (!mounted) return;
      setState(() {
        _draft = sent;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Admin ko bhej diya. Approve hote hi customers ko nazar aaye ga.'),
      ));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final text = '$error';
      setState(() {
        _busy = false;
        _error = text;
      });
      if (text.toLowerCase().contains('owner profile')) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const HotelOwnerProfileScreen()),
        );
      }
    }
  }

  // ─────────────────────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: UdTopBar(
          title: _step == _review
              ? (widget.hotelId != null && _draft?.status != 'Draft' ? 'Hotel edit' : 'Review & bhejein')
              : 'Hotel add karein',
          onBack: _back,
          actions: [
            UdIconButton(
              icon: Icons.home_rounded,
              tooltip: 'Customer Home',
              small: true,
              onPressed: () => leaveHotelMode(context, UserMode.customer),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
                children: [
                  if (_step != _review) ...[
                    Text('Step ${_step + 1} / 5 · ${_stepNames[_step]}',
                        style: AppType.caption.copyWith(fontWeight: FontWeight.w700, color: AppText.secondary)),
                    const SizedBox(height: 6),
                    UdSteps(total: 5, current: _step),
                    const SizedBox(height: 16),
                  ],
                  ...switch (_step) {
                    0 => _basic(),
                    1 => _location(),
                    2 => _photos(),
                    3 => _rooms(),
                    4 => _rules(),
                    _ => _reviewPage(),
                  },
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    UdBanner(tone: UdTone.err, icon: Icons.error_outline_rounded, text: _error),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _next(VoidCallback onPressed, {String? label}) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: UdButton.primary(
          label: label ?? (_fromReview ? 'Save' : 'Aage'),
          trailingIcon: _fromReview ? null : Icons.arrow_forward_rounded,
          busy: _busy,
          onPressed: _busy || _uploading != null ? null : onPressed,
        ),
      );

  List<Widget> _basic() => [
        UdTextField(
          controller: _name,
          label: 'Hotel ka naam',
          hint: 'Pine View Guest House',
          icon: Icons.apartment_rounded,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        const UdLabel('Type'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _types)
              UdChip(label: t, selected: _type == t, onTap: () => setState(() => _type = t)),
          ],
        ),
        const SizedBox(height: 14),
        UdTextField(
          controller: _description,
          label: 'Description',
          hint: 'Darya ke kinare, pahari view, family ke liye saaf suthre kamre…',
          maxLines: 5,
          minLines: 3,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
        ),
        _next(_saveBasic),
      ];

  List<Widget> _location() {
    final draft = _draft!;
    final pin = _pin;
    return [
      UdCard(
        tone: UdCardTone.tint,
        onTap: _pickPin,
        child: Row(
          children: [
            UdIconTile(
              icon: pin == null ? Icons.add_location_alt_outlined : Icons.location_on_rounded,
              tone: pin == null ? UdIconTone.neutral : UdIconTone.lime,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pin == null ? 'Map par pin lagayein' : 'Pin laga hua ✓',
                      style: AppType.listTitle.copyWith(color: AppText.primary)),
                  const SizedBox(height: 2),
                  Text(
                    pin == null
                        ? 'Hotel ke gate par — UDrive pickup isi jagah aaye ga.'
                        : '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)} · badalne ke liye tap',
                    style: AppType.caption.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppText.caption),
          ],
        ),
      ),
      const SizedBox(height: 14),
      UdTextField(
        controller: _address,
        label: 'Address',
        hint: 'Chattar Klass Road, near Bridge',
        icon: Icons.location_on_outlined,
        maxLines: 2,
      ),
      const SizedBox(height: 14),
      if (draft.district.isNotEmpty && _area == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Abhi: ${draft.district} · ${draft.city}',
              style: AppType.small.copyWith(color: AppText.secondary)),
        ),
      AreaPicker(
        api: AppControllerScope.of(context).apiClient,
        title: 'HOTEL KIS ILAQE MEIN HAI?',
        hint: 'District aur tehsil — customers isi se dhoondte hain.',
        onChanged: (selection) => setState(() => _area = selection),
      ),
      _next(_saveLocation),
    ];
  }

  List<Widget> _photos() {
    final draft = _draft!;
    final photos = draft.photos;
    return [
      Text('Kam az kam 3 photos — bahar, kamra, washroom. Pehli photo "Main" banti hai.',
          style: AppType.small.copyWith(color: AppText.secondary, height: 1.4)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final photo in photos)
            GestureDetector(
              onTap: _uploading == null ? () => _photoActions(photo) : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: AppRadii.all(12),
                    child: Image.network(
                      ApiConfig.absoluteUrl(photo.url),
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceAlt),
                    ),
                  ),
                  if (photo.isMain)
                    const Positioned(left: 5, top: 5, child: UdBadge(label: 'MAIN', tone: UdTone.lime)),
                ],
              ),
            ),
          if (photos.length < 9)
            Material(
              color: AppColors.background,
              borderRadius: AppRadii.all(12),
              child: InkWell(
                borderRadius: AppRadii.all(12),
                onTap: _uploading == null ? _addPhoto : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.all(12),
                    border: Border.all(color: AppColors.border, width: 1.5),
                  ),
                  child: Center(
                    child: _uploading == 'photo'
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy))
                        : const Icon(Icons.add_rounded, size: 28, color: AppColors.navy),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('${photos.length} / 9 · photo par tap: Main banayein / hatayein',
          style: AppType.caption.copyWith(color: AppText.secondary)),
      _next(_photosNext),
    ];
  }

  List<Widget> _rooms() {
    final rooms = _draft!.rooms;
    return [
      for (final room in rooms)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: UdCard(
            onTap: _busy || _uploading != null ? null : () => _editRoom(room),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadii.all(10),
                  child: SizedBox(
                    width: 60,
                    height: 52,
                    child: _uploading == 'room-${room.id}'
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy))
                        : room.imageUrl.isEmpty
                            ? const ColoredBox(
                                color: AppColors.surfaceAlt,
                                child: Icon(Icons.bed_outlined, color: AppColors.navy),
                              )
                            : Image.network(ApiConfig.absoluteUrl(room.imageUrl),
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceAlt)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.roomType, style: AppType.listTitle.copyWith(color: AppText.primary)),
                      Text('${room.capacity} log · ${room.totalRooms} kamre · tap: badlein',
                          style: AppType.caption.copyWith(color: AppText.secondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Money.amount(room.baseRate),
                        style: AppType.listTitle.copyWith(fontWeight: FontWeight.w800, color: AppText.primary)),
                    Text('/ raat', style: AppType.caption.copyWith(color: AppText.secondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      UdCard(
        selected: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Naya room type', style: AppType.h3.copyWith(color: AppText.primary)),
            const SizedBox(height: 10),
            UdTextField(controller: _roomType, label: 'Type', hint: 'Double room'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: UdTextField(controller: _roomPeople, label: 'Log', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: UdTextField(controller: _roomCount, label: 'Kamre', keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            UdTextField(controller: _roomRate, label: 'Rs / raat', hint: '6500', keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            UdButton.outline(
              label: 'Room type add karein',
              icon: Icons.add_rounded,
              busy: _busy,
              onPressed: _busy ? null : _addRoom,
            ),
          ],
        ),
      ),
      _next(_roomsNext),
    ];
  }

  List<Widget> _rules() => [
        const UdLabel('Sahuliyat'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _amenityChoices)
              UdChip(
                label: a,
                selected: _amenities.contains(a),
                onTap: () => setState(() => _amenities.contains(a) ? _amenities.remove(a) : _amenities.add(a)),
              ),
            UdChip(
              label: 'Pickup (UDrive)',
              selected: _pickup,
              onTap: () => setState(() => _pickup = !_pickup),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _timeBox('Check-in', _checkIn, () => _pickTime(true))),
            const SizedBox(width: 10),
            Expanded(child: _timeBox('Check-out', _checkOut, () => _pickTime(false))),
          ],
        ),
        const SizedBox(height: 16),
        UdTextField(
          controller: _bookingPhone,
          label: 'Booking WhatsApp number',
          hint: '03001234567',
          icon: Icons.chat_outlined,
          keyboardType: TextInputType.phone,
          helper: 'Har nayi booking is number par WhatsApp hogi — hotel head ka number dein.',
        ),
        _next(_saveRules, label: _fromReview ? 'Save' : 'Review karein'),
      ];

  Widget _timeBox(String label, String? value, VoidCallback onTap) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UdLabel(label),
          const SizedBox(height: 6),
          UdCard(
            tone: UdCardTone.flat,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            onTap: onTap,
            child: Row(
              children: [
                Expanded(
                  child: Text(_pretty(value),
                      style: AppType.listTitle.copyWith(color: AppText.primary)),
                ),
                const Icon(Icons.schedule_rounded, size: 18, color: AppText.secondary),
              ],
            ),
          ),
        ],
      );

  List<Widget> _reviewPage() {
    final d = _draft;
    if (d == null) return const [];
    final main = d.photos.isEmpty ? '' : ApiConfig.absoluteUrl(d.photos.first.url);
    final cheapest = d.rooms.isEmpty
        ? null
        : d.rooms.map((r) => r.baseRate).reduce((a, b) => a < b ? a : b);

    final (String note, UdTone tone) = switch (d.status) {
      'Approved' => ('Hotel live hai — jo badlenge woh foran customers ko nazar aaye ga.', UdTone.ok),
      'Pending' => ('Admin review mein hai. Badal sakte hain — admin naya version dekhega.', UdTone.warn),
      'Rejected' => ('Wapis bheja: ${d.rejectionReason ?? '—'}', UdTone.err),
      _ => ('Sab theek ho to admin ko bhejein. Approve hote hi customers ko nazar aaye ga.', UdTone.info),
    };

    return [
      if (main.isNotEmpty)
        ClipRRect(
          borderRadius: AppRadii.all(16),
          child: SizedBox(
            height: 150,
            child: Image.network(main, fit: BoxFit.cover, cacheWidth: 800,
                errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceAlt)),
          ),
        ),
      const SizedBox(height: 12),
      Text(d.name, style: AppType.h2.copyWith(color: AppText.primary)),
      Text([d.propertyType, if (d.city.isNotEmpty) d.city, if (d.district.isNotEmpty) d.district].join(' · '),
          style: AppType.small.copyWith(color: AppText.secondary)),
      const SizedBox(height: 12),
      UdBanner(tone: tone, text: note),
      const SizedBox(height: 12),
      UdListGroup(
        children: [
          _reviewRow('Basic', d.description.isEmpty ? 'Description baqi' : d.propertyType, 0),
          _reviewRow('Location', d.latitude == null ? 'Pin baqi' : (d.address.isEmpty ? 'Address baqi' : d.address), 1),
          _reviewRow('Photos (${d.photos.length})', d.photos.length < 3 ? 'Kam az kam 3' : 'Theek', 2),
          _reviewRow(
              'Rooms (${d.rooms.length})', cheapest == null ? 'Ek room type baqi' : '${Money.amount(cheapest)} se', 3),
          _reviewRow('Sahuliyat & rules',
              d.contactPhone.isEmpty ? 'WhatsApp number baqi' : 'WhatsApp ${_local(d.contactPhone)}', 4),
        ],
      ),
      if (d.missing.isNotEmpty) ...[
        const SizedBox(height: 12),
        UdBanner(tone: UdTone.warn, icon: Icons.info_outline_rounded, text: 'Abhi baqi: ${d.missing.join(', ')}.'),
      ],
      const SizedBox(height: 18),
      if (d.canSubmit)
        UdButton.primary(
          label: d.status == 'Rejected' ? 'Dobara admin ko bhejein' : 'Admin ko bhejein',
          icon: Icons.send_rounded,
          busy: _busy,
          onPressed: _busy || d.missing.isNotEmpty ? null : _submit,
        )
      else
        UdButton.primary(label: 'Ho gaya', onPressed: () => Navigator.of(context).pop()),
    ];
  }

  Widget _reviewRow(String title, String subtitle, int step) => UdListRow(
        title: title,
        subtitle: subtitle,
        trailing: Text('✎ Badlein', style: AppType.small.copyWith(color: AppText.secondary)),
        onTap: _busy ? null : () => _goTo(step),
      );

  static String _pretty(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return '—';
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? parts[1] : '00';
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour:$m $suffix';
  }

  static String _local(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('92') && digits.length == 12) return '0${digits.substring(2)}';
    return phone;
  }
}
