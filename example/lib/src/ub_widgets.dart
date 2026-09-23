/// Shared widgets for the Unseal Books demo chrome: buttons, generated
/// covers, progress bars and small labels, matching the prototype.
library;

import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'ub_icon.dart';
import 'ub_theme.dart';

enum UbButtonVariant { dark, outline, blue, text, plain }

/// Rebuilds [builder] with the hovered state (desktop pointer).
class UbHover extends StatefulWidget {
  const UbHover({required this.builder, super.key});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<UbHover> createState() => _UbHoverState();
}

class _UbHoverState extends State<UbHover> {
  bool _hovered = false;

  @override
  Widget build(final BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (final _) => setState(() => _hovered = true),
      onExit: (final _) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// The prototype's button family: 38px tall, radius 8, 13px/600 labels,
/// 18px icons, 7px gap.
class UbButton extends StatelessWidget {
  const UbButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = UbButtonVariant.outline,
    super.key,
  });

  const UbButton.dark(String label, VoidCallback onPressed, {String? icon, Key? key})
    : this(label: label, onPressed: onPressed, icon: icon, variant: UbButtonVariant.dark, key: key);

  const UbButton.outline(String label, VoidCallback onPressed, {String? icon, Key? key})
    : this(
        label: label,
        onPressed: onPressed,
        icon: icon,
        variant: UbButtonVariant.outline,
        key: key,
      );

  const UbButton.blue(String label, VoidCallback onPressed, {String? icon, Key? key})
    : this(label: label, onPressed: onPressed, icon: icon, variant: UbButtonVariant.blue, key: key);

  const UbButton.text(String label, VoidCallback onPressed, {String? icon, Key? key})
    : this(label: label, onPressed: onPressed, icon: icon, variant: UbButtonVariant.text, key: key);

  final String label;
  final VoidCallback onPressed;
  final String? icon;
  final UbButtonVariant variant;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final Color foreground;
    final Color background;
    final Color hoverBackground;
    final double horizontalPadding;
    switch (variant) {
      case UbButtonVariant.dark:
        foreground = palette.inverseFg;
        background = palette.inverseBg;
        hoverBackground = palette.inverseBg.withValues(alpha: 0.82);
        horizontalPadding = 16;
      case UbButtonVariant.outline:
        foreground = palette.ink;
        background = palette.bg;
        hoverBackground = palette.surface;
        horizontalPadding = 14;
      case UbButtonVariant.blue:
        foreground = Colors.white;
        background = palette.blue;
        hoverBackground = const Color(0xFF006BD6);
        horizontalPadding = 16;
      case UbButtonVariant.text:
        foreground = palette.blue;
        background = Colors.transparent;
        hoverBackground = Colors.transparent;
        horizontalPadding = 7;
      case UbButtonVariant.plain:
        foreground = palette.muted;
        background = Colors.transparent;
        hoverBackground = palette.surface;
        horizontalPadding = 7;
    }

    return UbHover(
      builder: (final context, final hovered) {
        final underline = variant == UbButtonVariant.text && hovered;
        return Semantics(
          button: true,
          label: label,
          onTap: onPressed,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.ease,
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              decoration: BoxDecoration(
                color: hovered ? hoverBackground : background,
                borderRadius: BorderRadius.circular(8),
                border: variant == UbButtonVariant.outline ? Border.all(color: palette.line) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    UbIcon(icon!, size: 18, color: foreground),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                        decoration: underline ? TextDecoration.underline : null,
                        decorationColor: foreground,
                      ),
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

/// Blue inline link with an optional trailing chevron, used next to
/// section headings ("Ver mais >").
class UbLinkButton extends StatelessWidget {
  const UbLinkButton({
    required this.label,
    required this.onPressed,
    this.chevron = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool chevron;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          label: label,
          onTap: onPressed,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.blue,
                    decoration: hovered ? TextDecoration.underline : null,
                    decorationColor: palette.blue,
                  ),
                ),
                if (chevron) ...<Widget>[
                  const SizedBox(width: 3),
                  UbIcon(UbIcons.chevronRight, size: 18, color: palette.blue),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 38x38 transparent icon button, radius 8.
class UbIconButton extends StatelessWidget {
  const UbIconButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
    required this.tooltip,
    this.size = 38,
    super.key,
  });

  final String icon;
  final VoidCallback onPressed;
  final bool active;
  final String tooltip;
  final double size;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        final Color background = active || hovered ? palette.surface : Colors.transparent;
        final Color foreground = active || hovered ? palette.ink : palette.muted;
        final button = Semantics(
          button: true,
          label: tooltip,
          onTap: onPressed,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
              child: Center(child: UbIcon(icon, size: 18, color: foreground)),
            ),
          ),
        );
        return Tooltip(message: tooltip, excludeFromSemantics: true, child: button);
      },
    );
  }
}

/// Book cover slot: the real cover image when Unseal found one,
/// otherwise a subtle card that names the file type clearly (and sits
/// a bit shorter than covered books).
class UbCover extends StatelessWidget {
  const UbCover({required this.entry, this.width, this.minHeight, super.key});

  final LoadedBook entry;
  final double? width;
  final double? minHeight;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final coverFloor = minHeight;

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final resolvedWidth = width ?? constraints.maxWidth;
        // Covered books keep the prototype's 0.68 aspect; cover-less
        // fallbacks are deliberately shorter.
        final heightFactor = entry.hasCover ? 1 / 0.68 : 1 / 1.15;
        final minHeightFloor = entry.hasCover ? (coverFloor ?? 0) : (coverFloor ?? 0) * 0.72;
        final height = (resolvedWidth * heightFactor).clamp(minHeightFloor, double.infinity);

        return Container(
          width: resolvedWidth,
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(3),
              right: Radius.circular(7),
            ),
            boxShadow: entry.hasCover
                ? const <BoxShadow>[
                    BoxShadow(color: Color(0x2B000000), blurRadius: 9, offset: Offset(1, 4)),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(3),
              right: Radius.circular(7),
            ),
            child: entry.hasCover
                ? Image.memory(entry.coverBytes!, fit: BoxFit.cover, gaplessPlayback: true)
                : Container(
                    alignment: Alignment.center,
                    color: palette.surface2,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        UbIcon(UbIcons.bookOpen, size: 20, color: palette.subtle),
                        const SizedBox(height: 7),
                        Text(
                          entry.formatLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: palette.muted,
                          ),
                        ),
                        if (coverFloor != null && coverFloor >= 140) ...<Widget>[
                          const SizedBox(height: 7),
                          Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, height: 1.35, color: palette.subtle),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Track + fill progress bar; fill fraction `0..1`.
class UbProgressBar extends StatelessWidget {
  const UbProgressBar({required this.fraction, this.height = 4, super.key});

  final double fraction;
  final double height;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final width = constraints.maxWidth;
        return Container(
          height: height,
          decoration: BoxDecoration(color: palette.line, borderRadius: BorderRadius.circular(10)),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: width * fraction.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: palette.ink,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );
      },
    );
  }
}
