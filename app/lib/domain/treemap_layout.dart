import 'dart:math' as math;

/// One thing to draw: [value] is its share (time); the layout gives it an area
/// proportional to it.
class TreemapItem {
  const TreemapItem(this.id, this.value);
  final String id;
  final double value;
}

/// Where an item goes, in the layout's own units (pixels, from the top left).
class TreemapRect {
  const TreemapRect(this.id, this.x, this.y, this.w, this.h);
  final String id;
  final double x;
  final double y;
  final double w;
  final double h;

  double get area => w * h;
  double get right => x + w;
  double get bottom => y + h;
}

/// Squarified treemap (Bruls, Huizing, van Wijk): the items, largest first, are
/// packed into rows along the shorter side of the space that is left, and a row
/// is closed as soon as adding the next item would make its worst rectangle
/// less square. Every rectangle's area is proportional to its value and
/// together they tile `width` x `height` exactly. Items with a value that is
/// zero, negative or not finite are dropped. The order is fixed (value
/// descending, then id), so the same data always gives the same picture.
List<TreemapRect> squarify(
  Iterable<TreemapItem> items, {
  required double width,
  required double height,
}) {
  if (!(width > 0) || !(height > 0)) return const [];
  final sorted = [
    for (final i in items)
      if (i.value > 0 && i.value.isFinite) i,
  ]..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      return byValue != 0 ? byValue : a.id.compareTo(b.id);
    });
  if (sorted.isEmpty) return const [];

  final total = sorted.fold<double>(0, (sum, i) => sum + i.value);
  final areaPerValue = width * height / total;
  final out = <TreemapRect>[];
  var x = 0.0, y = 0.0, w = width, h = height;
  var next = 0;

  while (next < sorted.length) {
    final side = math.min(w, h);
    // The worst aspect ratio of a row with these areas (sorted, largest first).
    double worst(double sum, double largest, double smallest) => math.max(
      side * side * largest / (sum * sum),
      sum * sum / (side * side * smallest),
    );

    var end = next;
    var rowArea = 0.0;
    var best = double.infinity;
    while (end < sorted.length) {
      final area = sorted[end].value * areaPerValue;
      final candidate = worst(
        rowArea + area,
        sorted[next].value * areaPerValue,
        area,
      );
      if (end > next && candidate > best) break;
      rowArea += area;
      best = candidate;
      end++;
    }

    final row = sorted.sublist(next, end);
    final isLastRow = end == sorted.length;
    if (w >= h) {
      // A column on the left, as wide as its area needs.
      final colW = isLastRow ? w : rowArea / h;
      var cy = y;
      for (var k = 0; k < row.length; k++) {
        final ih = k == row.length - 1
            ? y + h - cy
            : row[k].value * areaPerValue / colW;
        out.add(TreemapRect(row[k].id, x, cy, colW, ih));
        cy += ih;
      }
      x += colW;
      w -= colW;
    } else {
      // A row on the top, as tall as its area needs.
      final rowH = isLastRow ? h : rowArea / w;
      var cx = x;
      for (var k = 0; k < row.length; k++) {
        final iw = k == row.length - 1
            ? x + w - cx
            : row[k].value * areaPerValue / rowH;
        out.add(TreemapRect(row[k].id, cx, y, iw, rowH));
        cx += iw;
      }
      y += rowH;
      h -= rowH;
    }
    next = end;
  }
  return out;
}
