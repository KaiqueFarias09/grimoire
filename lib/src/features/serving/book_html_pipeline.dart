import 'package:unseal/unseal.dart' show Book;

import 'book_javascript_policy.dart';
import 'book_resource_resolution.dart';

/// Whether [content] is a MathML document (Calibre's sniff).
bool containsMath(final String content) => content.toLowerCase().contains('<math');

/// Sanitizes book-authored executable HTML while preserving document
/// markup, styles, images and ordinary links.
///
/// The sanitizer is intentionally applied only to the HTML copy sent
/// to a viewer. It does not mutate the parsed [Book], so document text
/// and source content remain available to the host unchanged.
String sanitizeBookHtml(
  final String html, {
  final BookJavaScriptPolicy policy = BookJavaScriptPolicy.disabled,
}) {
  if (policy == BookJavaScriptPolicy.allowBookScripts) {
    return html;
  }

  final output = StringBuffer();
  var cursor = 0;
  while (cursor < html.length) {
    final tagStart = html.indexOf('<', cursor);
    if (tagStart < 0) {
      output.write(html.substring(cursor));
      break;
    }
    output.write(html.substring(cursor, tagStart));

    if (html.startsWith('<!--', tagStart)) {
      final commentEnd = html.indexOf('-->', tagStart + 4);
      if (commentEnd < 0) {
        output.write(html.substring(tagStart));
        break;
      }
      output.write(html.substring(tagStart, commentEnd + 3));
      cursor = commentEnd + 3;
      continue;
    }

    final tagEnd = _findHtmlTagEnd(html, tagStart);
    if (tagEnd < 0) {
      final tail = html.substring(tagStart);
      if (_htmlTagName(tail) == 'script') {
        // An unclosed script element consumes the rest of the HTML in
        // a browser, so dropping the tail is the safe interpretation.
        break;
      }
      output.write(_sanitizeHtmlTag(tail));
      break;
    }

    final tag = html.substring(tagStart, tagEnd + 1);
    final tagName = _htmlTagName(tag);
    if (tagName == 'script') {
      // Drop unmatched closing tags as well as complete script
      // elements. An opening tag without a closing tag consumes the
      // remaining source, just like the HTML parser does.
      cursor = tagEnd + 1;
      if (_isClosingHtmlTag(tag)) {
        continue;
      }
      final closing = RegExp(
        r'</\s*script\b[^>]*>',
        caseSensitive: false,
      ).firstMatch(html.substring(cursor));
      if (closing == null) {
        break;
      }
      cursor += closing.end;
      continue;
    }

    output.write(_isClosingHtmlTag(tag) ? tag : _sanitizeHtmlTag(tag));
    cursor = tagEnd + 1;
  }
  return output.toString();
}

int _findHtmlTagEnd(final String html, final int tagStart) {
  String? quote;
  for (var index = tagStart + 1; index < html.length; index++) {
    final character = html[index];
    if (quote != null) {
      if (character == quote) {
        quote = null;
      }
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
    } else if (character == '>') {
      return index;
    }
  }
  return -1;
}

String? _htmlTagName(final String tag) {
  final match = RegExp(r'^<\s*/?\s*([A-Za-z][A-Za-z0-9:-]*)').firstMatch(tag);
  return match?.group(1)?.toLowerCase();
}

bool _isClosingHtmlTag(final String tag) => RegExp(r'^<\s*/').hasMatch(tag);

String _sanitizeHtmlTag(final String tag) {
  final nameMatch = RegExp(r'^<\s*/?\s*([A-Za-z][A-Za-z0-9:-]*)').firstMatch(tag);
  if (nameMatch == null || _isClosingHtmlTag(tag)) {
    return tag;
  }

  final output = StringBuffer(tag.substring(0, nameMatch.end));
  var cursor = nameMatch.end;
  while (cursor < tag.length) {
    final attributeStart = cursor;
    while (cursor < tag.length && _isHtmlWhitespace(tag.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= tag.length) {
      break;
    }
    if (tag[cursor] == '>' || tag[cursor] == '/') {
      output.write(tag.substring(attributeStart));
      break;
    }

    final nameStart = cursor;
    while (cursor < tag.length &&
        !_isHtmlWhitespace(tag.codeUnitAt(cursor)) &&
        tag[cursor] != '=' &&
        tag[cursor] != '>' &&
        tag[cursor] != '/') {
      cursor++;
    }
    if (cursor == nameStart) {
      output.write(tag[cursor]);
      cursor++;
      continue;
    }

    final attributeName = tag.substring(nameStart, cursor).toLowerCase();
    final afterName = _skipHtmlWhitespace(tag, cursor);
    var attributeEnd = afterName;
    String? value;
    if (afterName < tag.length && tag[afterName] == '=') {
      var valueStart = _skipHtmlWhitespace(tag, afterName + 1);
      if (valueStart < tag.length && (tag[valueStart] == '"' || tag[valueStart] == "'")) {
        final quote = tag[valueStart];
        valueStart++;
        var valueEnd = valueStart;
        while (valueEnd < tag.length && tag[valueEnd] != quote) {
          valueEnd++;
        }
        value = tag.substring(valueStart, valueEnd);
        attributeEnd = valueEnd < tag.length ? valueEnd + 1 : valueEnd;
      } else {
        var valueEnd = valueStart;
        while (valueEnd < tag.length &&
            !_isHtmlWhitespace(tag.codeUnitAt(valueEnd)) &&
            tag[valueEnd] != '>') {
          valueEnd++;
        }
        value = tag.substring(valueStart, valueEnd);
        attributeEnd = valueEnd;
      }
    }

    final attribute = tag.substring(attributeStart, attributeEnd);
    if (!_isUnsafeBookAttribute(attributeName, value)) {
      output.write(attribute);
    }
    cursor = attributeEnd;
  }
  return output.toString();
}

int _skipHtmlWhitespace(final String value, int cursor) {
  while (cursor < value.length && _isHtmlWhitespace(value.codeUnitAt(cursor))) {
    cursor++;
  }
  return cursor;
}

bool _isHtmlWhitespace(final int codeUnit) => codeUnit <= 0x20;

const Set<String> _javascriptUrlAttributes = <String>{
  'action',
  'archive',
  'background',
  'cite',
  'classid',
  'codebase',
  'data',
  'formaction',
  'href',
  'longdesc',
  'manifest',
  'poster',
  'profile',
  'src',
  'srcset',
  'usemap',
  'xlink:href',
  'xml:base',
};

bool _isUnsafeBookAttribute(final String name, final String? value) {
  if (name.startsWith('on') || name == 'srcdoc') {
    return true;
  }
  if (value == null) {
    return false;
  }
  if (_javascriptUrlAttributes.contains(name)) {
    if (name == 'srcset') {
      return value.split(',').any(_isJavascriptUrl);
    }
    return _isJavascriptUrl(value);
  }
  if (name == 'style') {
    final normalized = _normalizePotentialUrl(value);
    return normalized.contains('javascript:') ||
        RegExp(r'expression\s*\(', caseSensitive: false).hasMatch(value);
  }
  return false;
}

bool _isJavascriptUrl(final String value) =>
    _normalizePotentialUrl(value).startsWith('javascript:');

String _normalizePotentialUrl(final String value) {
  final decoded = value.replaceAllMapped(
    RegExp(r'&(?:#x([0-9a-f]+)|#([0-9]+)|colon);?', caseSensitive: false),
    (final match) {
      final hex = match.group(1);
      final decimal = match.group(2);
      if (hex != null) {
        final codeUnit = int.tryParse(hex, radix: 16);
        if (codeUnit != null && codeUnit <= 0x10ffff) {
          return String.fromCharCode(codeUnit);
        }
      } else if (decimal != null) {
        final codeUnit = int.tryParse(decimal);
        if (codeUnit != null && codeUnit <= 0x10ffff) {
          return String.fromCharCode(codeUnit);
        }
      } else {
        return ':';
      }
      return match.group(0)!;
    },
  );
  final output = StringBuffer();
  for (final codeUnit in decoded.codeUnits) {
    if (codeUnit <= 0x20 || (codeUnit >= 0x7f && codeUnit <= 0x9f)) {
      continue;
    }
    output.writeCharCode(codeUnit);
  }
  return output.toString().toLowerCase();
}

/// Rewrites resource references inside [html] to absolute URLs.
///
/// [resolve] maps a normalized book path to its served URL, or null
/// when the file is missing. Only resource attributes are rewritten:
/// `src`, `poster`, `object data`, SVG `xlink:href`, `srcset`, and
/// `href` scoped to `<link>`/`<image>` tags. Anchor (`<a href>`) and
/// page links stay untouched because the viewer intercepts clicks and
/// routes them through the host. Returns [html] unchanged where
/// nothing matches so tests can pin exact output.
String rewriteHtmlResources(
  final String html, {
  required final String pagePath,
  required final String? Function(String bookPath) resolve,
}) {
  var result = html;
  // href only where it points at a resource: <link> and SVG <image>.
  result = _rewriteTagAttributes(
    result,
    tagPattern: RegExp(r'<(?:link|image)\b[^>]*>', caseSensitive: false),
    attributes: const ['href'],
    pagePath: pagePath,
    resolve: resolve,
  );
  result = _rewriteTagAttributes(
    result,
    tagPattern: null,
    attributes: const ['src', 'poster', 'data', 'xlink:href', 'srcset'],
    pagePath: pagePath,
    resolve: resolve,
  );
  result = result.replaceAllMapped(
    RegExp(r'(<style\b[^>]*>)([\s\S]*?)(</style\s*>)', caseSensitive: false),
    (final match) {
      final inner = rewriteCssResources(match.group(2)!, cssPath: pagePath, resolve: resolve);
      return '${match.group(1)}$inner${match.group(3)}';
    },
  );
  result = _rewriteStyleAttributes(result, pagePath: pagePath, resolve: resolve);
  return result;
}

/// Rewrites `url(...)` references inside inline `style="..."`
/// attributes, preserving the original quote character.
String _rewriteStyleAttributes(
  final String html, {
  required final String pagePath,
  required final String? Function(String bookPath) resolve,
}) {
  const single = "\u0027";
  return html.replaceAllMapped(
    RegExp('\\bstyle\\s*=\\s*("([^"]*)"|[$single]([^$single]*)[$single])', caseSensitive: false),
    (final match) {
      final doubleQuoted = match.group(2) != null;
      final value = match.group(2) ?? match.group(3)!;
      final rewritten = rewriteCssResources(value, cssPath: pagePath, resolve: resolve);
      if (rewritten == value) {
        return match.group(0)!;
      }
      final q = doubleQuoted ? '"' : single;
      return 'style=$q${_escapeAttr(rewritten)}$q';
    },
  );
}

/// Rewrites `url(...)` and `@import` references inside a stylesheet.
String rewriteCssResources(
  final String css, {
  required final String cssPath,
  required final String? Function(String bookPath) resolve,
}) {
  var result = css.replaceAllMapped(RegExp(r'url\(\s*([^)]*?)\s*\)'), (final match) {
    var ref = match.group(1)!;
    String? quote;
    if (ref.length >= 2 &&
        ((ref.startsWith('"') && ref.endsWith('"')) ||
            (ref.startsWith("'") && ref.endsWith("'")))) {
      quote = ref.substring(0, 1);
      ref = ref.substring(1, ref.length - 1);
    }
    final rewritten = _rewriteRef(ref, fromPath: cssPath, resolve: resolve);
    if (rewritten == null) {
      return match.group(0)!;
    }
    // Bare form is only valid CSS without spaces or parens; a
    // rewritten URL always goes out quoted to be safe.
    final q = quote ?? '"';
    return 'url($q$rewritten$q)';
  });
  // Quote characters built without escapes so the pattern stays
  // readable.
  const quoteChars = "\u0027\u0022";
  result = result.replaceAllMapped(RegExp('@import\\s+([$quoteChars])([^$quoteChars]+?)\\1'), (
    final match,
  ) {
    final quote = match.group(1)!;
    final rewritten = _rewriteRef(match.group(2)!, fromPath: cssPath, resolve: resolve);
    return rewritten == null ? match.group(0)! : '@import $quote$rewritten$quote';
  });
  return result;
}

String _rewriteTagAttributes(
  final String html, {
  final RegExp? tagPattern,
  required final List<String> attributes,
  required final String pagePath,
  required final String? Function(String bookPath) resolve,
}) {
  final attrPattern = RegExp(
    '\\b(${attributes.join('|')})\\s*=\\s*("([^"]*)"|\'([^\']*)\')',
    caseSensitive: false,
  );
  String rewriteAttrs(final String input) => input.replaceAllMapped(attrPattern, (final match) {
    final attr = match.group(1)!.toLowerCase();
    final ref = match.group(3) ?? match.group(4)!;
    if (attr == 'srcset') {
      final rewritten = _rewriteSrcset(ref, fromPath: pagePath, resolve: resolve);
      if (rewritten == null) {
        return match.group(0)!;
      }
      return '${match.group(1)}="${_escapeAttr(rewritten)}"';
    }
    final rewritten = _rewriteRef(ref, fromPath: pagePath, resolve: resolve);
    if (rewritten == null || rewritten == ref) {
      return match.group(0)!;
    }
    return '${match.group(1)}="${_escapeAttr(rewritten)}"';
  });
  if (tagPattern == null) {
    return rewriteAttrs(html);
  }
  return html.replaceAllMapped(tagPattern, (final match) => rewriteAttrs(match.group(0)!));
}

/// Resolves one reference, or null to keep it as-is (absolute URLs,
/// data URIs, pure anchors, missing files).
String? _rewriteRef(
  final String rawRef, {
  required final String fromPath,
  required final String? Function(String bookPath) resolve,
}) {
  final ref = rawRef.trim();
  if (ref.isEmpty || ref.startsWith('#')) {
    return null;
  }
  final lower = ref.toLowerCase();
  for (final prefix in const ['http://', 'https://', 'data:', 'blob:', 'mailto:', 'javascript:']) {
    if (lower.startsWith(prefix)) {
      return null;
    }
  }
  var path = ref;
  final hash = path.indexOf('#');
  if (hash >= 0) {
    path = path.substring(0, hash);
  }
  if (path.isEmpty) {
    return null;
  }
  return resolve(resolveBookPath(path, fromPath: fromPath));
}

/// Resolves every candidate of a `srcset` value (`url 1x, url 2x`),
/// or null when nothing changed.
String? _rewriteSrcset(
  final String value, {
  required final String fromPath,
  required final String? Function(String bookPath) resolve,
}) {
  var changed = false;
  final out = value
      .split(',')
      .map((final candidate) {
        final trimmed = candidate.trim();
        if (trimmed.isEmpty) {
          return candidate;
        }
        final parts = trimmed.split(RegExp(r'\s+'));
        final rewritten = _rewriteRef(parts.first, fromPath: fromPath, resolve: resolve);
        if (rewritten == null) {
          return candidate;
        }
        changed = true;
        parts[0] = rewritten;
        return parts.join(' ');
      })
      .join(', ');
  return changed ? out : null;
}

String _escapeAttr(final String value) => value.replaceAll('"', '&quot;');

/// Injects the viewport meta, viewer stylesheet and script into [html]
/// at the given absolute URLs.
String injectViewerAssets(
  final String html, {
  required final String cssUrl,
  required final String jsUrl,
}) {
  final injection =
      '<meta name="viewport" content="width=device-width, '
      'initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>'
      '<link rel="stylesheet" href="$cssUrl"/>'
      '<script defer src="$jsUrl"></script>';
  return injectIntoHead(html, injection);
}

/// Calibre-parity MathJax boot: SVG output, mhchem for chemistry,
/// menus off, and a `mathjaxReady` bridge message once typesetting
/// settles so the reader can re-flow pagination. [scriptBase] points
/// at the directory serving `tex-mml-svg.js` (a loopback path on IO,
/// a CDN URL on the web). A single retry re-adds the script in case
/// the cache finished downloading after the page had already loaded.
String injectMathJax(final String html, {required final String scriptBase}) {
  final component = '$scriptBase/tex-mml-svg.js';
  final injection =
      '<script>'
      'window.MathJax={'
      'loader:{load:["[tex]/mhchem"]},'
      'tex:{packages:{"[+]":["mhchem"]}},'
      'svg:{fontCache:"global"},'
      'options:{enableMenu:false},'
      'startup:{pageReady:function(){'
      'return MathJax.startup.promise.then(function(){'
      'if(window.__grimoireMathJaxDone){window.__grimoireMathJaxDone();}'
      'if(window.__grimoire){window.__grimoire({type:"mathjaxReady"});}'
      '});}}};'
      '</script>'
      '<script defer src="$component"></script>'
      '<script>'
      'setTimeout(function(){'
      'if(!(window.MathJax&&window.MathJax.typeset)){'
      'var s=document.createElement("script");'
      's.defer=true;s.src="$component";'
      'document.head.appendChild(s);}'
      '},2500);'
      '</script>';
  return injectIntoHead(html, injection);
}

/// Inserts [injection] right after `<head>`, or synthesizes one.
String injectIntoHead(final String html, final String injection) {
  final headOpen = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (headOpen != null) {
    final at = headOpen.end;
    return html.substring(0, at) + injection + html.substring(at);
  }
  final htmlOpen = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(html);
  if (htmlOpen != null) {
    final at = htmlOpen.end;
    return '${html.substring(0, at)}<head>$injection</head>'
        '${html.substring(at)}';
  }
  return '<!DOCTYPE html><html><head>$injection</head>'
      '<body>$html</body></html>';
}
