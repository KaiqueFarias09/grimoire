import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/controller/viewer_position.dart';
import 'package:e_livre_viewer/src/widgets/reader_shell.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a parsed [Book] as a Calibre-style paginated reader.
///
/// ```dart
/// final book = await EBook.openFromPath(path);
/// ELivreView(book: book);
/// ```
///
/// Pass your own [controller] to drive the reader (positions, search,
/// themes) from the outside; otherwise the view creates and owns one.
class ELivreView extends StatefulWidget {
  /// Creates the reader view.
  const ELivreView({
    required this.book,
    this.controller,
    this.initialPosition,
    this.onPositionChanged,
    this.onSelection,
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

  @override
  State<ELivreView> createState() => _ELivreViewState();
}

class _ELivreViewState extends State<ELivreView> {
  ViewerController? _ownedController;
  late final Future<WebViewController> _startFuture;
  bool _listening = false;

  ViewerController get _controller =>
      widget.controller ?? (_ownedController ??= ViewerController(widget.book));

  @override
  void initState() {
    super.initState();
    _startFuture = _boot();
  }

  Future<WebViewController> _boot() async {
    final controller = _controller;
    final webview = await controller.start();
    if (widget.initialPosition != null) {
      await controller.goToSerializedPosition(widget.initialPosition!);
    }
    if (!_listening &&
        (widget.onPositionChanged != null || widget.onSelection != null)) {
      _listening = true;
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
    return webview;
  }

  void _notifyPosition() {
    if (mounted) {
      widget.onPositionChanged?.call(_controller.position);
    }
  }

  @override
  void dispose() {
    _ownedController?.removeListener(_notifyPosition);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return FutureBuilder<WebViewController>(
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
        return ReaderShell(controller: _controller);
      },
    );
  }
}
