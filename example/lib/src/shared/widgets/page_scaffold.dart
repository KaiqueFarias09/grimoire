/// Centered page frame shared by the demo pages: `min(1180px, 100%)`
/// wide, with the prototype's viewport-clamped paddings.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final horizontal = isMobile ? 16.0 : (width < 900 ? 28.0 : appPagePadding(width));
    // The system status bar plus the prototype's desktop breathing
    // room; the pages sit under the router now, which adds nothing.
    final systemTop = MediaQuery.paddingOf(context).top + (isMobile ? 0.0 : 12.0);
    final top = systemTop + (isMobile ? 25.0 : 34.0);
    final bottom = isMobile ? 94.0 : 80.0;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom),
          child: child,
        ),
      ),
    );
  }
}

/// The page heading block: overline, big title, subtitle, trailing
/// action aligned to the bottom (start of the text block on mobile).
class AppPageHeading extends StatelessWidget {
  const AppPageHeading({required this.title, required this.subtitle, this.action, super.key});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final titleSize = isMobile ? 32.0 : appH1Size(width);

    final Widget textColumn = Column(
      // Stretched on mobile so the subtitle wraps across the full
      // column exactly like the prototype's block flow.
      crossAxisAlignment: isMobile ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.045 * titleSize,
            height: 1.06,
            leadingDistribution: TextLeadingDistribution.proportional,
            color: palette.ink,
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isMobile ? 23.0 : 30.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.end,
        children: <Widget>[
          // The prototype's flex row leaves the text column at 223px on
          // mobile once the action button takes its share (measured).
          Flexible(
            child: ConstrainedBox(
              constraints: isMobile ? const BoxConstraints(maxWidth: 223) : const BoxConstraints(),
              child: textColumn,
            ),
          ),
          if (action != null) ...<Widget>[const SizedBox(width: 20), action!],
        ],
      ),
    );
  }
}

/// Section heading with title, subtitle and a trailing text link.
class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return Padding(
      padding: EdgeInsets.only(top: isMobile ? 28.0 : 38.0, bottom: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 19.0 : 21.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: (isMobile ? 19.0 : 21.0) * -0.025,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null) AppLinkButton(label: actionLabel!, onPressed: onAction ?? () {}),
        ],
      ),
    );
  }
}
