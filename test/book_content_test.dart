import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/serving/book_content.dart';

void main() {
  group('sanitizeBookHtml', () {
    test('safe mode removes executable book markup and preserves content', () {
      const html =
          '<html><head><style>.page { color: red; }</style></head>'
          '<body onload="bookBoot()" data-onload="keep">'
          '<script>window.bookScript = true;</script>'
          '<a href="javascript:alert(1)" onclick="bookClick()">blocked</a>'
          '<a href="https://example.com">external</a><a href="#chapter">anchor</a>'
          '<img src="cover.png" alt="cover" onerror="bookError()"/>'
          '</body></html>';

      final sanitized = sanitizeBookHtml(html);

      expect(sanitized, isNot(contains('<script')));
      expect(sanitized, isNot(contains('bookScript')));
      expect(sanitized, isNot(contains(' onload=')));
      expect(sanitized, isNot(contains('onclick=')));
      expect(sanitized, isNot(contains('onerror=')));
      expect(sanitized, isNot(contains('javascript:')));
      expect(sanitized, contains('<style>.page { color: red; }</style>'));
      expect(sanitized, contains('data-onload="keep"'));
      expect(sanitized, contains('href="https://example.com"'));
      expect(sanitized, contains('href="#chapter"'));
      expect(sanitized, contains('src="cover.png"'));
      expect(sanitized, contains('>blocked</a>'));
    });

    test('safe mode catches encoded and whitespace-obscured JavaScript URLs', () {
      const html =
          '<a href="java&#x73;cript&#x3a;alert(1)">one</a>'
          '<svg><image xlink:href="java\nscript:alert(2)"/></svg>'
          '<img src="cover.png" onload=run() style="color: red"/>';

      final sanitized = sanitizeBookHtml(html);

      expect(sanitized, isNot(contains('href="')));
      expect(sanitized, isNot(contains('onload=')));
      expect(sanitized, contains('src="cover.png"'));
      expect(sanitized, contains('style="color: red"'));
    });

    test('trusted policy preserves book-authored scripts', () {
      const html =
          '<script>window.bookScript = true;</script>'
          '<button onclick="bookClick()">Run</button>'
          '<a href="javascript:bookLink()">link</a>';

      expect(sanitizeBookHtml(html, policy: BookJavaScriptPolicy.allowBookScripts), html);
    });

    test('preserves comments and handles incomplete or malformed markup safely', () {
      const completeComment = '<!-- retained --><p>Visible</p>';
      const incompleteComment = '<p>Visible</p><!-- truncated';

      expect(sanitizeBookHtml(completeComment), completeComment);
      expect(sanitizeBookHtml(incompleteComment), incompleteComment);
      expect(sanitizeBookHtml('<p>Visible</p><script>run()'), '<p>Visible</p>');
      expect(sanitizeBookHtml('<p onclick="run()"'), '<p');
      expect(
        sanitizeBookHtml('<p == malformed data-ready="yes">Visible</p>'),
        '<p== malformed data-ready="yes">Visible</p>',
      );
    });

    test('decodes decimal character references before checking unsafe URLs', () {
      const html = '<a href="java&#115;cript&#58;alert(1)">blocked</a>';

      expect(sanitizeBookHtml(html), '<a>blocked</a>');
    });
  });

  group('resolveBookPath', () {
    test('resolves sibling and nested references', () {
      expect(
        resolveBookPath('ch2.xhtml', fromPath: 'OEBPS/text/ch1.xhtml'),
        'OEBPS/text/ch2.xhtml',
      );
      expect(
        resolveBookPath('images/x.png', fromPath: 'OEBPS/text/ch1.xhtml'),
        'OEBPS/text/images/x.png',
      );
    });

    test('climbs directories and normalizes segments', () {
      expect(
        resolveBookPath('../images/x.png', fromPath: 'OEBPS/text/ch1.xhtml'),
        'OEBPS/images/x.png',
      );
      expect(resolveBookPath('../../a/b.png', fromPath: 'OEBPS/text/ch1.xhtml'), 'a/b.png');
      expect(resolveBookPath('./x.png', fromPath: 'ch1.xhtml'), 'x.png');
    });

    test('treats leading slash as book-root relative', () {
      expect(resolveBookPath('/images/x.png', fromPath: 'OEBPS/text/ch1.xhtml'), 'images/x.png');
    });
  });

  group('rewriteHtmlResources', () {
    String? resolve(String path) => 'blob:https://x/$path';

    test('rewrites resource attributes to absolute URLs', () {
      final html = rewriteHtmlResources(
        '<p><img src="pic.png"/><img src="../other/pic.png" alt=""/></p>',
        pagePath: 'OEBPS/ch1.xhtml',
        resolve: resolve,
      );
      expect(html, contains('src="blob:https://x/OEBPS/pic.png"'));
      expect(html, contains('src="blob:https://x/other/pic.png"'));
    });

    test('rewrites stylesheet links but not anchors', () {
      final html = rewriteHtmlResources(
        '<link rel="stylesheet" href="style.css"/>'
        '<a href="ch2.xhtml#note">next</a><a href="#top">top</a>',
        pagePath: 'OEBPS/ch1.xhtml',
        resolve: resolve,
      );
      expect(html, contains('href="blob:https://x/OEBPS/style.css"'));
      expect(html, contains('href="ch2.xhtml#note"'));
      expect(html, contains('href="#top"'));
    });

    test('leaves absolute urls, data uris and missing files alone', () {
      final html = rewriteHtmlResources(
        '<img src="https://cdn/x.png"/><img src="data:image/png;base64,AA"/>'
        '<img src="missing.png"/>',
        pagePath: 'ch1.xhtml',
        resolve: (path) => path == 'missing.png' ? null : 'blob:$path',
      );
      expect(html, contains('src="https://cdn/x.png"'));
      expect(html, contains('src="data:image/png;base64,AA"'));
      expect(html, contains('src="missing.png"'));
    });

    test('rewrites every candidate of a srcset', () {
      final html = rewriteHtmlResources(
        '<source srcset="small.png 1x, big.png 2x"/>',
        pagePath: 'ch1.xhtml',
        resolve: resolve,
      );
      expect(html, contains('srcset="blob:https://x/small.png 1x, blob:https://x/big.png 2x"'));
    });

    test('preserves fragment-only and unresolved resources', () {
      const html = '<svg><image href="#cover"/></svg><source srcset="missing.png 1x"/>';

      expect(rewriteHtmlResources(html, pagePath: 'chapter.xhtml', resolve: (_) => null), html);
    });

    test('resolves a resource path without carrying its fragment', () {
      final html = rewriteHtmlResources(
        '<img src="cover.png#front"/>',
        pagePath: 'OEBPS/text/chapter.xhtml',
        resolve: (path) => 'blob:$path',
      );

      expect(html, '<img src="blob:OEBPS/text/cover.png"/>');
    });

    test('rewrites url() inside style blocks and attributes', () {
      final html = rewriteHtmlResources(
        '<style>body{background:url(bg.png)}</style><div style="background:url(\'sub/bg.png\')"/>',
        pagePath: 'ch1.xhtml',
        resolve: resolve,
      );
      expect(html, contains('url("blob:https://x/bg.png")'));
      expect(html, contains("url('blob:https://x/sub/bg.png')"));
    });

    test('rewrites svg image references', () {
      final html = rewriteHtmlResources(
        '<svg><image xlink:href="pic.png"/><image href="pic2.png"/></svg>',
        pagePath: 'ch1.xhtml',
        resolve: resolve,
      );
      expect(html, contains('xlink:href="blob:https://x/pic.png"'));
      expect(html, contains('href="blob:https://x/pic2.png"'));
    });
  });

  group('rewriteCssResources', () {
    String? resolve(String path) => 'blob:https://x/$path';

    test('rewrites quoted and bare url() references', () {
      final css = rewriteCssResources(
        '@font-face{src:url(fonts/a.ttf)} .x{background:url("img/b.png")}',
        cssPath: 'OEBPS/style.css',
        resolve: resolve,
      );
      expect(css, contains('url("blob:https://x/OEBPS/fonts/a.ttf")'));
      expect(css, contains('url("blob:https://x/OEBPS/img/b.png")'));
    });

    test('rewrites @import and skips data uris', () {
      final css = rewriteCssResources(
        "@import 'extra.css'; body{background:url(data:image/gif;base64,AA)}",
        cssPath: 'style.css',
        resolve: resolve,
      );
      expect(css, contains("@import 'blob:https://x/extra.css'"));
      expect(css, contains('url(data:image/gif;base64,AA)'));
    });
  });

  group('injections', () {
    test('spread half rewrites page resources before creating a blob document', () {
      const html =
          '<html><head><meta name="viewport" content="width=800,height=1200">'
          '<link rel="stylesheet" href="../Styles/page.css"></head>'
          '<body><img src="../Images/page.png"/></body></html>';

      final prepared = prepareSpreadHalfHtml(
        html,
        pagePath: 'OEBPS/Text/page.xhtml',
        resolve: (path) => 'blob:$path',
        cssUrl: 'blob:viewer.css',
        jsUrl: 'blob:viewer.js',
        policy: BookJavaScriptPolicy.disabled,
        fixedPage: const FixedPagePresentation(viewportWidth: 800, viewportHeight: 1200),
        mathJaxScriptBase: null,
      );

      expect(prepared, contains('href="blob:OEBPS/Styles/page.css"'));
      expect(prepared, contains('src="blob:OEBPS/Images/page.png"'));
      expect(prepared, contains('class="elv-fixed"'));
      expect(prepared, contains('data-elv-page="800×1200"'));
      expect(prepared, contains('name="viewport" content="width=device-width'));
      expect(prepared, isNot(contains('content="width=800,height=1200"')));
      expect(prepared, contains('__elvFrame'));
      expect(prepared, contains('src="blob:viewer.js"'));
    });

    test('injectViewerAssets falls back to a synthesized head', () {
      final out = injectViewerAssets('<p>no head</p>', cssUrl: 'blob:css', jsUrl: 'blob:js');
      expect(out, startsWith('<!DOCTYPE html>'));
      expect(out, contains('href="blob:css"'));
      expect(out, contains('src="blob:js"'));
      expect(out, contains('<p>no head</p>'));
    });

    test('injectMathJax points at the given script base', () {
      final out = injectMathJax(
        '<html><head></head><body><math/></body></html>',
        scriptBase: 'https://cdn/js',
      );
      expect(out, contains('src="https://cdn/js/tex-mml-svg.js"'));
      expect(out, contains('window.MathJax='));
    });

    test('fixed page markers synthesize a body when book markup omits it', () {
      final out = injectFixedPageMarkers(
        '<p>Fixed page</p>',
        presentation: const FixedPagePresentation(viewportWidth: 600, viewportHeight: 800),
      );

      expect(out, contains('<body class="elv-fixed" data-elv-page="600×800">'));
      expect(out, contains('<p>Fixed page</p>'));
    });

    test('fixed page markers merge body classes and normalize self-closing tags', () {
      final out = injectFixedPageMarkers(
        '<html><body class="book-page"/>Page</html>',
        presentation: const FixedPagePresentation(viewportWidth: 600, viewportHeight: 800),
      );

      expect(out, contains('<body class="book-page elv-fixed" data-elv-page="600×800">'));
      expect(out, contains('Page</html>'));
    });

    test('the complete viewer pipeline can add MathJax after the viewer assets', () {
      final out = finishBookHtmlForViewer(
        '<html><head></head><body><math/></body></html>',
        cssUrl: 'blob:viewer.css',
        jsUrl: 'blob:viewer.js',
        mathJaxScriptBase: 'blob:mathjax',
      );

      expect(out, contains('href="blob:viewer.css"'));
      expect(out, contains('src="blob:viewer.js"'));
      expect(out, contains('src="blob:mathjax/tex-mml-svg.js"'));
    });

    test('syntheticComicPageHtml wraps the image with the viewer', () {
      final out = syntheticComicPageHtml(
        imageUrl: 'blob:img',
        cssUrl: 'blob:css',
        jsUrl: 'blob:js',
      );
      expect(out, contains('class="elv-comic"'));
      expect(out, contains('<img src="blob:img"'));
    });

    test('mimeOf covers reader fallbacks', () {
      expect(mimeOf('a.xhtml'), 'application/xhtml+xml');
      expect(mimeOf('a.ttf'), 'font/ttf');
      expect(mimeOf('a.unknown'), 'application/octet-stream');
    });

    test('lookupBookFile falls back through case and basename', () {
      final files = <String, Object>{
        'OEBPS/Images/Cover.png': Uint8List(0),
        'OEBPS/style.CSS': 'p{}',
      };
      expect(lookupBookFile(files, 'OEBPS/images/cover.png')?.key, 'OEBPS/Images/Cover.png');
      expect(lookupBookFile(files, 'oebps/style.css')?.key, 'OEBPS/style.CSS');
      expect(lookupBookFile(files, 'Cover.png')?.key, 'OEBPS/Images/Cover.png');
      expect(lookupBookFile(files, 'nope.txt'), isNull);
    });
  });
}
