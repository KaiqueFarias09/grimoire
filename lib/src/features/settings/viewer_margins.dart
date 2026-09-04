import 'package:flutter/foundation.dart';

/// Per-side page margins in pixels (Calibre's margin_left/top/right/
/// bottom). In paged mode the left+right pair (horizontal writing) or
/// top+bottom pair (vertical writing) doubles as the column gap, and
/// the sides inset the rendered page; [maxTextWidth] and
/// [maxTextHeight] cap the text block by growing the insets instead
/// of shrinking the page (Calibre `View.set_margins`).
@immutable
class ViewerMargins {
  /// Creates margins; negative values are clamped to 0.
  const ViewerMargins({
    final int left = 20,
    final int top = 20,
    final int right = 20,
    final int bottom = 20,
    final int maxTextWidth = 0,
    final int maxTextHeight = 0,
  }) : left = left < 0 ? 0 : left,
       top = top < 0 ? 0 : top,
       right = right < 0 ? 0 : right,
       bottom = bottom < 0 ? 0 : bottom,
       maxTextWidth = maxTextWidth < 0 ? 0 : maxTextWidth,
       maxTextHeight = maxTextHeight < 0 ? 0 : maxTextHeight;

  /// Uniform margins on all four sides.
  factory ViewerMargins.uniform(final int px) =>
      ViewerMargins(left: px, top: px, right: px, bottom: px);

  /// The four sides as an [EdgeInsets]-shaped record (left, top,
  /// right, bottom) after applying the max-text caps against a
  /// [availableWidth] x [availableHeight] viewport. Calibre grows the
  /// margin strips so the text block never exceeds the caps.
  ({double left, double top, double right, double bottom}) insetsFor({
    required final double availableWidth,
    required final double availableHeight,
  }) {
    var l = left.toDouble();
    var t = top.toDouble();
    var r = right.toDouble();
    var b = bottom.toDouble();
    final textWidth = availableWidth - l - r;
    if (maxTextWidth > 100 && textWidth > maxTextWidth) {
      final extra = ((textWidth - maxTextWidth) / 2).floorToDouble();
      l += extra;
      r += extra;
    }
    final textHeight = availableHeight - t - b;
    if (maxTextHeight > 100 && textHeight > maxTextHeight) {
      final extra = ((textHeight - maxTextHeight) / 2).floorToDouble();
      t += extra;
      b += extra;
    }
    return (left: l, top: t, right: r, bottom: b);
  }

  /// Left margin (px).
  final int left;

  /// Top margin (px).
  final int top;

  /// Right margin (px).
  final int right;

  /// Bottom margin (px).
  final int bottom;

  /// Maximum text block width (px); 0 = unlimited. Values ≤ 100 are
  /// ignored (Calibre's threshold).
  final int maxTextWidth;

  /// Maximum text block height (px); 0 = unlimited.
  final int maxTextHeight;

  /// Restores from JSON ([toJson]).
  static ViewerMargins? fromJson(final Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    bool isInt(final Object? value) => value is int && value >= 0;
    if (!isInt(json['left']) ||
        !isInt(json['top']) ||
        !isInt(json['right']) ||
        !isInt(json['bottom']) ||
        !isInt(json['maxTextWidth']) ||
        !isInt(json['maxTextHeight'])) {
      return null;
    }
    return ViewerMargins(
      left: json['left'] as int,
      top: json['top'] as int,
      right: json['right'] as int,
      bottom: json['bottom'] as int,
      maxTextWidth: json['maxTextWidth'] as int,
      maxTextHeight: json['maxTextHeight'] as int,
    );
  }

  /// JSON for host persistence.
  Map<String, int> toJson() => <String, int>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'maxTextWidth': maxTextWidth,
    'maxTextHeight': maxTextHeight,
  };

  @override
  bool operator ==(final Object other) =>
      other is ViewerMargins &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.maxTextWidth == maxTextWidth &&
      other.maxTextHeight == maxTextHeight;

  @override
  int get hashCode => Object.hash(left, top, right, bottom, maxTextWidth, maxTextHeight);

  @override
  String toString() =>
      'ViewerMargins(l: $left, t: $top, r: $right, b: $bottom, '
      'maxW: $maxTextWidth, maxH: $maxTextHeight)';
}
