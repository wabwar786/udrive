import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';

/// Where one document stands, from the driver's side.
enum DocStatus {
  /// Checked and accepted by UDrive.
  verified,

  /// Sent, and waiting for UDrive to look at it.
  waiting,

  /// UDrive asked for it again — the note says why.
  rejected,

  /// Never sent.
  missing,
}

/// One row's worth: which document, and where it stands.
class DocStatusLine {
  const DocStatusLine({
    required this.type,
    required this.label,
    required this.state,
    this.note,
  });

  final String type;
  final String label;
  final DocStatus state;
  final String? note;

  /// Missing and rejected documents get an Upload button.
  bool get needsUpload =>
      state == DocStatus.missing || state == DocStatus.rejected;

  /// Builds the lines for [required] from the documents the server returned.
  ///
  /// [uploaded] is the raw list from `/driver/documents` or a vehicle's
  /// `documents` — maps with `documentType`, `status` and `reviewNotes`.
  static List<DocStatusLine> fromServer(
    List<(String, String)> required,
    List<Map<String, dynamic>> uploaded,
  ) {
    final byType = <String, Map<String, dynamic>>{
      for (final item in uploaded)
        (item['documentType'] ?? '').toString().toUpperCase(): item,
    };
    return [
      for (final (type, label) in required)
        _line(type, label, byType[type]),
    ];
  }

  static DocStatusLine _line(
      String type, String label, Map<String, dynamic>? item) {
    if (item == null) {
      return DocStatusLine(
          type: type, label: label, state: DocStatus.missing);
    }
    final status = (item['status'] ?? '').toString();
    final note = item['reviewNotes']?.toString();
    final state = switch (status) {
      'Verified' || 'Approved' => DocStatus.verified,
      'Rejected' || 'ChangesRequired' => DocStatus.rejected,
      _ => DocStatus.waiting,
    };
    return DocStatusLine(type: type, label: label, state: state, note: note);
  }
}

/// A list of documents, each with its state and — where something is
/// needed — an Upload button.
///
/// Used on the Verification status screen for the driver's own papers and
/// for each vehicle. A driver who was asked to re-send one photograph sees
/// exactly which one, why, and the button to fix it, instead of a red status
/// with nowhere to go.
class DocumentChecklist extends StatelessWidget {
  const DocumentChecklist({
    required this.lines,
    required this.onUpload,
    this.canReplace = false,
    this.busy = false,
    super.key,
  });

  final List<DocStatusLine> lines;
  final ValueChanged<String> onUpload;

  /// Whether documents already sent may be replaced too (a draft that has
  /// not been approved yet). Once approved, only missing or rejected ones.
  final bool canReplace;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return UdListGroup(
      children: [
        for (final line in lines)
          UdListRow(
            title: line.label,
            subtitle: _subtitle(line),
            leading: UdIconTile(
              icon: _icon(line.state),
              tone: _tone(line.state),
            ),
            trailing: line.needsUpload
                ? UdButton.soft(
                    label: 'Upload',
                    icon: Icons.upload_rounded,
                    size: UdButtonSize.xs,
                    expand: false,
                    onPressed: busy ? null : () => onUpload(line.type),
                  )
                : UdBadge(
                    label: line.state == DocStatus.verified
                        ? 'Verified'
                        : 'Review mein',
                    tone: line.state == DocStatus.verified
                        ? UdTone.ok
                        : UdTone.warn,
                  ),
            onTap: !busy && (line.needsUpload || canReplace)
                ? () => onUpload(line.type)
                : null,
          ),
      ],
    );
  }

  static String _subtitle(DocStatusLine line) => switch (line.state) {
        DocStatus.verified => 'Manzoor ho chuka',
        DocStatus.waiting => 'Upload ho gaya — UDrive check kar raha hai',
        DocStatus.rejected => (line.note ?? '').trim().isEmpty
            ? 'Dobara bhejein'
            : 'Dobara bhejein: ${line.note!.trim()}',
        DocStatus.missing => 'Abhi nahi bheja',
      };

  static IconData _icon(DocStatus state) => switch (state) {
        DocStatus.verified => Icons.check_circle_rounded,
        DocStatus.waiting => Icons.hourglass_top_rounded,
        DocStatus.rejected => Icons.error_rounded,
        DocStatus.missing => Icons.add_circle_outline_rounded,
      };

  static UdIconTone _tone(DocStatus state) => switch (state) {
        DocStatus.verified => UdIconTone.soft,
        DocStatus.waiting => UdIconTone.warn,
        DocStatus.rejected => UdIconTone.red,
        DocStatus.missing => UdIconTone.neutral,
      };
}

/// "2 documents need you" — the line above a checklist, or null when none do.
String? documentsNeedingYou(List<DocStatusLine> lines) {
  final count = lines.where((line) => line.needsUpload).length;
  if (count == 0) return null;
  return count == 1 ? '1 document chahiye' : '$count documents chahiye';
}

/// Kept here so the text colour of a caption matches the badge tone.
Color documentsCaptionColour(List<DocStatusLine> lines) =>
    lines.any((line) => line.needsUpload)
        ? AppTint.dangerText
        : AppText.secondary;
