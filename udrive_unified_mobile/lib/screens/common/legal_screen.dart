import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

/// The privacy policy, terms and account-deletion page, read inside the app.
///
/// These used to open in an external browser, which meant that in Neelum or
/// Leepa — where a customer is most likely to be standing at the roadside with
/// one bar of signal — the privacy policy simply did not open. The text is now
/// bundled with the app and needs no connection at all.
///
/// The same Markdown files are embedded in the API and served at /privacy and
/// /terms, so the copy Google Play points at and the copy in somebody's pocket
/// are the same document. `tool/check_legal_sync.py` fails a release if they
/// have drifted apart.
class LegalScreen extends StatefulWidget {
  const LegalScreen({required this.document, super.key});

  /// One of `privacy-policy`, `terms`, `account-deletion`.
  final String document;

  static Future<void> open(BuildContext context, String document) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LegalScreen(document: document),
      ));

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  String? _language;
  _LegalDocument? _parsed;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opens in whatever language the app is already in, and stays there until
    // the reader switches. Nobody should have to change the whole app's
    // language to read a policy.
    _language ??= AppControllerScope.of(context).locale.languageCode == 'ur' ? 'ur' : 'en';
    if (_parsed == null && _error == null) _load();
  }

  Future<void> _load() async {
    final language = _language ?? 'en';
    try {
      final raw = await rootBundle.loadString('assets/legal/${widget.document}.$language.md');
      if (!mounted) return;
      setState(() {
        _parsed = _LegalDocument.parse(raw);
        _error = null;
      });
    } catch (_) {
      // A missing translation falls back to English rather than showing an
      // error: a policy that will not open is worse than one in the other
      // language, and the English text is the one that governs anyway.
      if (language != 'en') {
        _language = 'en';
        await _load();
        return;
      }
      if (!mounted) return;
      setState(() => _error = 'This document could not be opened.');
    }
  }

  void _switchTo(String language) {
    if (_language == language) return;
    setState(() {
      _language = language;
      _parsed = null;
    });
    _load();
  }

  Future<void> _openOnline() async {
    final path = widget.document == 'privacy-policy'
        ? '/privacy'
        : widget.document == 'terms'
            ? '/terms'
            : '/account-deletion';
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      ApiConfig.uri('$path?lang=${_language ?? 'en'}'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the page. Check your internet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _parsed;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(document?.title ?? 'UDrive'),
        actions: [
          IconButton(
            tooltip: 'Open online',
            onPressed: _openOnline,
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : document == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
                  children: [
                    _LanguageToggle(language: _language ?? 'en', onChanged: _switchTo),
                    const SizedBox(height: 14),
                    Text(
                      document.title,
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, height: 1.2),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      document.effective.isEmpty
                          ? 'Version ${document.version}'
                          : 'Version ${document.version} · ${document.effective}',
                      style: const TextStyle(color: AppText.secondary, fontSize: 12.5),
                    ),
                    if (!document.governing) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadii.all(AppRadii.card),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'This translation is for convenience. The English version governs.',
                          style: TextStyle(color: AppText.secondary, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ...document.blocks.map((block) => block.build()),
                  ],
                ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.language, required this.onChanged});
  final String language;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String value, String label) {
      final selected = language == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              // Brand lime with navy on top. AppColors.primary is navy, and
              // navy-on-navy is the invisible-label mistake this palette
              // documents at the top of AppColors.
              color: selected ? AppColors.brand : Colors.transparent,
              borderRadius: AppRadii.all(AppRadii.cta),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: selected ? AppText.onBrand : AppText.secondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [option('ur', 'Roman Urdu'), option('en', 'English')]),
    );
  }
}

// ---------------------------------------------------------------- parsing
//
// The same Markdown subset the API renders: ## headings, paragraphs, bullet
// and numbered lists, pipe tables, **bold** and `code`. Deliberately small —
// these are documents we write ourselves, and a Markdown package would be a
// dependency carried into the app for six files.

class _LegalDocument {
  _LegalDocument({
    required this.title,
    required this.version,
    required this.effective,
    required this.governing,
    required this.blocks,
  });

  final String title;
  final String version;
  final String effective;
  final bool governing;
  final List<_Block> blocks;

  static _LegalDocument parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n');
    final meta = <String, String>{};
    var body = text;

    if (text.startsWith('---\n')) {
      // From 4, not 3: index 3 is the newline closing the opening delimiter,
      // so an empty front-matter block matched there and made substring(4, 3)
      // throw. Mirrors the same guard in LegalDocumentService.
      final end = text.indexOf('\n---', 4);
      if (end >= 4) {
        for (final line in text.substring(4, end).split('\n')) {
          final colon = line.indexOf(':');
          if (colon <= 0) continue;
          meta[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
        }
        body = text.substring(end + 4).replaceFirst(RegExp(r'^\n+'), '');
      }
    }

    return _LegalDocument(
      title: meta['title'] ?? 'UDrive',
      version: meta['version'] ?? '1.0',
      effective: meta['effective'] ?? '',
      governing: meta['governing'] == 'true',
      blocks: _parseBlocks(body),
    );
  }

  static List<_Block> _parseBlocks(String body) {
    final blocks = <_Block>[];
    final lines = body.split('\n');
    final paragraph = <String>[];
    final item = <String>[];
    final items = <String>[];
    var ordered = false;
    var index = 0;

    void closeParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_Paragraph(paragraph.join(' ')));
      paragraph.clear();
    }

    void closeItem() {
      if (item.isEmpty) return;
      items.add(item.join(' '));
      item.clear();
    }

    void closeList() {
      closeItem();
      if (items.isEmpty) return;
      blocks.add(_BulletList(List<String>.from(items), ordered: ordered));
      items.clear();
    }

    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        closeParagraph();
        closeList();
        index++;
        continue;
      }

      if (trimmed.startsWith('|') &&
          index + 1 < lines.length &&
          _isTableSeparator(lines[index + 1])) {
        closeParagraph();
        closeList();
        final header = _splitRow(lines[index]);
        final rows = <List<String>>[];
        index += 2;
        while (index < lines.length && lines[index].trim().startsWith('|')) {
          rows.add(_splitRow(lines[index]));
          index++;
        }
        blocks.add(_Table(header, rows));
        continue;
      }

      if (trimmed.startsWith('## ') || trimmed.startsWith('# ')) {
        closeParagraph();
        closeList();
        blocks.add(_Heading(trimmed.startsWith('## ') ? trimmed.substring(3) : trimmed.substring(2)));
        index++;
        continue;
      }

      if (trimmed.startsWith('- ')) {
        closeParagraph();
        closeItem();
        // A bullet directly after a numbered item, with no blank line between,
        // starts a new list rather than joining the old one with the wrong
        // markers in front of it.
        if (items.isNotEmpty && ordered) closeList();
        ordered = false;
        item.add(trimmed.substring(2));
        index++;
        continue;
      }

      final numbered = _numberedItem(trimmed);
      if (numbered != null) {
        closeParagraph();
        closeItem();
        if (items.isNotEmpty && !ordered) closeList();
        ordered = true;
        item.add(numbered);
        index++;
        continue;
      }

      if (item.isNotEmpty && line.startsWith('  ')) {
        item.add(trimmed);
        index++;
        continue;
      }

      closeList();
      paragraph.add(trimmed);
      index++;
    }

    closeParagraph();
    closeList();
    return blocks;
  }

  static bool _isTableSeparator(String line) {
    final t = line.trim();
    return t.startsWith('|') &&
        t.contains('---') &&
        t.split('').every((c) => c == '|' || c == '-' || c == ':' || c == ' ');
  }

  static String? _numberedItem(String trimmed) {
    final dot = trimmed.indexOf('.');
    if (dot <= 0 || dot + 1 >= trimmed.length || trimmed[dot + 1] != ' ') return null;
    final digits = trimmed.substring(0, dot);
    return int.tryParse(digits) == null ? null : trimmed.substring(dot + 2);
  }

  static List<String> _splitRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }
}

// ---------------------------------------------------------------- blocks

abstract class _Block {
  Widget build();
}

class _Heading implements _Block {
  _Heading(this.text);
  final String text;
  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, height: 1.3),
        ),
      );
}

class _Paragraph implements _Block {
  _Paragraph(this.text);
  final String text;
  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text.rich(
          _inline(text),
          style: const TextStyle(fontSize: 14, height: 1.62, color: AppText.primary),
        ),
      );
}

class _BulletList implements _Block {
  _BulletList(this.items, {required this.ordered});
  final List<String> items;
  final bool ordered;

  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: ordered ? 24 : 18,
                      child: Text(
                        ordered ? '${i + 1}.' : '•',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.62,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        _inline(items[i]),
                        style: const TextStyle(fontSize: 14, height: 1.62, color: AppText.primary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _Table implements _Block {
  _Table(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;

  @override
  Widget build() {
    // Laid out as stacked cards rather than a real table. A two-column table of
    // retention periods is unreadable at 360 dp wide, and this is a document
    // people read on a phone.
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.all(AppRadii.card),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < row.length; c++)
                    Padding(
                      padding: EdgeInsets.only(bottom: c == row.length - 1 ? 0 : 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c < header.length && header[c].isNotEmpty)
                            Text(
                              header[c],
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .07,
                                color: AppText.secondary,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text.rich(
                            _inline(row[c]),
                            style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppText.primary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Turns `**bold**` and `` `code` `` into spans. Unpaired markers are shown as
/// the author typed them rather than swallowing the rest of the sentence.
InlineSpan _inline(String text) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var bold = false;
  var code = false;
  var index = 0;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(
      text: buffer.toString(),
      style: TextStyle(
        fontWeight: bold ? FontWeight.w900 : null,
        fontFamily: code ? 'monospace' : null,
        backgroundColor: code ? AppColors.surface : null,
      ),
    ));
    buffer.clear();
  }

  while (index < text.length) {
    if (text.startsWith('**', index) &&
        (bold || text.indexOf('**', index + 2) >= 0)) {
      flush();
      bold = !bold;
      index += 2;
      continue;
    }
    if (text[index] == '`' && (code || text.indexOf('`', index + 1) >= 0)) {
      flush();
      code = !code;
      index += 1;
      continue;
    }
    buffer.write(text[index]);
    index++;
  }

  flush();
  return TextSpan(children: spans);
}
