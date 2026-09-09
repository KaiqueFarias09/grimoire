import 'dart:async';

import 'package:e_livre/e_livre.dart';
import 'package:flutter/material.dart';

import '../controller/viewer_controller.dart';
import '../features/bridge/viewer_bridge.dart';
import '../features/navigation/viewer_position.dart';
import '../features/serving/book_content.dart';
import 'reader_shell.dart';

/// Renders a parsed [Book] as a Calibre-style paginated reader.
///
/// ```dart
/// final book = await EBook.openFromPath(path);
/// ELivreView(book: book);
/// ```
///
/// The reader keeps two webviews: the visible one and a spare that
/// preloads the next file, so chapter transitions are instant.
///
/// Pass your own [controller] to drive the reader (positions,
/// bookmarks, highlights, search, themes) from the outside;
/// otherwise the view creates and owns one.
class ELivreView extends StatefulWidget {
  /// Creates the reader view.
  const ELivreView({
    required this.book,
    this.controller,
    this.initialPosition,
    this.onPositionChanged,
    this.onSelection,
    this.onExternalLink,
    this.onReady,
    this.onViewImage,
    this.onFootnoteTap,
    this.showShell = true,
    this.bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    super.key,
  });

  /// The parsed book to render.
  final Book book;

  /// Optional external controller.
  final ViewerController? controller;

  /// Serialized position ([ViewerPosition.serialize]) restored on
  /// start.
  final String? initialPosition;

  /// Called on every position change (convenience over the
  /// controller's `addListener`).
  final ValueChanged<ViewerPosition>? onPositionChanged;

  /// Called when the user selects text (dictionary hook).
  final ValueChanged<ViewerSelection>? onSelection;

  /// Called when the user taps an external http(s) link.
  final ValueChanged<String>? onExternalLink;

  /// Called once the first file is loaded and laid out.
  final VoidCallback? onReady;

  /// Custom image viewer hook. When null, a fullscreen
  /// InteractiveViewer dialog is used.
  final ValueChanged<String>? onViewImage;

  /// Called when the reader taps a footnote reference (after the
  /// navigation to the footnote target already happened).
  final ValueChanged<FootnoteTapEvent>? onFootnoteTap;

  /// Whether to render the built-in reader chrome ([ReaderShell]).
  /// Host apps that provide their own chrome (toolbars, TOC,
  /// notebook) set this to false and drive everything through the
  /// [controller].
  final bool showShell;

  /// Controls JavaScript authored by book HTML when this widget
  /// creates its own [ViewerController]. The default disables book
  /// scripts while preserving eLivreViewer's injected viewer and
  /// bridge scripts. Use [BookJavaScriptPolicy.allowBookScripts] only
  /// for trusted books. When [controller] is supplied, configure its
  /// policy through [ViewerController.bookJavaScriptPolicy].
  final BookJavaScriptPolicy bookJavaScriptPolicy;

  @override
  State<ELivreView> createState() => _ELivreViewState();
}

class _ELivreViewState extends State<ELivreView> {
  ViewerController? _ownedController;
  late final Future<void> _startFuture;
  bool _wired = false;

  ViewerController get _controller =>
      widget.controller ??
      (_ownedController ??= ViewerController(
        widget.book,
        bookJavaScriptPolicy: widget.bookJavaScriptPolicy,
      ));

  @override
  void initState() {
    super.initState();
    _startFuture = _boot();
  }

  @override
  void didUpdateWidget(final ELivreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showShell != widget.showShell) {
      _controller.useHostChrome = !widget.showShell;
    }
  }

  StreamSubscription<String>? _imagePopupSub;
  StreamSubscription<ViewerPageChange>? _pageChangeSub;
  String _pageAnnouncement = '';
  StreamSubscription<FootnoteTapEvent>? _footnoteSub;
  bool _positionListenerAttached = false;
  StreamSubscription<ViewerSelection>? _selectionSub;

  Future<void> _boot() async {
    final controller = _controller;
    controller.useHostChrome = !widget.showShell;
    if (widget.onExternalLink != null) {
      controller.onExternalLink = widget.onExternalLink;
    }
    await controller.start();
    unawaited(
      controller.ready.then((final _) {
        if (mounted) {
          widget.onReady?.call();
        }
      }),
    );
    _imagePopupSub = controller.imagePopupEvents.listen((final src) {
      if (!mounted) {
        return;
      }
      final custom = widget.onViewImage;
      if (custom != null) {
        custom(src);
      } else {
        _showImagePopup(src);
      }
    });
    _pageChangeSub = controller.pageChanges.listen((final change) {
      if (!mounted) {
        return;
      }
      final percent = (change.progress * 100).round();
      final page = change.position.column + 1;
      final total = change.position.columns;
      final chapter = change.chapterTitle;
      setState(() {
        _pageAnnouncement =
            'Page $page of $total'
            '${chapter != null ? ', $chapter' : ''}, $percent percent';
      });
    });
    _footnoteSub = controller.footnoteTapEvents.listen((final event) {
      if (!mounted) {
        return;
      }
      if (event.text != null && !controller.useHostChrome) {
        _showFootnotePopup(event);
      }
      widget.onFootnoteTap?.call(event);
    });
    if (widget.initialPosition != null) {
      await controller.goToSerializedPosition(widget.initialPosition!);
    }
    if (!_wired && (widget.onPositionChanged != null || widget.onSelection != null)) {
      _wired = true;
      if (widget.onPositionChanged != null) {
        controller.addListener(_notifyPosition);
        _positionListenerAttached = true;
      }
      if (widget.onSelection != null) {
        _selectionSub = controller.selectionEvents.listen((final selection) {
          if (mounted) {
            widget.onSelection?.call(selection);
          }
        });
      }
    }
  }

  void _showFootnotePopup(final FootnoteTapEvent event) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (final sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (final sheetContext, final scrollController) => _FootnoteSheet(
          event: event,
          scrollController: scrollController,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  void _notifyPosition() {
    if (mounted) {
      widget.onPositionChanged?.call(_controller.position);
    }
  }

  void _showImagePopup(final String src) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (final dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: InteractiveViewer(
            maxScale: 8,
            child: Center(
              child: Image.network(
                src,
                fit: BoxFit.contain,
                errorBuilder: (final context, final error, final stack) =>
                    const Icon(Icons.broken_image, size: 48, color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _imagePopupSub?.cancel();
    _footnoteSub?.cancel();
    _pageChangeSub?.cancel();
    unawaited(_selectionSub?.cancel());
    if (_positionListenerAttached) {
      _controller.removeListener(_notifyPosition);
    }
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return FutureBuilder<void>(
      future: _startFuture,
      builder: (final context, final snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.white,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to open book: ${snapshot.error}'));
        }
        final controller = _controller;
        return AnimatedBuilder(
          animation: controller,
          builder: (final context, final _) {
            final engines = controller.engines;
            final active = controller.activeEngineIndex;
            final below = 1 - active;
            // LayoutBuilder reports the real webview box: embedded iOS
            // WebViews cannot be trusted to measure themselves (the
            // MediaQuery size is the whole screen, not this widget).
            // The horizontal padding insets the webview with the reader
            // margins — the Calibre desktop viewer frames its iframe
            // the same way (margin: 0 on the body, but the frame comes
            // from the window), so text never touches the edges.
            return SafeArea(
              child: LayoutBuilder(
                builder: (final context, final outer) {
                  // Calibre View.set_margins: the text-block caps grow
                  // the margins instead of shrinking the page.
                  final insets = controller.margins.insetsFor(
                    availableWidth: outer.maxWidth,
                    availableHeight: outer.maxHeight,
                  );
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      insets.left,
                      insets.top,
                      insets.right,
                      insets.bottom,
                    ),
                    child: LayoutBuilder(
                      builder: (final context, final constraints) {
                        controller.setLogicalViewport(constraints.maxWidth, constraints.maxHeight);
                        // The announcement must be positioned: a
                        // zero-size non-positioned child collapses the
                        // stack, and a zero-size platform view never
                        // attaches on the web.
                        return Stack(
                          children: [
                            // Screen readers announce page turns
                            // (TalkBack/VoiceOver live region).
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Semantics(
                                  liveRegion: true,
                                  label: _pageAnnouncement,
                                  child: const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            // Inactive engine below (preloaded content), active on
                            // top, reader chrome overlays everything.
                            if (engines.length > below)
                              Positioned.fill(child: engines[below].buildWidget()),
                            if (engines.length > active)
                              Positioned.fill(child: engines[active].buildWidget()),
                            if (widget.showShell)
                              Positioned.fill(child: ReaderShell(controller: controller)),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// Built-in popup for footnote bodies in footnote popup mode.
class _FootnoteSheet extends StatelessWidget {
  const _FootnoteSheet({required this.event, required this.scrollController, this.onClose});

  final FootnoteTapEvent event;
  final ScrollController scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text('Footnote', style: theme.textTheme.titleMedium)),
              IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: SelectableText(event.text!, style: theme.textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}
