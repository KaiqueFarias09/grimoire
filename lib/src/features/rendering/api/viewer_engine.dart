import 'package:flutter/widgets.dart';

/// A webview engine rendering one reader slot.
///
/// The reader keeps two engines ([slot] 0 and 1): the active one
/// shows the current file while the spare preloads the next chapter,
/// making file transitions instant.
abstract class ViewerEngine {
  /// Creates the engine.
  ViewerEngine({required this.slot, required this.onMessage});

  /// Which reader slot this engine renders (0 or 1).
  final int slot;

  /// Delivers a message from the page's JavaScript channel. The
  /// payload is either a JSON string or a decoded map.
  final void Function(Object message, int source) onMessage;

  /// Whether the engine finished creating its platform webview.
  bool get isCreated;

  /// The platform webview widget.
  Widget buildWidget();

  /// Navigates the engine to [url].
  Future<void> loadUrl(final Uri url);

  /// Evaluates [code] in the current page.
  Future<void> evaluateJavaScript(final String code);

  /// Releases platform resources.
  Future<void> dispose();
}

/// Creates the engines used by a reader.
abstract class ViewerEngineFactory {
  /// Creates the two engine slots wired to [onMessage].
  /// Creates one engine for the page-count measurer (slot >= 2).
  ViewerEngine createEngine(
    final int slot,
    final void Function(Object message, int source) onMessage,
  );

  /// Creates the engine pair (active slot 0 and preloading slot 1)
  /// wired to the host [onMessage] callback.
  List<ViewerEngine> createPair(final void Function(Object message, int source) onMessage);
}
