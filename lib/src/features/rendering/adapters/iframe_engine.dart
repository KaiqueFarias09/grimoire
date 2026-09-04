import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:e_livre_viewer/src/features/rendering/api/viewer_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// [ViewerEngine] over a native same-origin `<iframe>` (Flutter web).
///
/// Flutter web already runs inside a browser, so no webview plugin is
/// needed: the reader page loads a `blob:` URL prepared by the web
/// book host. Outbound bridge messages arrive via
/// `window.parent.postMessage`; commands go in through
/// `contentWindow.eval` (same origin, so this is allowed). Each
/// engine only accepts messages whose `event.source` is its own
/// frame, which routes the two reader slots and the measurer
/// correctly without touching the shared viewer script.
class IframeEngine extends ViewerEngine {
  /// Creates the engine. The iframe element is created when the
  /// widget first mounts ([buildWidget]).
  IframeEngine({required super.slot, required super.onMessage}) {
    _subscription = web.window.onMessage.listen(_onWindowMessage);
  }

  web.HTMLIFrameElement? _iframe;
  StreamSubscription<web.MessageEvent>? _subscription;
  String? _pendingUrl;

  void _onWindowMessage(final web.MessageEvent event) {
    final source = event.source;
    final frame = _iframe;
    if (source == null || frame == null || frame.contentWindow == null) {
      return;
    }
    if (!source.equals(frame.contentWindow).toDart) {
      return; // another engine's frame or an unrelated message
    }
    final decoded = event.data.dartify();
    if (decoded is Map) {
      onMessage(decoded, slot);
    }
  }

  void _onElementCreated(final Object element) {
    final iframe = element as web.HTMLIFrameElement;
    iframe
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..setAttribute('title', 'eLivre reader slot $slot');
    _iframe = iframe;
    final url = _pendingUrl;
    if (url != null) {
      iframe.src = url;
      _pendingUrl = null;
    }
  }

  @override
  bool get isCreated => _iframe != null;

  @override
  Widget buildWidget() =>
      HtmlElementView.fromTagName(tagName: 'iframe', onElementCreated: _onElementCreated);

  @override
  Future<void> loadUrl(final Uri url) async {
    final frame = _iframe;
    if (frame == null) {
      // The widget has not mounted yet; apply on creation.
      _pendingUrl = url.toString();
      return;
    }
    frame.src = url.toString();
  }

  @override
  Future<void> evaluateJavaScript(final String code) async {
    final frame = _iframe?.contentWindow;
    if (frame == null) {
      return;
    }
    frame.callMethod('eval'.toJS, code.toJS);
  }

  @override
  Future<void> dispose() async {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _iframe?.src = 'about:blank';
    _iframe = null;
  }
}

/// Factory producing [IframeEngine] pairs for Flutter web.
class IframeEngineFactory extends ViewerEngineFactory {
  @override
  ViewerEngine createEngine(
    final int slot,
    final void Function(Object message, int source) onMessage,
  ) => IframeEngine(slot: slot, onMessage: onMessage);

  @override
  List<ViewerEngine> createPair(final void Function(Object message, int source) onMessage) {
    return <ViewerEngine>[
      IframeEngine(slot: 0, onMessage: onMessage),
      IframeEngine(slot: 1, onMessage: onMessage),
    ];
  }
}
