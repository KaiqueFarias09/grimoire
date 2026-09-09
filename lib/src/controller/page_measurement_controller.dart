part of 'viewer_controller.dart';

/// The narrow host surface needed by the page-measurement scheduler.
abstract interface class _PageMeasurementHost {
  bool get _pageMeasurementIsActive;

  int get _pageMeasurementCurrentFileIndex;

  Future<void> _loadPageForMeasurement(int fileIndex);

  void _pageMeasurementDidChange();
}

/// Owns book-wide column measurement, cache persistence, and pacing.
class _PageMeasurementController {
  _PageMeasurementController({required this.book, required this.host});

  final Book book;
  final _PageMeasurementHost host;

  BookPageCountMode pageCountMode = BookPageCountMode.measureAhead;
  Duration batchDelay = const Duration(milliseconds: 250);
  String? Function(String key)? loadCache;
  Future<void> Function(String key, String json)? saveCache;
  void Function(int measured, int total)? onProgress;

  List<int?> _measuredColumns = <int?>[];
  int _measureCursor = -1;
  String _pageCacheKey = '';
  bool _pageCacheLoaded = false;
  Timer? _measureTimer;
  int _layoutSignature = -1;
  bool _disposed = false;

  final Map<String, List<int?>> _pageCacheByKey = <String, List<int?>>{};

  String get _cacheKey => 'elivre-pages/$_pageCacheKey/$_layoutSignature';

  List<int?> get columns => List<int?>.unmodifiable(_measuredColumns);

  List<int?> get _rawColumns => _measuredColumns;

  bool get isLoading => _measureCursor >= 0;

  (int, int) get progress {
    final measured = _measuredColumns.where((final count) => count != null).length;
    return (measured, _measuredColumns.length);
  }

  bool isMeasured(final int fileIndex) =>
      fileIndex >= 0 && fileIndex < _measuredColumns.length && _measuredColumns[fileIndex] != null;

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
      if (_disposed || !host._pageMeasurementIsActive) {
        return;
      }
      host._pageMeasurementDidChange();
      schedule();
    });
  }

  /// Starts or continues the background queue.
  void schedule() {
    if (_disposed ||
        !host._pageMeasurementIsActive ||
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
              host._pageMeasurementDidChange();
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
        !host._pageMeasurementIsActive ||
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
      final currentFileIndex = host._pageMeasurementCurrentFileIndex;
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
      await host._loadPageForMeasurement(next);
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
    if (_disposed || !host._pageMeasurementIsActive) {
      return;
    }
    host._pageMeasurementDidChange();
    _measureTimer?.cancel();
    _measureTimer = Timer(batchDelay, _measureNext);
  }

  void _reportProgress() {
    final (measured, total) = progress;
    onProgress?.call(measured, total);
  }

  void dispose() {
    _disposed = true;
    _measureTimer?.cancel();
  }
}
