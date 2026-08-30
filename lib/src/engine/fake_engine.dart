import 'dart:async';

import 'package:e_livre_viewer/src/engine/viewer_engine.dart';
import 'package:flutter/widgets.dart';

/// A fake engine for tests: records loaded URLs and evaluated
/// scripts without a platform webview.
class FakeViewerEngine extends ViewerEngine {
  FakeViewerEngine({required super.slot, required super.onMessage});

  final List<Uri> loadedUrls = <Uri>[];
  final List<String> scripts = <String>[];
  bool _created = true;

  @override
  bool get isCreated => _created;

  @override
  Widget buildWidget() => const SizedBox.shrink();

  @override
  Future<void> loadUrl(final Uri url) async {
    loadedUrls.add(url);
    // Simulate the page booting and posting its ready message.
    scheduleMicrotask(() {
      onMessage({'type': 'ready', 'chars': 100, 'columns': 5}, slot);
    });
  }

  @override
  Future<void> evaluateJavaScript(final String code) async {
    scripts.add(code);
  }

  @override
  Future<void> dispose() async {
    _created = false;
  }

  /// Simulates the page posting a message back to the controller.
  void postMessage(final Map<String, dynamic> message) {
    onMessage(message, slot);
  }

  /// Simulates the page posting a raw JSON string.
  void postRaw(final String json) {
    onMessage(json, slot);
  }
}

/// Factory producing [FakeViewerEngine] pairs.
class FakeViewerEngineFactory extends ViewerEngineFactory {
  final List<FakeViewerEngine> engines = <FakeViewerEngine>[];

  @override
  @override
  ViewerEngine createEngine(
    final int slot,
    final void Function(Object message, int source) onMessage,
  ) =>
      FakeViewerEngine(slot: slot, onMessage: onMessage);

  List<ViewerEngine> createPair(
    final void Function(Object message, int source) onMessage,
  ) {
    final pair = <FakeViewerEngine>[
      FakeViewerEngine(slot: 0, onMessage: onMessage),
      FakeViewerEngine(slot: 1, onMessage: onMessage),
    ];
    engines.addAll(pair);
    return pair;
  }
}
