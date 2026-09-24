/// The shell's confirmation toast, ported from the prototype's
/// `_UbToast`.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';

/// The dark inverse pill at the bottom-right corner announcing a
/// completed action.
class AppToast extends StatelessWidget {
  const AppToast({required this.message, super.key});

  final String message;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.inverseBg,
        borderRadius: BorderRadius.circular(9),
        boxShadow: <BoxShadow>[
          const BoxShadow(color: Color(0x2E000000), blurRadius: 28, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIcon(AppIcons.checkCircle, size: 18, color: palette.inverseFg),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.35, color: palette.inverseFg),
            ),
          ),
        ],
      ),
    );
  }
}
