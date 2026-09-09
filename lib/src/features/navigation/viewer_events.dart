import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:flutter/foundation.dart';

/// A page turn: the visible location moved to another page (paged
/// mode), chapter (any mode), or whole-percent progress (scroll
/// mode). Persist reading progress from here instead of polling.
@immutable
class ViewerPageChange {
  /// Creates a page change.
  const ViewerPageChange({required this.position, required this.progress, this.chapterTitle});

  /// The new reading location.
  final ViewerPosition position;

  /// Book-wide progress `0..1` at the new location.
  final double progress;

  /// TOC section covering the new location, when the book's
  /// navigation has a titled entry for it.
  final String? chapterTitle;
}

/// One stretch of active reading, for time tracking and Insights. A
/// segment opens on the first reading event and closes after the controller's
/// `readingIdleTimeout` without one, when a segment exceeds the internal cap,
/// or when the controller is disposed.
@immutable
class ReadingSessionEvent {
  /// Creates a reading session segment.
  const ReadingSessionEvent({required this.startedAt, required this.endedAt});

  /// When the segment opened.
  final DateTime startedAt;

  /// When the last reading event of the segment arrived.
  final DateTime endedAt;

  /// Active reading time in the segment.
  Duration get duration => endedAt.difference(startedAt);
}
