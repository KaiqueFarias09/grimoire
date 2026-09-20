/// Design tokens for the Unseal Books demo, ported 1:1 from the
/// prototype's CSS custom properties (light and dark schemes).
library;

import 'package:flutter/material.dart';

@immutable
class UbPalette {
  const UbPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.subtle,
    required this.line,
    required this.lineSoft,
    required this.blue,
    required this.blueSoft,
    required this.highlight,
    required this.inverseBg,
    required this.inverseFg,
    required this.surfaceRaised,
    required this.sidebar,
    required this.nightPaper,
    required this.pdfSurface,
    required this.barrier,
    required this.sheetBarrier,
  });

  factory UbPalette.light() => const UbPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F7),
    surface2: Color(0xFFFBFBFD),
    paper: Color(0xFFFBFAF6),
    ink: Color(0xFF1D1D1F),
    muted: Color(0xFF6E6E73),
    subtle: Color(0xFF86868B),
    line: Color(0xFFD2D2D7),
    lineSoft: Color(0xFFE8E8ED),
    blue: Color(0xFF007AFF),
    blueSoft: Color(0xFFEAF3FF),
    highlight: Color(0xFFFFF0A6),
    inverseBg: Color(0xFF1D1D1F),
    inverseFg: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF5F5F7),
    nightPaper: Color(0xFF232323),
    pdfSurface: Color(0xFFFFFFFF),
    barrier: Color(0x61000000),
    sheetBarrier: Color(0x52000000),
  );

  factory UbPalette.dark() => const UbPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF1C1C1E),
    surface: Color(0xFF2C2C2E),
    surface2: Color(0xFF242426),
    paper: Color(0xFF292725),
    ink: Color(0xFFF5F5F7),
    muted: Color(0xFFAEAEB2),
    subtle: Color(0xFF8E8E93),
    line: Color(0xFF48484A),
    lineSoft: Color(0xFF38383A),
    blue: Color(0xFF007AFF),
    blueSoft: Color(0xFF1F344E),
    highlight: Color(0xFF6D5D18),
    // Dark scheme inverts the dark buttons, brand mark and toast.
    inverseBg: Color(0xFFF5F5F7),
    inverseFg: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF3A3A3C),
    sidebar: Color(0xFF2C2C2E),
    nightPaper: Color(0xFF111111),
    pdfSurface: Color(0xFFF7F7F7),
    barrier: Color(0x94000000),
    sheetBarrier: Color(0x52000000),
  );

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color subtle;
  final Color line;
  final Color lineSoft;
  final Color blue;
  final Color blueSoft;
  final Color highlight;
  final Color inverseBg;
  final Color inverseFg;
  final Color surfaceRaised;
  final Color sidebar;
  final Color nightPaper;
  final Color pdfSurface;
  final Color barrier;
  final Color sheetBarrier;

  List<BoxShadow> get cardShadow => <BoxShadow>[
    const BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 34,
      spreadRadius: -12,
      offset: Offset(0, 12),
    ),
  ];
}

/// Text styles ported from the prototype. Sizes are logical px, equal
/// to the prototype's CSS px at 100% zoom.
@immutable
class UbType {
  const UbType._();

  static const String serif = 'Georgia';
  static const List<String> serifFallback = <String>['Iowan Old Style', 'Times New Roman'];

  static TextStyle serifTitle(
    final double size, {
    final double letterSpacingEm = -0.04,
    final double height = 1.03,
  }) {
    return TextStyle(
      fontFamily: serif,
      fontFamilyFallback: serifFallback,
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: letterSpacingEm * size,
      height: height,
      color: const Color(0xFF1D1D1F),
    );
  }
}

/// Makes the palette reachable from any widget below [BooksApp].
class UbScope extends InheritedWidget {
  const UbScope({required this.palette, required super.child, super.key});

  final UbPalette palette;

  static UbPalette of(final BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UbScope>();
    return scope!.palette;
  }

  @override
  bool updateShouldNotify(final UbScope oldWidget) => oldWidget.palette != palette;
}

/// Resolves the prototype's clamp() paddings for the current width.
double ubPagePadding(final double width) => width.clamp(24.0, 64.0);

/// clamp(30px, 4vw, 42px)
double ubH1Size(final double width) => (width * 0.04).clamp(30.0, 42.0);

/// clamp(31px, 4vw, 52px)
double ubContinueTitleSize(final double width) => (width * 0.04).clamp(31.0, 52.0);

/// clamp(28px, 6vw, 70px) vertical paper padding
double ubPaperPaddingV(final double width) => (width * 0.06).clamp(28.0, 70.0);

/// clamp(22px, 7vw, 100px) horizontal paper padding
double ubPaperPaddingH(final double width) => (width * 0.07).clamp(22.0, 100.0);

/// clamp(23px, 5vw, 58px) PDF padding
double ubPdfPadding(final double width) => (width * 0.05).clamp(23.0, 58.0);

/// clamp(27px, 4vw, 42px) reader chapter title
double ubReaderH2Size(final double width) => (width * 0.04).clamp(27.0, 42.0);

/// clamp(17px, 2vw, 22px) reader body text
double ubReaderBodySize(final double width) => (width * 0.02).clamp(17.0, 22.0);

/// clamp(22px, 4vw, 46px) continue card gap
double ubContinueGap(final double width) => (width * 0.04).clamp(22.0, 46.0);

/// clamp(22px, 4vw, 42px) continue card padding
double ubContinuePadding(final double width) => (width * 0.04).clamp(22.0, 42.0);

/// clamp(32px, 5vw, 56px) detail title
double ubDetailTitleSize(final double width) => (width * 0.05).clamp(32.0, 56.0);

/// clamp(28px, 6vw, 74px) detail gap
double ubDetailGap(final double width) => (width * 0.06).clamp(28.0, 74.0);
