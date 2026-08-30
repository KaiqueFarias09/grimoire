import 'dart:io' show Platform;

import 'package:e_livre_viewer/src/engine/inappwebview_engine.dart';
import 'package:e_livre_viewer/src/engine/webview_flutter_engine.dart';
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
  Future<void> loadUrl(Uri url);

  /// Evaluates [code] in the current page.
  Future<void> evaluateJavaScript(String code);

  /// Releases platform resources.
  Future<void> dispose();
}

/// Creates the engines used by a reader.
abstract class ViewerEngineFactory {
  /// Creates the two engine slots wired to [onMessage].
  List<ViewerEngine> createPair(
    void Function(Object message, int source) onMessage,
  );

  /// The factory for the running platform: the official
  /// webview_flutter engine on Android, iOS and macOS; Windows and
  /// Linux route to the flutter_inappwebview engine when available.
  static ViewerEngineFactory forCurrentPlatform() {
    return selectForPlatform(
      Platform.isWindows,
      Platform.isLinux,
      desktopFactory: desktopEngineFactory(),
    );
  }

  /// Testable selection: desktop platforms route to
  /// [desktopFactory] when one is registered.
  static ViewerEngineFactory selectForPlatform(
    final bool isWindows,
    final bool isLinux, {
    final ViewerEngineFactory? desktopFactory,
  }) {
    if (isWindows || isLinux) {
      return desktopFactory ?? InAppWebViewEngineFactory();
    }
    return WebviewFlutterEngineFactory();
  }
}

/// Returns the desktop (Windows/Linux) engine factory, or `null`
/// when the flutter_inappwebview adapter is not linked in.
ViewerEngineFactory? desktopEngineFactory() => _registeredDesktopFactory;

ViewerEngineFactory? _registeredDesktopFactory;

/// Registers the desktop engine factory (called by the
/// flutter_inappwebview adapter when it is linked in).
// ignore: avoid_setters_without_getters
set desktopEngineFactoryOverride(final ViewerEngineFactory? factory) {
  _registeredDesktopFactory = factory;
}
