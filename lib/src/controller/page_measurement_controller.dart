import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:unseal/unseal.dart';

import '../features/settings/viewer_settings.dart';

/// The narrow runtime port needed by the page-measurement scheduler.
///
/// This contract keeps the scheduler independent of the reader controller:
/// it can observe lifecycle and position, request one page load, and report a
/// state change, but cannot reach any other controller state.
abstract interface class PageMeasurementHost {
  /// Whether measurement work may currently run.
  bool get pageMeasurementIsActive;

  /// The reading-order index currently visible to the reader.
  int get pageMeasurementCurrentFileIndex;

  /// Loads one reading-order item into the dedicated measurement engine.
  Future<void> loadPageForMeasurement(int fileIndex);

  /// Reports that measured state changed and dependents should refresh.
  void pageMeasurementDidChange();
}

/// Owns book-wide column measurement, cache persistence, and pacing.
final class PageMeasurementController {
  /// Creates a scheduler for [book] backed by the narrow runtime [host].
  PageMeasurementController({required this.book, required this.host});

  /// The book whose reading-order items are measured.
  final Book book;

  /// The only runtime capabilities the scheduler may use.
  final PageMeasurementHost host;

  /// Determines whether measurement is disabled, forward-only, or complete.
  BookPageCountMode pageCountMode = BookPageCountMode.measureAhead;

  /// Delay inserted between completed page measurements.
  Duration batchDelay = const Duration(milliseconds: 250);

  /// Optional host-owned persistent cache loader.
  String? Function(String key)? loadCache;

  /// Optional host-owned persistent cache saver.
  Future<void> Function(String key, String json)? saveCache;

  /// Optional progress observer receiving `(measured, total)`.
  void Function(int measured, int total)? onProgress;

  List<int?> _measuredColumns = <int?>[];
  int _measureCursor = -1;
  String _pageCacheKey = '';
  bool _pageCacheLoaded = false;
  Timer? _measureTimer;
  int _layoutSignature = -1;
  bool _disposed = false;

  final Map<String, List<int?>> _pageCacheByKey = <String, List<int?>>{};

  String get _cacheKey => 'grimoire-pages/$_pageCacheKey/$_layoutSignature';

  /// Immutable view of measured columns; null entries remain estimated.
  List<int?> get columns => List<int?>.unmodifiable(_measuredColumns);

  /// Whether an item is currently loaded for measurement.
  bool get isLoading => _measureCursor >= 0;

  /// Number of measured items and total reading-order items.
  (int, int) get progress {
    final measured = _measuredColumns.where((final count) => count != null).length;
    return (measured, _measuredColumns.length);
  }

  /// Whether [fileIndex] has a real measured column count.
  bool isMeasured(final int fileIndex) =>
      fileIndex >= 0 && fileIndex < _measuredColumns.length && _measuredColumns[fileIndex] != null;

  /// Resets or restores counts when the layout fingerprint changes.
  void refreshLayout({required final int signature, required final String bookFingerprint}) {
    if (_disposed || signature == _layoutSignature) {
      return;
    }
    _layoutSignature = signature;
    _pageCacheKey = '$bookFingerprint/$signature';
    final cached = _pageCacheByKey[_pageCacheKey];
    _measuredColumns = cached != null
        ? [...cached]
        : <int?>[for (var index = 0; index < book.readingOrder.length; index++) null];
    _pageCacheLoaded = true;
    // The host can refresh during layout. Preserve the original
    // microtask boundary before notifications and queue work.
    scheduleMicrotask(() {
      if (_disposed || !host.pageMeasurementIsActive) {
        return;
      }
      host.pageMeasurementDidChange();
      schedule();
    });
  }

  /// Starts or continues the background queue.
  void schedule() {
    if (_disposed ||
        !host.pageMeasurementIsActive ||
        pageCountMode == BookPageCountMode.estimate ||
        _measureCursor >= 0) {
      return;
    }
    unawaited(_loadCacheThenMeasure());
  }

  Future<void> _loadCacheThenMeasure() async {
    if (!_pageCacheLoaded) {
      _pageCacheLoaded = true;
      final loader = loadCache;
      if (loader != null) {
        try {
          final raw = loader(_cacheKey);
          if (raw != null) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              _measuredColumns = <int?>[for (final item in decoded) item is int ? item : null];
              while (_measuredColumns.length < book.readingOrder.length) {
                _measuredColumns.add(null);
              }
              host.pageMeasurementDidChange();
            }
          }
        } on Object {
          // Corrupt cache: fall through and measure.
        }
      }
    }
    unawaited(_measureNext());
  }

  Future<void> _measureNext() async {
    if (_disposed ||
        !host.pageMeasurementIsActive ||
        pageCountMode == BookPageCountMode.estimate ||
        _measureCursor >= 0) {
      return;
    }
    var next = _nextUnmeasured();
    if (next == null) {
      _reportProgress();
      unawaited(_persistCache());
      return;
    }
    if (pageCountMode == BookPageCountMode.measureAhead) {
      final currentFileIndex = host.pageMeasurementCurrentFileIndex;
      if (next < currentFileIndex) {
        next = _nextUnmeasured(from: currentFileIndex);
        if (next == null) {
          _reportProgress();
          return;
        }
      }
    }
    _measureCursor = next;
    try {
      await host.loadPageForMeasurement(next);
    } on Object {
      _measureCursor = -1;
    }
  }

  int? _nextUnmeasured({final int from = 0}) {
    for (var index = from; index < _measuredColumns.length; index++) {
      if (_measuredColumns[index] == null) {
        return index;
      }
    }
    return null;
  }

  Future<void> _persistCache() async {
    _pageCacheByKey[_pageCacheKey] = [..._measuredColumns];
    final saver = saveCache;
    if (saver == null) {
      return;
    }
    try {
      await saver(_cacheKey, jsonEncode([for (final count in _measuredColumns) count]));
    } on Object {
      // Persistence failures are non-fatal.
    }
  }

  /// Records a real count and paces the next measurement.
  Future<void> onReady(final int columns) async {
    final fileIndex = _measureCursor;
    if (_disposed || fileIndex < 0 || fileIndex >= _measuredColumns.length) {
      _measureCursor = -1;
      return;
    }
    _measuredColumns[fileIndex] = math.max(1, columns);
    _measureCursor = -1;
    _reportProgress();
    await _persistCache();
    if (_disposed || !host.pageMeasurementIsActive) {
      return;
    }
    host.pageMeasurementDidChange();
    _measureTimer?.cancel();
    _measureTimer = Timer(batchDelay, _measureNext);
  }

  void _reportProgress() {
    final (measured, total) = progress;
    onProgress?.call(measured, total);
  }

  /// Stops pending paced work and rejects later callbacks.
  void dispose() {
    _disposed = true;
    _measureTimer?.cancel();
  }
}
