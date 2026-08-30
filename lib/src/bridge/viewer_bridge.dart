import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// Events flowing from the viewer JS to Dart.
sealed class ViewerEvent {
  const ViewerEvent();
}

/// The page finished booting (fires once per loaded file).
class ReadyEvent extends ViewerEvent {
  const ReadyEvent({required this.chars, required this.columns});

  final int chars;
  final int columns;
}

/// The visible column / position changed.
class PositionEvent extends ViewerEvent {
  const PositionEvent({
    required this.column,
    required this.columns,
    required this.offset,
    required this.chars,
    required this.frac,
  });

  final int column;
  final int columns;
  final int offset;
  final int chars;
  final double frac;
}

/// A page turn hit the start/end of the current file.
class BoundaryEvent extends ViewerEvent {
  const BoundaryEvent({required this.direction});

  /// `1` for forward, `-1` for backward.
  final int direction;
}

/// The text selection changed (empty [text] means cleared).
class SelectionEvent extends ViewerEvent {
  const SelectionEvent({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final int start;
  final int end;
}

/// A link was tapped (external http links are reported, not opened).
class LinkTapEvent extends ViewerEvent {
  const LinkTapEvent({required this.href, required this.external});

  final String href;
  final bool external;
}

/// The center tap zone asked the host to toggle the chrome.
class ChromeToggleEvent extends ViewerEvent {
  const ChromeToggleEvent();
}

/// Typed bridge between the viewer JS and Dart.
///
/// Incoming messages arrive through the `ELivreBridge` JavaScript
/// channel ([acceptRaw]); outgoing messages call `window.__elivre`
/// via [WebViewController.runJavaScript].
class ViewerBridge {
  final StreamController<ViewerEvent> _events =
      StreamController<ViewerEvent>.broadcast();

  /// Stream of typed viewer events.
  Stream<ViewerEvent> get events => _events.stream;

  WebViewController? _controller;
  bool _attached = false;

  /// Wires the bridge to a live webview.
  void attach(final WebViewController controller) {
    _controller = controller;
    _attached = true;
  }

  /// Whether [attach] was called.
  bool get isAttached => _attached;

  /// Parses a raw JSON message from the JavaScript channel.
  void acceptRaw(final String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final event = _decode(decoded);
      if (event != null) {
        _events.add(event);
      }
    } on FormatException {
      // Ignore malformed payloads.
    }
  }

  /// Sends an action message to the current page.
  Future<void> send(final Map<String, Object?> message) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final payload = jsonEncode(message);
    await controller.runJavaScript('window.__elivre && window.__elivre($payload)');
  }

  /// Closes the event stream.
  Future<void> dispose() async {
    await _events.close();
    _controller = null;
  }

  static ViewerEvent? _decode(final Map<String, dynamic> map) {
    final type = map['type'];
    switch (type) {
      case 'ready':
        return ReadyEvent(
          chars: _asInt(map['chars']),
          columns: _asInt(map['columns']),
        );
      case 'positionChanged':
        return PositionEvent(
          column: _asInt(map['column']),
          columns: _asInt(map['columns']),
          offset: _asInt(map['offset']),
          chars: _asInt(map['chars']),
          frac: _asDouble(map['frac']),
        );
      case 'fileBoundary':
        final direction = _asInt(map['direction']);
        return BoundaryEvent(direction: direction >= 0 ? 1 : -1);
      case 'selectionChanged':
        return SelectionEvent(
          text: map['text'] is String ? map['text'] as String : '',
          start: _asInt(map['start']),
          end: _asInt(map['end']),
        );
      case 'linkTap':
        return LinkTapEvent(
          href: map['href'] is String ? map['href'] as String : '',
          external: map['external'] == true,
        );
      case 'chromeToggle':
        return const ChromeToggleEvent();
      default:
        return null;
    }
  }

  static int _asInt(final Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _asDouble(final Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
