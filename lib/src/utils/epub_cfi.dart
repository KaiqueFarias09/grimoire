import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'document_text.dart';

/// EPUB CFI (Canonical Fragment Identifier) for a single XHTML file.
///
/// Parity: calibre src/pyj/read_book/cfi.pyj — the single-file subset
/// the viewer needs (element steps with id assertions, text character
/// offsets, escaping, sorting). Cross-iframe indirection (`!`),
/// temporal (`~`) and spatial (`@`) offsets are out of scope for this
/// model. Text offsets share the character space of [documentText]
/// (body-only, whitespace kept as-is), so a CFI and an `eLv1` offset
/// address the same characters.
final RegExp _escapable = RegExp(r'[\^\[\]\(\);~@!]');

/// Parity: cfi.pyj:12-17 (escape_for_cfi).
String escapeForCfi(final String text) =>
    text.replaceAllMapped(_escapable, (final m) => '^${m[0]}');

/// Parity: cfi.pyj:12-17 (unescape_from_cfi).
String unescapeFromCfi(final String text) =>
    text.replaceAllMapped(RegExp(r'\^([\^\[\]\(\);~@!])'), (final m) => m[1]!);

/// Parity: cfi.pyj:21 (fstr) — not needed for integer-only steps, kept
/// for completeness of the escaping surface.

/// A parsed CFI: element/text path steps from the file root plus an
/// optional character offset within the final text node.
class EpubCfi {
  const EpubCfi({required this.steps, this.charOffset = 0, this.idAssertion});

  /// EPUB path steps: even numbers address elements (2-based counting),
  /// odd numbers address text nodes.
  final List<int> steps;

  /// Character offset inside the final text node (0 when the step
  /// addresses an element).
  final int charOffset;

  /// Id assertion of the final element (`/6[chapter-one]`).
  final String? idAssertion;

  /// `epubcfi(/4/6:12[id])` style serialization.
  String serialize() {
    final path = steps.map((final s) => '/$s').join();
    final offset = charOffset > 0 ? ':$charOffset' : '';
    final id = idAssertion != null ? '[${escapeForCfi(idAssertion!)}]' : '';
    return 'epubcfi($path$offset$id)';
  }

  /// Parity: cfi.pyj:321+ (decode) — accepts the serialization above.
  static EpubCfi? parse(final String input) {
    final match = RegExp(
      r'^epubcfi\((.*)\)$',
    ).firstMatch(input.trim());
    if (match == null) {
      return null;
    }
    var body = match.group(1)!;
    final idAssertion = RegExp(
      r'\[((?:\^.|[^\]])*)\]$',
    ).firstMatch(body);
    var id;
    if (idAssertion != null) {
      id = unescapeFromCfi(idAssertion.group(1)!);
      body = body.substring(0, idAssertion.start);
    }
    final offsetMatch = RegExp(r':(\d+)$').firstMatch(body);
    var charOffset = 0;
    if (offsetMatch != null) {
      charOffset = int.parse(offsetMatch.group(1)!);
      body = body.substring(0, offsetMatch.start);
    }
    final steps = <int>[];
    for (final step in RegExp(r'/(\d+)').allMatches(body)) {
      steps.add(int.parse(step.group(1)!));
    }
    if (steps.isEmpty) {
      return null;
    }
    return EpubCfi(
      steps: steps,
      charOffset: charOffset,
      idAssertion: id is String ? id : null,
    );
  }

  /// Parity: cfi.pyj:421-497 (cfi_sort_key/create_cfi_cmp) — lexical
  /// comparison of steps, then the character offset.
  static int compare(final EpubCfi a, final EpubCfi b) {
    final max = math.max(a.steps.length, b.steps.length);
    for (var i = 0; i < max; i++) {
      final sa = i < a.steps.length ? a.steps[i] : 0;
      final sb = i < b.steps.length ? b.steps[i] : 0;
      if (sa != sb) {
        return sa.compareTo(sb);
      }
    }
    return a.charOffset.compareTo(b.charOffset);
  }
}

/// Position/lookup over the parsed tree of one XHTML file. Text
/// offsets are the concatenation of text nodes inside `<body>`
/// (skipping `script`/`style`), i.e. the same space as
/// [documentText] and the viewer's JS TreeWalker.
class EpubCfiDocument {
  EpubCfiDocument._(this._body, this._textNodes);

  final XmlElement _body;
  final List<XmlNode> _textNodes;

  /// Parses [xhtml] and indexes its text nodes. Named HTML entities
  /// that XML cannot resolve are decoded first (same entity table as
  /// [documentText]).
  factory EpubCfiDocument.parse(final String xhtml) {
    var source = xhtml;
    // Named entities beyond the XML five would fail the XML parser.
    source = source.replaceAllMapped(
      RegExp(r'&([a-zA-Z][a-zA-Z0-9]{1,31});'),
      (final m) => decodeEntity(m.group(1)!) ?? m.group(0)!,
    );
    final doc = XmlDocument.parse(source);
    final body = doc.findAllElements('body').first;
    final textNodes = <XmlNode>[];
    void walk(final XmlNode node) {
      for (final child in node.children) {
        if (child is XmlText) {
          if (child.value.isNotEmpty) {
            textNodes.add(child);
          }
        } else if (child is XmlElement) {
          final name = child.name.local.toLowerCase();
          if (name == 'script' || name == 'style') {
            continue;
          }
          walk(child);
        }
      }
    }

    walk(body);
    return EpubCfiDocument._(body, textNodes);
  }

  /// The concatenated document text (the offset space).
  String get text {
    final buffer = StringBuffer();
    for (final t in _textNodes) {
      buffer.write((t as XmlText).value);
    }
    return buffer.toString();
  }

  /// Offset of the first occurrence of [needle] in the text space.
  int? indexOfText(final String needle) {
    final at = text.indexOf(needle);
    return at < 0 ? null : at;
  }

  /// Character offset of [node] in the document text space.
  int offsetOf(final XmlNode node) {
    var consumed = 0;
    for (final text in _textNodes) {
      if (identical(text, node)) {
        return consumed;
      }
      consumed += (text as XmlText).value.length;
    }
    return consumed;
  }

  XmlNode? _textNodeAt(final int offset) {
    var consumed = 0;
    for (final text in _textNodes) {
      final len = (text as XmlText).value.length;
      if (consumed + len > offset) {
        return text;
      }
      consumed += len;
    }
    return _textNodes.isEmpty ? null : _textNodes.last;
  }

  /// Parity: cfi.pyj:194+ (encode) — walk up from [node] to the body
  /// collecting EPUB steps (element child i -> 2i, text child i ->
  /// 2i-1), skipping highlight wrapper spans just like Calibre skips
  /// `calibreRangeWrapper` spans. [idAssertion] is taken from the
  /// final element when it carries an `id` attribute.
  List<int> _stepsFor(final XmlNode node) {
    final steps = <int>[];
    XmlNode current = node;
    while (true) {
      final parent = current.parent;
      if (parent == null || parent is XmlDocument) {
        break;
      }
      var index = 0;
      var seen = 0;
      XmlNode? previous;
      for (final child in parent.children) {
        if (_skips(child)) {
          continue;
        }
        seen += 1;
        if (identical(child, current)) {
          index = seen;
          break;
        }
        previous = child;
      }
      if (index == 0) {
        break;
      }
      final isText = current is XmlText;
      steps.insert(0, isText ? index * 2 - 1 : index * 2);
      // The body itself contributes no step; its children do.
      if (_isBody(parent)) {
        break;
      }
      current = parent;
    }
    return steps;
  }

  bool _isBody(final XmlNode node) =>
      node is XmlElement && node.name.local.toLowerCase() == 'body';

  bool _skips(final XmlNode node) =>
      node is XmlText && node.value.isEmpty;

  /// CFI of the character at [offset] (like the JS encode from a text
  /// node plus offset). The id assertion comes from the nearest
  /// element ancestor carrying an `id`.
  EpubCfi cfiForOffset(final int offset) {
    final node = _textNodeAt(offset);
    if (node == null) {
      throw RangeError.range(offset, 0, 0, 'offset', 'empty document');
    }
    final steps = _stepsFor(node);
    String? id;
    XmlElement? element = node.parent is XmlElement
        ? node.parent as XmlElement
        : null;
    while (element != null && !_isBody(element)) {
      final idAttr = element.attributes.where(
        (final a) => a.name.local.toLowerCase() == 'id',
      );
      if (idAttr.isNotEmpty) {
        id = idAttr.first.value;
        break;
      }
      element = element.parent is XmlElement
          ? element.parent as XmlElement
          : null;
    }
    return EpubCfi(
      steps: steps,
      charOffset: offset - offsetOf(node),
      idAssertion: id,
    );
  }

  /// Character offset of a parsed [cfi] (the decode path): resolves
  /// the path against the tree; a final element step addresses the
  /// start of its first text node.
  int? offsetForCfi(final EpubCfi cfi) {
    if (cfi.steps.isEmpty) {
      return null;
    }
    // Text step: odd numbers map to text children, index = (step+1)/2.
    // The EPUB child index counts ALL nodes (whitespace text nodes
    // included), exactly like _stepsFor on the encode side.
    XmlNode current = _body;
    for (var i = 0; i < cfi.steps.length; i++) {
      final step = cfi.steps[i];
      final isText = step.isOdd;
      final childIndex = isText ? (step + 1) ~/ 2 : step ~/ 2;
      final children =
          current.children.where((final c) => !_skips(c)).toList();
      if (childIndex < 1 || childIndex > children.length) {
        return null;
      }
      final child = children[childIndex - 1];
      if (isText && child is XmlText) {
        if (i == cfi.steps.length - 1) {
          final len = child.value.length;
          return offsetOf(child) + math.min(cfi.charOffset, len);
        }
        return null;
      }
      if (!isText && child is XmlElement) {
        current = child;
        continue;
      }
      return null;
    }
    return offsetOf(current);
  }
}
