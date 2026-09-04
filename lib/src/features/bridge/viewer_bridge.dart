import 'dart:ui' show Rect;

import 'dart:async';
import 'dart:convert';

/// Events flowing from the viewer JS to Dart.
///
/// [source] identifies the webview slot that produced the event (0 or
/// 1 — the reader keeps two webviews and preloads into the spare one).
sealed class ViewerEvent {
  const ViewerEvent({this.source = 0});

  final int source;
}

/// The page finished booting (fires once per loaded file).
class ReadyEvent extends ViewerEvent {
  ReadyEvent({required this.chars, required this.columns, super.source});

  final int chars;
  final int columns;
}

/// The visible column / position changed.
class PositionEvent extends ViewerEvent {
  PositionEvent({
    required this.column,
    required this.columns,
    required this.offset,
    required this.chars,
    required this.frac,
    super.source,
  });

  final int column;
  final int columns;
  final int offset;
  final int chars;
  final double frac;
}

/// A page turn hit the start/end of the current file.
class BoundaryEvent extends ViewerEvent {
  BoundaryEvent({
    required this.direction,
    this.exitColumn = 0,
    this.colsPerScreen = 1,
    super.source,
  });

  /// `1` for forward, `-1` for backward.
  final int direction;

  /// Column the reader was on when leaving the file, so coming back
  /// can restore it (Calibre's forward_scroll_data).
  final int exitColumn;

  /// Columns per screen in effect when leaving.
  final int colsPerScreen;
}

/// A wheel pinch/burst asking for a font size step.
class FontSizeBumpEvent extends ViewerEvent {
  FontSizeBumpEvent({required this.delta, super.source});

  /// `1` larger, `-1` smaller.
  final int delta;
}

/// A keyboard shortcut the JS layer resolves to a host-side action.
class ShortcutEvent extends ViewerEvent {
  ShortcutEvent({required this.name, super.source});

  final String name;
}

/// The reader tapped an inline image.
class ViewImageEvent extends ViewerEvent {
  ViewImageEvent({required this.src, super.source});

  final String src;
}

/// The reader tapped a link recognized as a footnote reference.
class FootnoteTapEvent extends ViewerEvent {
  FootnoteTapEvent({required this.href, this.html, this.text, super.source});

  final String href;

  /// The footnote body's raw HTML, resolved by the controller in
  /// footnote popup mode; null in navigate mode or when the body
  /// could not be resolved.
  final String? html;

  /// The footnote body as plain text (popup mode only).
  final String? text;
}

/// The text selection changed (empty [text] means cleared).
class SelectionEvent extends ViewerEvent {
  SelectionEvent({
    required this.text,
    required this.start,
    required this.end,
    this.extents,
    super.source,
  });

  /// Selection bounding rect in document coordinates, when the browser
  /// reported one (drives the anchored selection bar).
  final Rect? extents;

  final String text;
  final int start;
  final int end;
}

/// A link was tapped (external http links are reported, not opened).
class LinkTapEvent extends ViewerEvent {
  LinkTapEvent({required this.href, required this.external, super.source});

  final String href;
  final bool external;
}

/// A highlight was tapped by the user.
class HighlightTapEvent extends ViewerEvent {
  HighlightTapEvent({required this.id, super.source});

  final String id;
}

/// MathJax finished typesetting the loaded page; column layout may
/// have changed, so the reader re-flows and re-measures.
class MathJaxReadyEvent extends ViewerEvent {
  MathJaxReadyEvent({required super.source});
}

/// The viewer resolved a DOM fragment id to its documentText offset
/// (reply to the `locateFragment` action).
class FragmentOffsetEvent extends ViewerEvent {
  FragmentOffsetEvent({required this.id, required this.offset, super.source});

  /// The requested fragment id.
  final String id;

  /// Character offset, or -1 when the id is unknown.
  final int offset;
}

/// The center tap zone asked the host to toggle the chrome.
class ChromeToggleEvent extends ViewerEvent {
  ChromeToggleEvent({super.source});
}

/// Codec + event stream for the viewer bridge.
///
/// Keeps no webview reference: engines receive messages through
/// [accept] and the controller sends commands straight through its
/// engines (`bridge.javaScriptFor` builds the expression).
class ViewerBridge {
  final StreamController<ViewerEvent> _events = StreamController<ViewerEvent>.broadcast();

  /// Stream of typed viewer events.
  Stream<ViewerEvent> get events => _events.stream;

  /// Accepts a raw message from a JavaScript channel: a JSON string
  /// (webview_flutter) or an already-decoded map (inappwebview).
  void accept(final Object payload, {final int source = 0}) {
    Map<String, dynamic>? decoded;
    if (payload is String) {
      try {
        final parsed = jsonDecode(payload);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } on FormatException {
        return;
      }
    } else if (payload is Map) {
      decoded = payload.cast<String, dynamic>();
    }
    if (decoded == null) {
      return;
    }
    final event = _decode(decoded, source);
    if (event != null) {
      _events.add(event);
    }
  }

  /// Builds the JavaScript expression delivering [message] to the
  /// page controller.
  static String javaScriptFor(final Map<String, Object?> message) {
    final payload = jsonEncode(message);
    return 'window.__elivre && window.__elivre($payload)';
  }

  /// Closes the event stream.
  Future<void> dispose() async {
    await _events.close();
  }

  static ViewerEvent? _decode(final Map<String, dynamic> map, final int source) {
    final type = map['type'];
    switch (type) {
      case 'ready':
        return ReadyEvent(
          chars: _asInt(map['chars']),
          columns: _asInt(map['columns']),
          source: source,
        );
      case 'positionChanged':
        return PositionEvent(
          column: _asInt(map['column']),
          columns: _asInt(map['columns']),
          offset: _asInt(map['offset']),
          chars: _asInt(map['chars']),
          frac: _asDouble(map['frac']),
          source: source,
        );
      case 'fileBoundary':
        final direction = _asInt(map['direction']);
        return BoundaryEvent(
          direction: direction >= 0 ? 1 : -1,
          exitColumn: _asInt(map['exitColumn']),
          colsPerScreen: _asInt(map['colsPerScreen']),
          source: source,
        );
      case 'selectionChanged':
        final rawExtents = map['extents'];
        Rect? extents;
        if (rawExtents is Map) {
          extents = Rect.fromLTRB(
            _asDouble(rawExtents['left']),
            _asDouble(rawExtents['top']),
            _asDouble(rawExtents['right']),
            _asDouble(rawExtents['bottom']),
          );
        }
        return SelectionEvent(
          text: map['text'] is String ? map['text'] as String : '',
          start: _asInt(map['start']),
          end: _asInt(map['end']),
          extents: extents,
          source: source,
        );
      case 'linkTap':
        return LinkTapEvent(
          href: map['href'] is String ? map['href'] as String : '',
          external: map['external'] == true,
          source: source,
        );
      case 'highlightTap':
        return HighlightTapEvent(
          id: map['id'] is String ? map['id'] as String : '',
          source: source,
        );
      case 'chromeToggle':
        return ChromeToggleEvent(source: source);
      case 'fontSizeBump':
        return FontSizeBumpEvent(delta: _asInt(map['delta']), source: source);
      case 'viewImage':
        return ViewImageEvent(
          src: map['src'] is String ? map['src'] as String : '',
          source: source,
        );
      case 'footnoteTap':
        return FootnoteTapEvent(
          href: map['href'] is String ? map['href'] as String : '',
          source: source,
        );
      case 'mathjaxReady':
        return MathJaxReadyEvent(source: source);
      case 'fragmentOffset':
        return FragmentOffsetEvent(
          id: map['id'] is String ? map['id'] as String : '',
          offset: _asInt(map['offset']),
          source: source,
        );
      case 'shortcut':
        return ShortcutEvent(
          name: map['name'] is String ? map['name'] as String : '',
          source: source,
        );
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
