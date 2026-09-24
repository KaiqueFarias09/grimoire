/// Meta cell for the detail page's meta strip, ported 1:1 from the
/// prototype's `_MetaCell`.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// An upper-cased label over a bold value, filling one meta column.
class MetaCell extends StatelessWidget {
  const MetaCell({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 10, letterSpacing: 10 * 0.06, color: palette.subtle),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.ink),
          ),
        ],
      ),
    );
  }
}
