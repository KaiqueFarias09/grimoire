import 'package:e_livre_viewer/src/features/settings/viewer_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('css vars render as css colors', () {
    final vars = ViewerTheme.sepia.cssVars();
    expect(vars['--elv-bg'], '#f4ecd8');
    expect(vars['--elv-fg'], '#4a3f35');
    expect(vars['--elv-link'], '#8a5a2b');
    expect(vars['--elv-selection-bg'], startsWith('rgba(138, 90, 43,'));
  });

  test('system follows brightness', () {
    expect(ViewerTheme.system(Brightness.dark).background,
        ViewerTheme.dark.background);
    expect(ViewerTheme.system(Brightness.light).background,
        ViewerTheme.light.background);
  });

  test('copyWith keeps untouched fields', () {
    final theme = ViewerTheme.light.copyWith(overrideBookColors: true);
    expect(theme.background, ViewerTheme.light.background);
    expect(theme.overrideBookColors, isTrue);
  });
}
