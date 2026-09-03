import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

/// One document the platform needs from every Driver.
class _Required {
  const _Required({
    required this.type,
    required this.label,
    required this.why,
    this.expires = false,
  });

  /// The value the API stores in `document_type`.
  final String type;

  final String label;

  /// Why it is being asked for. A Driver handing over a CNIC deserves to know
  /// what it is for, and a list of bare labels reads like an interrogation.
  final String why;

  /// Whether an expiry date should be collected with it.
  final bool expires;
}

/// The Driver's document wallet: what is needed, what has been sent, what came
/// back.
///
/// The old flow was a form that uploaded files and then said nothing. A Driver
/// could photograph their licence, send it, and have no way to see what had
/// actually arrived — they found out it was blurred or upside down when it came
/// back rejected, days later. Every upload here can be opened and looked at.
class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  /// Deliberately short.
  ///
  /// Every extra document is a Driver who gives up halfway. These four are what
  /// actually establishes that a person may drive and that the vehicle is
  /// theirs; anything else can be asked for later, by an Admin who has a reason.
  static const _required = <_Required>[
    _Required(
      type: 'CnicFront',
      label: 'CNIC — front',
      why: 'Confirms who you are.',
    ),
    _Required(
      type: 'CnicBack',
      label: 'CNIC — back',
      why: 'The address side.',
    ),
    _Required(
      type: 'DrivingLicence',
      label: 'Driving licence',
      why: 'Confirms you may drive.',
      expires: true,
    ),
    _Required(
      type: 'ProfilePhoto',
      label: 'Your photograph',
      why: 'Customers see this before they get in.',
    ),
  ];

  List<Map<String, dynamic>> _documents = const [];
  bool _loading = true;
  String? _busyType;
  String? _error;
  String _profileStatus = 'Draft';
  String? _reviewNotes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  AuthRepository get _repository =>
      AuthRepository(AppControllerScope.of(context).apiClient);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await _repository.getDriverProfile();
      if (!mounted) return;
      setState(() {
        _documents = profile?.documents ?? const [];
        _profileStatus = profile?.verificationStatus ?? 'Draft';
        _reviewNotes = profile?.reviewNotes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _documentFor(String type) {
    for (final document in _documents) {
      if ('${document['documentType']}'.toLowerCase() == type.toLowerCase()) {
        return document;
      }
    }
    return null;
  }

  bool get _allUploaded =>
      _required.every((item) => _documentFor(item.type) != null);

  bool get _anyRejected => _documents.any(
      (document) => '${document['status']}'.toLowerCase() == 'rejected');

  Future<void> _upload(_Required item) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null || !mounted) return;

    setState(() => _busyType = item.type);
    try {
      await _repository.uploadDriverDocument(
        documentType: item.type,
        file: file,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.label} uploaded.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  /// Opens the uploaded file so the Driver can check it before it is judged.
  Future<void> _preview(_Required item, Map<String, dynamic> document) async {
    final id = '${document['id'] ?? ''}';
    if (id.isEmpty) return;

    // Read the token before navigating. The document routes are authenticated,
    // and an Image.network without the header shows a broken-image icon — from
    // which a Driver reasonably concludes their upload failed.
    final controller = AppControllerScope.of(context);
    final token = await controller.apiClient.sessionStore.readAccessToken();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DocumentPreview(
          title: item.label,
          url: '${ApiConfig.baseUrl}/api/v1/driver/documents/$id/file',
          token: token,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busyType = '__submit__');
    try {
      await _repository.submitDriverProfile();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sent for review. You will be told the result here.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My documents')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                children: [
                  _StatusBanner(
                    status: _profileStatus,
                    notes: _reviewNotes,
                    rejectedDocuments: _anyRejected,
                  ),
                  const SizedBox(height: 14),

                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                  ],

                  for (final item in _required) ...[
                    _DocumentRow(
                      item: item,
                      document: _documentFor(item.type),
                      busy: _busyType == item.type,
                      onUpload: () => _upload(item),
                      onPreview: () {
                        final document = _documentFor(item.type);
                        if (document != null) _preview(item, document);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // Submitting before everything is present wastes a review
                      // cycle and a day of the Driver's time, so the button
                      // stays off and the row above says what is missing.
                      onPressed: !_allUploaded ||
                              _busyType != null ||
                              _profileStatus == 'Approved'
                          ? null
                          : _submit,
                      child: Text(
                        _profileStatus == 'Approved'
                            ? 'Approved'
                            : _allUploaded
                                ? 'Send for approval'
                                : 'Upload all documents first',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Photographs are fine. Make sure all four corners are in '
                    'the frame and the text is readable — that is what most '
                    'rejections are about.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppText.disabled,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Where the Driver stands with the reviewers, in one block at the top.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.status,
    required this.notes,
    required this.rejectedDocuments,
  });

  final String status;
  final String? notes;
  final bool rejectedDocuments;

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'Rejected' || rejectedDocuments;
    final approved = status == 'Approved';
    final submitted = status == 'Submitted' || status == 'UnderReview';

    final (background, ink, icon, title, body) = approved
        ? (
            AppTint.success,
            AppTint.successText,
            Icons.verified_rounded,
            'Approved',
            'You can go online and take rides.',
          )
        : rejected
            ? (
                AppTint.danger,
                AppColors.danger,
                Icons.error_outline_rounded,
                'Something needs fixing',
                notes?.trim().isNotEmpty == true
                    ? notes!.trim()
                    : 'One or more documents were rejected. Replace the ones '
                        'marked below and send again.',
              )
            : submitted
                ? (
                    AppTint.warning,
                    AppTint.warningText,
                    Icons.hourglass_top_rounded,
                    'With the reviewers',
                    'Nothing to do. The result appears on this screen.',
                  )
                : (
                    AppColors.surfaceAlt,
                    AppText.secondary,
                    Icons.description_outlined,
                    'Not sent yet',
                    'Upload the four documents below, check each one, then send '
                        'for approval.',
                  );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(AppRadii.panel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One required document: what it is, what state it is in, and the two things
/// you can do with it.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.item,
    required this.document,
    required this.busy,
    required this.onUpload,
    required this.onPreview,
  });

  final _Required item;
  final Map<String, dynamic>? document;
  final bool busy;
  final VoidCallback onUpload;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final status = '${document?['status'] ?? ''}';
    final rejected = status.toLowerCase() == 'rejected';
    final approved = status.toLowerCase() == 'approved';
    final uploaded = document != null;
    final notes = '${document?['reviewNotes'] ?? ''}'.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.panel),
        border: Border.all(
          color: rejected ? AppColors.danger : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved
                    ? Icons.check_circle_rounded
                    : rejected
                        ? Icons.cancel_rounded
                        : uploaded
                            ? Icons.schedule_rounded
                            : Icons.add_photo_alternate_outlined,
                size: 20,
                color: approved
                    ? AppColors.success
                    : rejected
                        ? AppColors.danger
                        : uploaded
                            ? AppColors.warning
                            : AppText.disabled,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      approved
                          ? 'Approved'
                          : rejected
                              ? 'Rejected — replace this one'
                              : uploaded
                                  ? 'Uploaded, waiting for review'
                                  : item.why,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: uploaded ? FontWeight.w700 : FontWeight.w500,
                        color: rejected
                            ? AppColors.danger
                            : AppText.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (rejected && notes.isNotEmpty) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppTint.danger,
                borderRadius: AppRadii.all(AppRadii.row),
              ),
              // The reviewer's own words. A rejection with no reason is a wall,
              // and the Driver will simply upload the same photograph again.
              child: Text(
                notes,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          const SizedBox(height: 11),
          Row(
            children: [
              if (uploaded) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPreview,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || approved ? null : onUpload,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          uploaded
                              ? Icons.refresh_rounded
                              : Icons.upload_rounded,
                          size: 16,
                        ),
                  label: Text(
                    uploaded ? 'Replace' : 'Upload',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows an uploaded document full screen.
class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.title,
    required this.url,
    required this.token,
  });

  final String title;
  final String url;

  /// The document routes are authenticated, so the bearer token has to travel
  /// with the image request. Without it the preview is a broken-image icon and
  /// the Driver concludes their upload failed.
  final String? token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            headers: token == null ? null : {'Authorization': 'Bearer $token'},
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'This file cannot be shown here — PDFs open outside the app. '
                'If you expected a photograph, upload it again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}
