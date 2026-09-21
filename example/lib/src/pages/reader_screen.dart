/// The reader screen: the prototype's reader chrome (top bar, paper,
/// bottom bar, inline settings, host note) around either the real
/// Grimoire viewer (books with bundled fixtures) or the prototype's
/// mock paper.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:grimoire/grimoire.dart';
import 'package:unseal/unseal.dart' show NavPoint;
import 'package:path_provider/path_provider.dart';

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
  ViewerController? _controller;
  String? _loadError;
  double _liveProgress = 0;
  String? _liveChapter;
  bool _chromeVisible = true;

  // Cancelled in dispose via a local copy (see dispose); the lint wants
  // the cancel in the creating function, which is not possible here.
  // ignore: cancel_subscriptions
  StreamSubscription<ViewerEvent>? _chromeSub;

  LoadedBook? get entry => widget.host.state.bookById(widget.host.state.selectedBook);

  @override
  void initState() {
    super.initState();
    unawaited(_startViewer());
  }

  Future<void> _startViewer() async {
    final book = entry;
    if (book == null) {
      setState(() => _loadError = 'Livro indisponível.');
      return;
    }
    try {
      final cachePath = kIsWeb ? '' : (await getTemporaryDirectory()).path;
      if (!mounted) return;
      await _buildController(book.book, cachePath);
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
    // With host chrome the center-third tap still emits ChromeToggleEvent;
    // the host owns the bars, so toggle ours.
    _chromeSub = controller.bridge.events.where((final event) => event is ChromeToggleEvent).listen(
      (final _) {
        if (mounted) {
          _toggleChrome();
        }
      },
    );
    if (!mounted) {
      controller.dispose();
      return;
    }
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
      if (controller != null && controller.book is PdfBook) {
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
    ReaderHooks.tocSource = () => _controller?.book.navigation.navPoints ?? const <NavPoint>[];
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
    final chromeSub = _chromeSub;
    if (chromeSub != null) {
      unawaited(chromeSub.cancel());
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final controller = _controller;
    final book = entry;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 720 ? 16.0 : (width < 900 ? 28.0 : ubPagePadding(width));

    final progress = _liveProgress > 0 ? _liveProgress : (book?.fixture.progress ?? 0) / 100;
    final chapterLabel = _liveChapter ?? book?.fixture.chapter ?? '';

    final Widget body;
    if (_loadError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir este livro: $_loadError',
            style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted),
          ),
        ),
      );
    } else if (controller != null && book != null) {
      body = _RealPaper(controller: controller, theme: widget.host.state.readerTheme);
    } else {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ColoredBox(
      color: palette.bg,
      child: Stack(
        children: <Widget>[
          // The paper is full bleed: the webview owns the whole screen,
          // chrome overlays included.
          Positioned.fill(child: body),
          // Side tap surfaces only while the viewer has no webview yet.
          // Once the paper is up, the webview's center third owns the
          // toggle (ChromeToggleEvent) and its edge thirds turn pages,
          // so nothing may cover them.
          if (controller == null && _loadError == null)
            for (final side in <bool>[false, true])
              Positioned(
                top: 70,
                bottom: 120,
                left: side ? null : 0,
                right: side ? 0 : null,
                width: horizontal,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggleChrome),
              ),
          _ReaderAppBar(
            host: widget.host,
            visible: _chromeVisible,
            onBack: () => widget.host.dispatch('reader-back'),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ReaderBottomChrome(
              host: widget.host,
              visible: _chromeVisible,
              progress: progress,
              chapterLabel: chapterLabel,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }
}

class _RealPaper extends StatelessWidget {
  const _RealPaper({required this.controller, required this.theme});

  final ViewerController controller;
  final ReaderThemeMode theme;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final Color paperColor = switch (theme) {
      ReaderThemeMode.day => palette.paper,
      ReaderThemeMode.sepia => const Color(0xFFF3ECDC),
      ReaderThemeMode.night => palette.nightPaper,
    };

    return ColoredBox(
      color: paperColor,
      child: GrimoireView(book: controller.book, controller: controller, showShell: false),
    );
  }
}

/// Pinned reader app bar: back, book title, author and the bookmark
/// and settings actions. Slides away with the rest of the chrome.
class _ReaderAppBar extends StatelessWidget {
  const _ReaderAppBar({required this.host, required this.visible, required this.onBack});

  final UbHost host;
  final bool visible;
  final VoidCallback onBack;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final book = state.bookById(state.selectedBook);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              color: palette.bg,
              border: Border(bottom: BorderSide(color: palette.lineSoft)),
            ),
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    UbIconButton(icon: UbIcons.arrowLeft, tooltip: 'Voltar', onPressed: onBack),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            book?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: palette.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            book == null ? '' : '${book.author} · ${book.fixture.chapter}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: palette.muted),
                          ),
                        ],
                      ),
                    ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned reader bottom chrome: the settings panel and host note when
/// open, plus the navigation/progress bar. Slides away with the rest
/// of the chrome on a center tap.
class _ReaderBottomChrome extends StatelessWidget {
  const _ReaderBottomChrome({
    required this.host,
    required this.visible,
    required this.progress,
    required this.chapterLabel,
  });

  final UbHost host;
  final bool visible;
  final double progress;
  final String chapterLabel;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          decoration: BoxDecoration(
            color: palette.bg,
            border: Border(top: BorderSide(color: palette.lineSoft)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (state.readerSettings) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _ReaderSettingsPanel(host: host, isPdf: false, isComic: false),
                ),
                const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: _HostNote()),
                const SizedBox(height: 10),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _ReaderBottomBarContent(
                  host: host,
                  progress: progress,
                  chapterLabel: chapterLabel,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomBarContent extends StatelessWidget {
  const _ReaderBottomBarContent({
    required this.host,
    required this.progress,
    required this.chapterLabel,
    required this.isMobile,
  });

  final UbHost host;
  final double progress;
  final String chapterLabel;
  final bool isMobile;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;

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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: <Widget>[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: progressBar),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.list,
                    label: 'Sumário',
                    onPressed: () => host.dispatch('open-summary-sheet'),
                  ),
                ),
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.search,
                    label: 'Buscar',
                    onPressed: () => host.dispatch('open-reader-search-sheet'),
                  ),
                ),
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.highlighter,
                    label: 'Destacar',
                    active: state.highlighted,
                    onPressed: () => host.dispatch('toggle-highlight'),
                  ),
                ),
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.note,
                    label: 'Nota',
                    onPressed: () => host.dispatch('open-note'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
