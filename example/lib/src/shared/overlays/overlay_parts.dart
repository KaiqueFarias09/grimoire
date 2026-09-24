/// Sheet and modal internals shared by several overlays: the framed
/// header, the list blocks, the search box and the modal head.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The sheet's frame: drag handle, title with subtitle and the close
/// button above the sheet body.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onClose,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: palette.line, borderRadius: BorderRadius.circular(99)),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 22 * -0.025,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: palette.muted)),
                ],
              ),
            ),
            const SizedBox(width: 18),
            SheetCloseButton(onClose: onClose),
          ],
        ),
        const SizedBox(height: 18),
        body,
      ],
    );
  }
}

/// The round surface close button sheets use in their header.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Semantics(
      button: true,
      label: 'Fechar painel',
      onTap: onClose,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onClose,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
          child: Center(child: AppIcon(AppIcons.close, size: 18, color: palette.muted)),
        ),
      ),
    );
  }
}

/// The prototype's `.ub-sheet-list`: rows under a soft top border.
class SheetList extends StatelessWidget {
  const SheetList({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      child: Column(children: children),
    );
  }
}

/// A selectable list row with a title, subtitle and optional trailing
/// widget.
class SheetListRow extends StatelessWidget {
  const SheetListRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.active = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool active;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return AppHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          selected: active,
          label: '$title, $subtitle',
          onTap: onTap,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.lineSoft)),
                color: active || hovered ? palette.surface2 : Colors.transparent,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 13, color: palette.ink)),
                  ),
                  if (trailing != null) ...<Widget>[const SizedBox(width: 16), trailing!],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The rounded search input with a trailing submit button.
class SheetSearchBox extends StatefulWidget {
  const SheetSearchBox({
    required this.hint,
    required this.initialValue,
    required this.onSubmitted,
    super.key,
  });

  final String hint;
  final String initialValue;
  final void Function(String value) onSubmitted;

  @override
  State<SheetSearchBox> createState() => _SheetSearchBoxState();
}

class _SheetSearchBoxState extends State<SheetSearchBox> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: <Widget>[
          AppIcon(AppIcons.search, size: 18, color: palette.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(fontSize: 15, color: palette.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
              ),
              onSubmitted: widget.onSubmitted,
            ),
          ),
          AppIconButton(
            icon: AppIcons.arrowRight,
            tooltip: 'Buscar no livro',
            onPressed: () => widget.onSubmitted(_controller.text),
          ),
        ],
      ),
    );
  }
}

/// The soft surface box overlays use for empty and hint states.
class SheetEmptyState extends StatelessWidget {
  const SheetEmptyState(this.message, {super.key});

  final String message;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(9)),
      child: Text(message, style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted)),
    );
  }
}

/// The modal's header: title with subtitle and the close button.
class ModalHead extends StatelessWidget {
  const ModalHead({required this.title, required this.subtitle, required this.onClose, super.key});

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 24 * -0.03,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(subtitle, style: TextStyle(fontSize: 13, height: 1.45, color: palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          ModalCloseButton(onClose: onClose),
        ],
      ),
    );
  }
}

/// The round surface close button modals use in their header.
class ModalCloseButton extends StatelessWidget {
  const ModalCloseButton({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Semantics(
      button: true,
      label: 'Fechar janela',
      onTap: onClose,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onClose,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
          child: Center(child: AppIcon(AppIcons.close, size: 18, color: palette.muted)),
        ),
      ),
    );
  }
}
