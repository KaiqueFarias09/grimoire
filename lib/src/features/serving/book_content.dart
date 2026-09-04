/// Pure book-hosting helpers shared by the platform server variants.
///
/// The IO host serves book files over a loopback HTTP server; the web
/// host rewrites references to blob URLs. Both inject the same viewer
/// assets and both resolve quirky relative paths the same way, so the
/// logic lives here with no dart:io dependency.
library;

import 'package:mime/mime.dart' as mime;

/// Whether [content] is a MathML document (Calibre's sniff).
bool containsMath(final String content) => content.toLowerCase().contains('<math');

/// Content-Type for a book file name, with reader-specific fallbacks.
String mimeOf(final String name) {
  final resolved = mime.lookupMimeType(name);
  if (resolved != null) {
    return resolved;
  }
  final lower = name.toLowerCase();
  if (lower.endsWith('.js')) return 'text/javascript';
  if (lower.endsWith('.css')) return 'text/css';
  if (lower.endsWith('.xhtml')) return 'application/xhtml+xml';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  if (lower.endsWith('.ttf')) return 'font/ttf';
  if (lower.endsWith('.otf')) return 'font/otf';
  return 'application/octet-stream';
}

/// Whether a book file name should be served as a rewritten HTML
/// reader page (extension-less files count as HTML, mirroring the
/// IO server's historical behavior).
bool isHtmlName(final String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') ||
      lower.endsWith('.htm') ||
      lower.endsWith('.xhtml') ||
      !lower.contains('.');
}

/// Fuzzy lookup for a book file path: exact match first, then
/// case-insensitive, then a unique basename match for quirky relative
/// refs. Returns the canonical key with the file content.
MapEntry<String, Object>? lookupBookFile(final Map<String, Object> files, final String rawPath) {
  final exact = files[rawPath];
  if (exact != null) {
    return MapEntry<String, Object>(rawPath, exact);
  }
  final lower = rawPath.toLowerCase();
  for (final entry in files.entries) {
    if (entry.key.toLowerCase() == lower) {
      return entry;
    }
  }
  // Last resort: unique basename match for quirky relative refs.
  final base = rawPath.split('/').last.toLowerCase();
  final matches = files.entries
      .where((final entry) => entry.key.split('/').last.toLowerCase() == base)
      .toList(growable: false);
  return matches.length == 1 ? matches.first : null;
}

/// Resolves a relative book reference against the directory of
/// [fromPath], normalizing `.` and `..` segments. Leading `/` means
/// book-root relative (the EPUB spec forbids it but quirky books use
/// it anyway).
String resolveBookPath(final String ref, {required final String fromPath}) {
  final rootRelative = ref.startsWith('/');
  final dirEnd = fromPath.lastIndexOf('/');
  final baseDir = rootRelative ? '' : (dirEnd > 0 ? fromPath.substring(0, dirEnd) : '');
  final source = rootRelative ? ref.substring(1) : ref;
  final segments = <String>[if (baseDir.isNotEmpty) ...baseDir.split('/')];
  for (final part in source.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(part);
  }
  return segments.join('/');
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
      'if(window.__elivreMathJaxDone){window.__elivreMathJaxDone();}'
      'if(window.__elivre){window.__elivre({type:"mathjaxReady"});}'
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

/// Synthetic wrapper page for comic (image-only) reading-order items.
String syntheticComicPageHtml({
  required final String imageUrl,
  required final String cssUrl,
  required final String jsUrl,
}) {
  return injectViewerAssets(
    '<!DOCTYPE html><html><head><title></title></head>'
    '<body class="elv-comic"><img src="$imageUrl" alt=""/></body></html>',
    cssUrl: cssUrl,
    jsUrl: jsUrl,
  );
}
