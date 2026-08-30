import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/controller/viewer_position.dart';
import 'package:e_livre_viewer/src/widgets/reader_shell.dart';
import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  State<ELivreView> createState() => _ELivreViewState();
}

class _ELivreViewState extends State<ELivreView> {
  ViewerController? _ownedController;
  late final Future<void> _startFuture;
  bool _wired = false;

  ViewerController get _controller =>
      widget.controller ?? (_ownedController ??= ViewerController(widget.book));

  @override
  void initState() {
    super.initState();
    _startFuture = _boot();
  }

  StreamSubscription<String>? _imagePopupSub;

  Future<void> _boot() async {
    final controller = _controller;
    if (widget.onExternalLink != null) {
      controller.onExternalLink = widget.onExternalLink;
    }
    await controller.start();
    _imagePopupSub = controller.imagePopupEvents.listen((final src) {
      if (mounted) {
        _showImagePopup(src);
      }
    });
    if (widget.initialPosition != null) {
      await controller.goToSerializedPosition(widget.initialPosition!);
    }
    if (!_wired &&
        (widget.onPositionChanged != null || widget.onSelection != null)) {
      _wired = true;
      if (widget.onPositionChanged != null) {
        controller.addListener(_notifyPosition);
      }
      if (widget.onSelection != null) {
        controller.selectionEvents.listen((final selection) {
          if (mounted) {
            widget.onSelection?.call(selection);
          }
        });
      }
    }
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
                    const Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.white70,
                    ),
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
    _ownedController?.removeListener(_notifyPosition);
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
              child: Padding(
                // Calibre margins: 20 on every side (margin_left/right
                // frame the text horizontally; margin_top/bottom keep
                // it clear of the chrome).
                padding: EdgeInsets.all(controller.marginsPx.toDouble()),
                child: LayoutBuilder(
                  builder: (final context, final constraints) {
                    controller.setLogicalViewport(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return Stack(
                      children: [
                        // Inactive engine below (preloaded content), active on
                        // top, reader chrome overlays everything.
                        if (engines.length > below)
                          Positioned.fill(child: engines[below].buildWidget()),
                        if (engines.length > active)
                          Positioned.fill(child: engines[active].buildWidget()),
                        Positioned.fill(
                          child: ReaderShell(controller: controller),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
