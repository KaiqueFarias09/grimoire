import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression contract for the Android WebView theme-repaint bug:
/// flipping only the --elv-* custom properties on :root does not
/// invalidate the var()-driven html/body paint, so the first page of
/// a section kept the previous theme's colors (white defaults over a
/// dark theme and the reverse) while the columns beyond the body box
/// picked the new colors up. applyVars must therefore re-emit the
/// base color rules as literal declarations through the
/// `elv-theme-colors` sheet, which invalidates reliably.
void main() {
  test('applyVars re-emits the theme colors as literal rules', () {
    final source = File('assets/viewer/viewer.js').readAsStringSync();

    expect(source, contains("getElementById('elv-theme-colors')"));
    expect(source, contains("vars['--elv-bg']"));
    expect(source, contains('html, body { background-color: '));
    expect(source, contains('body { color: '));
    expect(source, contains('a, a:link, a:visited { color: '));
    expect(source, contains('::selection { background: '));
  });
}
