/// Building blocks shared by the modal and sheet hosts: the titled
/// section, the action footer row, the error alert banner and the
/// accepted-formats chip list.
library;

import 'package:flutter/material.dart';

import '../ub_icon.dart';
import '../ub_theme.dart';

class UbOverlaySection extends StatelessWidget {
  const UbOverlaySection({
    required this.title,
    required this.description,
    required this.child,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: 14, color: palette.ink)),
          const SizedBox(height: 7),
          Text(description, style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class UbOverlayFooter extends StatelessWidget {
  const UbOverlayFooter({required this.alignment, required this.children, super.key});

  final MainAxisAlignment alignment;
  final List<Widget> children;

  @override
  Widget build(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      // A Wrap, not a Row: two buttons plus their labels overflow
      // narrow phones, so they stack instead.
      child: Wrap(
        alignment: switch (alignment) {
          MainAxisAlignment.end => WrapAlignment.end,
          MainAxisAlignment.center => WrapAlignment.center,
          MainAxisAlignment.spaceBetween => WrapAlignment.spaceBetween,
          _ => WrapAlignment.start,
        },
        spacing: 9,
        runSpacing: 9,
        children: children,
      ),
    );
  }
}

class UbOverlayAlert extends StatelessWidget {
  const UbOverlayAlert(this.message, {super.key});

  final String message;

  @override
  Widget build(final BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UbIcon(UbIcons.alert, size: 18, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFFB42318)),
            ),
          ),
        ],
      ),
    );
  }
}

class UbFormatSection extends StatelessWidget {
  const UbFormatSection({super.key});

  static const _formats = <String>[
    'EPUB',
    'MOBI',
    'AZW3',
    'AZW4',
    'PDF',
    'FB2',
    'TXT',
    'HTML',
    'DOCX',
    'ODT',
    'CBZ / CBR',
    'CB7',
    'CBC',
  ];

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbOverlaySection(
      title: 'Formatos aceitos',
      description: 'Adicione livros, documentos e quadrinhos que você já possui.',
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: <Widget>[
          for (final format in _formats)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.line),
              ),
              child: Text(format, style: TextStyle(fontSize: 11, color: palette.muted)),
            ),
        ],
      ),
    );
  }
}
