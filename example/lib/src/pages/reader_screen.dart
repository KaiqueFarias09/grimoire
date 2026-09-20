/// The reader screen: the prototype's reader chrome (top bar, paper,
/// bottom bar, inline settings, host note) around either the real
/// Grimoire viewer (books with bundled fixtures) or the prototype's
/// mock paper.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:grimoire/grimoire.dart';
import 'package:unseal/unseal.dart' show NavPoint;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_shell.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';

/// Hooks the shell dispatch uses to reach the live reader instance.
/// Registered while a reader is mounted; cleared on dispose.
abstract final class ReaderHooks {
  static Future<void> Function(ReaderThemeMode)? applyTheme;
  static Future<void> Function(ReaderMode)? applyMode;
  static Future<void> Function(String)? applyFontSize;
  static void Function()? addBookmark;
  static void Function(String? data)? selectedChapter;
  static void Function()? jumpToSearch;
  static List<NavPoint> Function()? tocSource;
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.host, super.key});

  final UbHost host;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  Book? _book;
  ViewerController? _controller;
  String? _loadError;
  double _liveProgress = 0;
  String? _liveChapter;

  DemoBook get demoBook => demoBookById(widget.host.state.selectedBook);

  @override
  void initState() {
    super.initState();
    final asset = demoBook.asset;
    if (asset == null) {
      _registerHooks();
      return;
    }
    unawaited(_loadBook(asset));
  }

  Future<void> _loadBook(final String asset) async {
    try {
      final bytes = Uint8List.fromList((await rootBundle.load(asset)).buffer.asUint8List());
      final book = await Unseal.read(bytes);
      final cachePath = kIsWeb ? '' : (await getTemporaryDirectory()).path;
      if (!mounted) return;
      setState(() => _book = book);
      await _buildController(book, cachePath);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _loadError = '$error');
      }
    }
  }

  Future<void> _buildController(final Book book, final String cachePath) async {
    final state = widget.host.state;
    final controller =
        ViewerController(book, theme: _viewerTheme(state.readerTheme), fontFamily: UbType.serif)
          ..useHostChrome = true
          ..mathJaxCachePath = cachePath
          ..pdfJsCachePath = cachePath;
    controller.pageChanges.listen((final change) {
      if (mounted) {
        setState(() {
          _liveProgress = change.progress;
          _liveChapter = change.chapterTitle;
        });
      }
    });
    setState(() => _controller = controller);
    _registerHooks();
    if (book is PdfBook) {
      await controller.setPdfReadingMode(PdfReadingMode.facsimile);
    }
  }

  ViewerTheme _viewerTheme(final ReaderThemeMode mode) {
    final dark = UbScope.of(context).brightness == Brightness.dark;
    return switch (mode) {
      ReaderThemeMode.day => ViewerTheme(
        background: dark ? const Color(0xFF292725) : const Color(0xFFFBFAF6),
        foreground: dark ? const Color(0xFFE9E9E9) : const Color(0xFF252525),
        link: const Color(0xFF0563C1),
      ),
      ReaderThemeMode.sepia => const ViewerTheme(
        background: Color(0xFFF3ECDC),
        foreground: Color(0xFF252525),
        link: Color(0xFF0563C1),
      ),
      ReaderThemeMode.night => ViewerTheme(
        background: dark ? const Color(0xFF111111) : const Color(0xFF232323),
        foreground: const Color(0xFFE9E9E9),
        link: const Color(0xFF7FB2F0),
      ),
    };
  }

  void _registerHooks() {
    ReaderHooks.applyTheme = (final mode) {
      final controller = _controller;
      if (controller != null) {
        return controller.setTheme(_viewerTheme(mode));
      }
      return Future<void>.value();
    };
    ReaderHooks.applyMode = (final mode) {
      final controller = _controller;
      if (controller != null && _book is PdfBook) {
        return controller.setPdfReadingMode(
          mode == ReaderMode.pages ? PdfReadingMode.facsimile : PdfReadingMode.reflow,
        );
      }
      return Future<void>.value();
    };
    ReaderHooks.applyFontSize = (final size) {
      final controller = _controller;
      if (controller != null) {
        return controller.setFontSize(switch (size) {
          'small' => 15,
          'large' => 20,
          _ => 17,
        });
      }
      return Future<void>.value();
    };
    ReaderHooks.addBookmark = () {
      _controller?.addBookmark();
    };
    ReaderHooks.selectedChapter = (final data) {
      final points = ReaderHooks.tocSource?.call() ?? const <NavPoint>[];
      final index = int.tryParse(data ?? '');
      if (index != null && index >= 0 && index < points.length) {
        unawaited(_controller!.goToNavPoint(points[index]));
      }
    };
    ReaderHooks.jumpToSearch = () {
      final controller = _controller;
      if (controller != null && controller.searchResults.isNotEmpty) {
        unawaited(controller.goToSearchMatch(0));
      }
    };
    ReaderHooks.tocSource = () => _book?.navigation.navPoints ?? const <NavPoint>[];
  }

  @override
  void dispose() {
    ReaderHooks.applyTheme = null;
    ReaderHooks.applyMode = null;
    ReaderHooks.applyFontSize = null;
    ReaderHooks.addBookmark = null;
    ReaderHooks.selectedChapter = null;
    ReaderHooks.jumpToSearch = null;
    ReaderHooks.tocSource = null;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = widget.host.state;
    final controller = _controller;
    final isReal = controller != null && _book != null;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 720 ? 16.0 : (width < 900 ? 28.0 : ubPagePadding(width));

    final Widget content;
    if (isReal) {
      content = Column(
        children: <Widget>[
          Expanded(
            child: _RealPaper(controller: controller, demoBook: demoBook, host: widget.host),
          ),
          _ReaderBottomBar(
            host: widget.host,
            progress: _liveProgress,
            chapterLabel: _liveChapter ?? demoBook.chapter,
          ),
          if (state.readerSettings)
            _ReaderSettingsPanel(host: widget.host, isPdf: _book is PdfBook, isComic: false),
          const _HostNote(),
        ],
      );
    } else if (_loadError != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir este livro: $_loadError',
            style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted),
          ),
        ),
      );
    } else if (demoBook.asset != null) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      content = Column(
        children: <Widget>[
          _MockPaper(host: widget.host),
          _ReaderBottomBar(
            host: widget.host,
            progress: demoBook.progress / 100,
            chapterLabel: demoBook.chapter,
          ),
          if (state.readerSettings)
            _ReaderSettingsPanel(host: widget.host, isPdf: false, isComic: false),
          const _HostNote(),
        ],
      );
    }

    return ColoredBox(
      color: palette.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Column(
            children: <Widget>[
              _ReaderTopBar(host: widget.host),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1050),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontal),
                      child: isReal || demoBook.asset != null || _loadError != null
                          ? content
                          : SingleChildScrollView(
                              // The prototype's `.ub-page` top padding.
                              padding: EdgeInsets.only(top: width < 720 ? 25.0 : 34.0),
                              child: content,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RealPaper extends StatelessWidget {
  const _RealPaper({required this.controller, required this.demoBook, required this.host});

  final ViewerController controller;
  final DemoBook demoBook;
  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final Color paperColor;
    final Color paperBorder;
    switch (state.readerTheme) {
      case ReaderThemeMode.day:
        paperColor = palette.paper;
        paperBorder = palette.lineSoft;
      case ReaderThemeMode.sepia:
        paperColor = const Color(0xFFF3ECDC);
        paperBorder = palette.lineSoft;
      case ReaderThemeMode.night:
        paperColor = palette.nightPaper;
        paperBorder = palette.lineSoft;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: paperColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: paperBorder),
        boxShadow: palette.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: GrimoireView(book: controller.book, controller: controller, showShell: false),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final book = demoBookById(state.selectedBook);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 38),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        UbIcon(UbIcons.arrowLeft, size: 18, color: palette.blue),
                        const SizedBox(width: 3),
                        UbLinkButton(
                          label: 'Voltar',
                          chevron: false,
                          onPressed: () => host.dispatch('reader-back'),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: palette.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${book.author} · ${book.chapter}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              UbIconButton(
                icon: UbIcons.bookmark,
                tooltip: 'Marcar posição',
                active: state.bookmarked,
                onPressed: () => host.dispatch('toggle-bookmark'),
              ),
              const SizedBox(width: 4),
              UbIconButton(
                icon: UbIcons.type,
                tooltip: 'Temas e ajustes',
                active: state.readerSettings,
                onPressed: () => host.dispatch('toggle-reader-settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({required this.host, required this.progress, required this.chapterLabel});

  final UbHost host;
  final double progress;
  final String chapterLabel;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    final Widget progressBar = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Row(
        children: <Widget>[
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
          const SizedBox(width: 9),
          Expanded(child: UbProgressBar(fraction: progress, height: 3)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              chapterLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          children: <Widget>[
            progressBar,
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _ReaderBottomButton(
                  icon: UbIcons.list,
                  label: 'Sumário',
                  onPressed: () => host.dispatch('open-summary-sheet'),
                ),
                _ReaderBottomButton(
                  icon: UbIcons.search,
                  label: 'Buscar',
                  onPressed: () => host.dispatch('open-reader-search-sheet'),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _ReaderBottomButton(
                  icon: UbIcons.highlighter,
                  label: 'Destacar',
                  active: state.highlighted,
                  onPressed: () => host.dispatch('toggle-highlight'),
                ),
                _ReaderBottomButton(
                  icon: UbIcons.note,
                  label: 'Nota',
                  onPressed: () => host.dispatch('open-note'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: <Widget>[
          _ReaderBottomButton(
            icon: UbIcons.list,
            label: 'Sumário',
            onPressed: () => host.dispatch('open-summary-sheet'),
          ),
          const SizedBox(width: 3),
          _ReaderBottomButton(
            icon: UbIcons.search,
            label: 'Buscar',
            onPressed: () => host.dispatch('open-reader-search-sheet'),
          ),
          const SizedBox(width: 16),
          Expanded(child: progressBar),
          const SizedBox(width: 16),
          _ReaderBottomButton(
            icon: UbIcons.highlighter,
            label: 'Destacar',
            active: state.highlighted,
            onPressed: () => host.dispatch('toggle-highlight'),
          ),
          const SizedBox(width: 3),
          _ReaderBottomButton(
            icon: UbIcons.note,
            label: 'Nota',
            onPressed: () => host.dispatch('open-note'),
          ),
        ],
      ),
    );
  }
}

class _ReaderBottomButton extends StatelessWidget {
  const _ReaderBottomButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final String icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        final Color background = active || hovered ? palette.surface : Colors.transparent;
        final Color foreground = active || hovered ? palette.ink : palette.muted;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                UbIcon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, color: foreground)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReaderSettingsPanel extends StatelessWidget {
  const _ReaderSettingsPanel({required this.host, required this.isPdf, required this.isComic});

  final UbHost host;
  final bool isPdf;
  final bool isComic;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Temas e ajustes', style: TextStyle(fontSize: 14, color: palette.ink)),
          const SizedBox(height: 15),
          _SettingRow(
            label: 'Tema',
            options: const <(String, String)>[
              ('Claro', 'day'),
              ('Papel', 'sepia'),
              ('Escuro', 'night'),
            ],
            activeValue: state.readerTheme.name,
            onSelect: (final value) => host.dispatch('reader-theme', data: value),
          ),
          _SettingRow(
            label: 'Texto',
            options: const <(String, String)>[
              ('A menor', 'small'),
              ('A normal', 'medium'),
              ('A maior', 'large'),
            ],
            activeValue: 'medium',
            onSelect: (final value) => host.dispatch('font-size', data: value),
          ),
          if (!isComic)
            _SettingRow(
              label: 'Layout',
              options: <(String, String)>[('Texto', 'reflow'), if (isPdf) ('Páginas', 'pages')],
              activeValue: state.readerMode.name,
              onSelect: (final value) => host.dispatch('reader-mode', data: value),
            ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.options,
    required this.activeValue,
    required this.onSelect,
  });

  final String label;
  final List<(String, String)> options;
  final String activeValue;
  final void Function(String value) onSelect;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: palette.muted)),
          ),
          for (final (label, value) in options)
            _SettingOption(
              label: label,
              active: activeValue == value,
              onTap: () => onSelect(value),
            ),
        ],
      ),
    );
  }
}

class _SettingOption extends StatelessWidget {
  const _SettingOption({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: active ? palette.ink : palette.line),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? palette.ink : palette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _HostNote extends StatelessWidget {
  const _HostNote();

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 17),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UbIcon(UbIcons.info, size: 18, color: palette.muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Você pode retomar, buscar, destacar e anotar este livro. O arquivo original permanece na sua biblioteca.',
              style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's static paper for books without a bundled fixture.
class _MockPaper extends StatelessWidget {
  const _MockPaper({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final book = demoBookById(state.selectedBook);

    if (state.readerMode == ReaderMode.comic) {
      return Container(
        constraints: BoxConstraints(minHeight: isMobile ? 500 : 500),
        padding: const EdgeInsets.all(32),
        color: const Color(0xFFE3C8B7),
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 430, minHeight: 390),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF1D1D1F), width: 7),
              color: const Color(0xFFF2EEE8),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'A cidade\ndepois da chuva',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: UbType.serif,
                      fontFamilyFallback: UbType.serifFallback,
                      fontSize: 32,
                      height: 1.15,
                      leadingDistribution: TextLeadingDistribution.proportional,
                      color: Color(0xFF1D1D1F),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Página 18 · Toque para avançar',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1D1D1F)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (state.readerMode == ReaderMode.pages) {
      return Container(
        constraints: BoxConstraints(minHeight: isMobile ? 460 : 500),
        padding: EdgeInsets.all(isMobile ? 30 : ubPdfPadding(width)),
        decoration: BoxDecoration(
          color: palette.pdfSurface,
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'PÁGINA ${book.progress == 0 ? 12 : book.progress}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 11 * 0.08,
                color: palette.subtle,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'O pequeno atlas das ideias',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.proportional,
                color: Color(0xFF2C2C2E),
              ),
            ),
            const SizedBox(height: 20),
            const _PdfParagraph(
              'Uma página fixa pode preservar a composição original, as imagens e as margens do documento.',
            ),
            const SizedBox(height: 15),
            const _PdfParagraph(
              'Quando fizer sentido, o leitor também pode oferecer uma leitura contínua para acompanhar o texto com mais conforto.',
            ),
            const SizedBox(height: 15),
            const _PdfParagraph(
              'Escolha o modo de leitura em “Aa” para experimentar as duas experiências.',
            ),
          ],
        ),
      );
    }

    final (Color paperColor, Color textColor) = switch (state.readerTheme) {
      ReaderThemeMode.day => (palette.paper, const Color(0xFF252525)),
      ReaderThemeMode.sepia => (const Color(0xFFF3ECDC), const Color(0xFF252525)),
      ReaderThemeMode.night => (palette.nightPaper, const Color(0xFFE9E9E9)),
    };

    return Container(
      constraints: BoxConstraints(minHeight: isMobile ? 460 : 500),
      padding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 22, vertical: 30)
          : EdgeInsets.symmetric(
              horizontal: ubPaperPaddingH(width),
              vertical: ubPaperPaddingV(width),
            ),
      decoration: BoxDecoration(
        color: paperColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: palette.lineSoft),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            book.chapter.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 11 * 0.11,
              color: Color(0xFF8B6F5A),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            'Conselhos de uma lagarta',
            style: TextStyle(
              fontFamily: UbType.serif,
              fontFamilyFallback: UbType.serifFallback,
              fontSize: isMobile ? 27 : ubReaderH2Size(width),
              fontWeight: FontWeight.w500,
              letterSpacing: (isMobile ? 27 : ubReaderH2Size(width)) * -0.03,
              height: 1.08,
              leadingDistribution: TextLeadingDistribution.proportional,
              color: textColor,
            ),
          ),
          const SizedBox(height: 28),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Text(
              'Alice estava começando a ficar muito cansada de ficar sentada ao lado da irmã na margem do rio, sem ter nada para fazer. Uma ou duas vezes ela tinha espiado o livro que a irmã estava lendo, mas não havia figuras nem diálogos.',
              style: TextStyle(
                fontFamily: UbType.serif,
                fontFamilyFallback: UbType.serifFallback,
                fontSize: isMobile ? 18 : ubReaderBodySize(width),
                height: 1.75,
                leadingDistribution: TextLeadingDistribution.proportional,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: _HighlightedParagraph(
              highlighted: state.highlighted,
              textColor: textColor,
              isMobile: isMobile,
              width: width,
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Text(
              'Capítulo 5 de 12 · 38% concluído',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                leadingDistribution: TextLeadingDistribution.proportional,
                color: palette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfParagraph extends StatelessWidget {
  const _PdfParagraph(this.text);

  final String text;

  @override
  Widget build(final BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.65,
        leadingDistribution: TextLeadingDistribution.proportional,
        color: Color(0xFF2C2C2E),
      ),
    );
  }
}

class _HighlightedParagraph extends StatelessWidget {
  const _HighlightedParagraph({
    required this.highlighted,
    required this.textColor,
    required this.isMobile,
    required this.width,
  });

  final bool highlighted;
  final Color textColor;
  final bool isMobile;
  final double width;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final style = TextStyle(
      fontFamily: UbType.serif,
      fontFamilyFallback: UbType.serifFallback,
      fontSize: isMobile ? 18 : ubReaderBodySize(width),
      height: 1.75,
      leadingDistribution: TextLeadingDistribution.proportional,
      color: textColor,
    );
    if (!highlighted) {
      return Text(
        'E para que serve um livro, pensou Alice, sem figuras nem diálogos?',
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: palette.highlight,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('E para que serve um livro', style: style),
            ),
          ),
          const TextSpan(text: ', pensou Alice, sem figuras nem diálogos?'),
        ],
      ),
    );
  }
}
