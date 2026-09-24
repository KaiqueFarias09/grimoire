/// One reader bottom-bar action: an icon plus label over a hover
/// tint, ported from the prototype's reader footer buttons.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// A single bottom-bar button. A pure component: icon, label and
/// callback only.
class ReaderBottomButton extends StatelessWidget {
  const ReaderBottomButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return AppHover(
      builder: (final context, final hovered) {
        final Color background = hovered ? palette.surface : Colors.transparent;
        final Color foreground = hovered ? palette.ink : palette.muted;

        return Semantics(
          button: true,
          label: label,
          onTap: onPressed,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppIcon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
